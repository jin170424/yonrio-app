import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:isar/isar.dart';
import 'dart:io';
// Dioを追加
import 'package:dio/dio.dart';
// スクロール制御用
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
// ネットワークチェック用
import 'package:voice_app/utils/network_utils.dart';

import 'package:voice_app/repositories/recording_repository.dart';
import '../services/gemini_service.dart';
import '../models/recording.dart';
import 'share_screen.dart';
import '../services/s3upload_service.dart';
import '../services/get_idtoken_service.dart';
import '../main.dart'; // isarインスタンス取得用

enum DisplayMode { transcription, summary }

class ResultScreen extends StatefulWidget {
  final Recording recording;
  final String? searchQuery; // ホーム画面から引き継いだ検索ワード

  const ResultScreen({
    super.key, 
    required this.recording,
    this.searchQuery, 
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();
  late final RecordingRepository _repository;

  // Stream & UI State
  late Stream<Recording?> _recordingStream;
  DisplayMode _currentMode = DisplayMode.transcription;
  bool _isProcessing = false; // 同期・保存中のローディング判定用
  bool _isLoading = false;    // Gemini処理中の判定用

  // 検索機能用のステート
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchBarVisible = false; // 検索バーを表示しているか
  String? _previousJumpQuery;       // 前回スクロールジャンプした時のキーワード（無限ループ防止用）

  // Audio Player & Image State
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isImage = false;
  
  // 翻訳用言語マップ
  final Map<String, String> _targetLanguages = {
    '英語': 'English',
    '中国語': 'Simplified Chinese',
    '韓国語': 'Korean',
    'スペイン語': 'Spanish',
    'フランス語': 'French',
    'ドイツ語': 'German',
  };

  // 自動スクロール用コントローラー
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    final isar = Isar.getInstance(); 
    if (isar != null) {
      // Dioを渡して初期化
      _repository = RecordingRepository(isar: isar, dio: Dio());
      _recordingStream = isar.recordings.watchObject(widget.recording.id, fireImmediately: true);
    }

    // 初期検索ワードの設定
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      _searchController.text = widget.searchQuery!;
      _isSearchBarVisible = true;
    }
    
    // 画像判定
    final path = widget.recording.filePath.toLowerCase();
    _isImage = path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');

    // プレイヤー初期化
    if (!_isImage) {
      _initAudioPlayer();
    }

    _autoSyncIfNeeded();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- Audio Player Logic ---
  Future<void> _initAudioPlayer() async {
    try {
      if (await File(widget.recording.filePath).exists()) {
        _audioPlayer.positionStream.listen((p) {
          if (mounted) setState(() => _position = p);
        });
        _audioPlayer.durationStream.listen((d) {
          if (mounted) setState(() => _duration = d ?? Duration.zero);
        });
        _audioPlayer.playerStateStream.listen((state) {
          if (mounted) {
            setState(() {
              _isPlaying = state.playing;
            });
            if (state.processingState == ProcessingState.completed) {
              _audioPlayer.seek(Duration.zero);
              _audioPlayer.pause();
            }
          }
        });
        await _audioPlayer.setFilePath(widget.recording.filePath);
      }
    } catch (e) {
      print("オーディオ読み込みエラー: $e");
    }
  }

  void _togglePlay() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // --- Sync Logic ---
  Future<void> _autoSyncIfNeeded() async {
    final isar = Isar.getInstance();
    if (isar == null) return;
    
    final recording = await isar.recordings.get(widget.recording.id);
    if (recording == null || recording.remoteId == null || recording.status == 'pending') return;

    // 同期フラグがある場合は手動同期へ誘導または自動アップロード
    if (recording.needsCloudUpdate) {
      print("ローカル変更があるため自動同期をスキップしてアップロードを試みます");
      return;
    }

    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();
      if (token != null) {
        await _repository.syncTranscriptionAndSummary(recording, token);
      }
    } catch (e) {
      print("バックグラウンド同期失敗 (無視可): $e");
    }
  }

  Future<void> _manualSync() async {
    // ネットワークチェック付き実行
    runWithNetworkCheck(
      context: context, 
      action: () async {
        setState(() => _isProcessing = true);
        final isar = Isar.getInstance();
        if (isar != null) {
          final recording = await isar.recordings.get(widget.recording.id);
          if (recording != null) {
            try {
                final tokenService = GetIdtokenService();
                final token = await tokenService.getIdtoken();
                if (token == null) throw Exception("ログインが必要です");
                
                // クラウド更新が必要な場合(taki機能)はアップロードを実行
                if (recording.needsCloudUpdate) {
                   print("変更をアップロード中...");
                   await _repository.updateRecording(recording, token, syncTranscripts: true);
                   await isar.writeTxn(() async {
                     recording.needsCloudUpdate = false;
                     await isar.recordings.put(recording);
                   });
                }

                // ダウンロード同期
                await _repository.syncTranscriptionAndSummary(recording, token);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同期完了')));
                }
            } catch (e) {
              if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同期エラー: $e')));
                }
            }
          }
        }
        setState(() => _isProcessing = false);
      }
    );
  }

  // --- S3 Upload Logic ---
  Future<void> s3Upload(String title) async {
    setState(() => _isProcessing = true);
    
    final file = File(widget.recording.filePath);
    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();

      if (token == null) {
        throw Exception('ログインが必要です');
      }

      final uploadService = S3UploadService();
      String? existingId = widget.recording.remoteId;
      
      final result = await uploadService.uploadAudioFile(
        file, 
        title,
        idToken: token,
        recordingId: existingId,
      );

      final recordingId = result['recording_id'];
      final s3Key = result['s3_key'];
      
      final isar = Isar.getInstance();
      if (isar != null) {
        await isar.writeTxn(() async {
          widget.recording.remoteId = recordingId;
          if (s3Key != null) {
             widget.recording.s3AudioUrl = s3Key;
          }
          widget.recording.status = 'processing'; 
          await isar.recordings.put(widget.recording);
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アップロード完了 (ID: $recordingId)')),
      );

    } catch (e) {
      print("アップロード失敗: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // --- Gemini / Translation Logic ---
  Future<void> _runGeminiTask(Future<String> Function() task, Recording recording) async {
    setState(() => _isLoading = true);
    try {
      final result = await task();
      
      final isar = Isar.getInstance();
      if (isar != null) {
        await isar.writeTxn(() async {
          recording.transcription = result;
          recording.needsCloudUpdate = true; // AI処理後は同期フラグを立てる
          await isar.recordings.put(recording);
        });
      }
    } catch (e) {
      print("Geminiエラー: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("エラー: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showTranslationDialog(Recording recording) async {
    final currentText = recording.transcription ?? "";
    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('翻訳するテキストがありません')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('翻訳先の言語を選択'),
          children: _targetLanguages.entries.map((entry) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                _runGeminiTask(
                  () => _geminiService.translateText(
                    currentText, 
                    targetLang: entry.value,
                  ),
                  recording
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(entry.key, style: const TextStyle(fontSize: 16)),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // --- UI Helpers ---

  // ハイライト表示用
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) return Text(text, style: const TextStyle(fontSize: 15, height: 1.4));

    final List<TextSpan> spans = [];
    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    int start = 0;
    
    while (true) {
      final int index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: const TextStyle(
          backgroundColor: Colors.yellow, 
          fontWeight: FontWeight.bold,
        ),
      ));
      
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.black),
        children: spans,
      ),
    );
  }

  // コンパクトなモード切り替えボタン
  Widget _buildModeBtn(String label, DisplayMode mode) {
    final bool isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _currentMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // --- View Builders ---
  Widget _buildTranscriptionList(Recording recording) {
    final segments = recording.transcripts.toList();

    if (segments.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          (recording.transcription != null && recording.transcription!.isNotEmpty)
            ? recording.transcription!
            : "文字起こしデータがありません",
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
      );
    }

    segments.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));

    // 検索ワードが変わった時だけスクロール処理
    final currentQuery = _searchController.text;
    if (currentQuery.isNotEmpty && currentQuery != _previousJumpQuery) {
      final index = segments.indexWhere((s) => 
        s.text.toLowerCase().contains(currentQuery.toLowerCase())
      );
      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if(_itemScrollController.isAttached) {
             _itemScrollController.jumpTo(index: index);
          }
        });
        _previousJumpQuery = currentQuery;
      }
    } else if (currentQuery.isEmpty) {
      _previousJumpQuery = null;
    }

    return ScrollablePositionedList.builder(
      itemCount: segments.length,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      itemBuilder: (context, index) {
        final segment = segments[index];
        final bool isMatch = (currentQuery.isNotEmpty &&
            segment.text.toLowerCase().contains(currentQuery.toLowerCase()));

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ★修正箇所: 発言者名の横に再生ボタンを追加
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                child: Row(
                  children: [
                    Text(
                      segment.speaker,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color:Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 再生ボタン (taki機能)
                    if (!_isImage) // 音声ファイルの時のみ表示
                      InkWell(
                        onTap: () async {
                          // その位置までシークして再生
                          await _audioPlayer.seek(Duration(milliseconds: segment.startTimeMs));
                          if (!_isPlaying) {
                            _audioPlayer.play();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow, size: 16, color: Colors.blueAccent),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMatch ? Colors.yellow.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: isMatch 
                      ? Border.all(color: Colors.orange, width: 2)
                      : Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: _buildHighlightedText(segment.text, currentQuery),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryView(Recording recording) {
    final text = (recording.summary != null && recording.summary!.isNotEmpty) 
            ? recording.summary!
            : "要約はまだありません (同期中または生成待ち)";
            
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
           color: Colors.orange.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: _buildHighlightedText(text, _searchController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Recording?>(
      stream: _recordingStream, 
      builder: (context, snapshot){
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting){
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        final recording = snapshot.data;
        if (recording == null) {
          return const Scaffold(body: Center(child: Text('データが見つかりません')));
        }

        final String shareContent = "【要約】\n${recording.summary ?? 'なし'}\n\n【全文】\n${recording.transcription ?? 'なし'}";

        // アクションボタン（保存 or 同期）
        Widget actionButton;
        if (_isProcessing) {
           actionButton = const Padding(
             padding: EdgeInsets.all(12.0),
             child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
           );
        } else if (recording.status == 'pending' || recording.remoteId == null) {
          actionButton = IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'クラウドに保存',
            onPressed: () => s3Upload(recording.title),
          );
        } else {
          actionButton = IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'クラウドから結果を取得',
            onPressed: () => _manualSync(),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(recording.title),
            actions: [
              actionButton,
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ShareScreen(textContent: shareContent),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. プレイヤー / 画像表示エリア
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                decoration: BoxDecoration(color: Colors.grey.shade50),
                child: _isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(recording.filePath),
                          height: 200,
                          fit: BoxFit.contain,
                          errorBuilder: (c, o, s) => const SizedBox(height:100, child: Center(child: Icon(Icons.broken_image))),
                        ),
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                iconSize: 40,
                                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                                color: Colors.blue,
                                onPressed: _togglePlay,
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3.0, 
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0), 
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: _duration.inMilliseconds.toDouble(),
                                    value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                                    onChanged: (value) {
                                      _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(_position), style: const TextStyle(fontSize: 12)),
                                Text(_formatDuration(_duration), style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),

              // 2. 検索バー (トグル表示)
              if (_isSearchBarVisible)
                Container(
                  color: Colors.grey.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'ページ内検索...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                             _previousJumpQuery = null;
                          });
                        },
                      ),
                    ),
                    onChanged: (val) => setState((){}),
                  ),
                ),

              // 3. コンパクトコントロールバー
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    // 検索ボタン (トグル)
                    IconButton(
                      icon: Icon(_isSearchBarVisible ? Icons.expand_less : Icons.search),
                      tooltip: _isSearchBarVisible ? "検索を閉じる" : "検索",
                      color: _isSearchBarVisible ? Colors.blue : Colors.grey[700],
                      onPressed: () {
                        setState(() {
                          _isSearchBarVisible = !_isSearchBarVisible;
                          if (!_isSearchBarVisible) {
                            _searchController.clear();
                            _previousJumpQuery = null;
                          }
                        });
                      },
                    ),
                    
                    const Spacer(),
                    
                    // モード切り替え (セグメントボタン風)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _buildModeBtn("文字起こし", DisplayMode.transcription),
                          _buildModeBtn("要約", DisplayMode.summary),
                        ],
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // 翻訳ボタン
                    IconButton(
                      icon: const Icon(Icons.translate),
                      tooltip: "翻訳",
                      color: Colors.grey[700],
                      onPressed: _isLoading ? null : () => _showTranslationDialog(recording),
                    ),
                    
                    if (_isImage)
                       IconButton(
                         icon: const Icon(Icons.refresh), 
                         tooltip: "再解析",
                         color: Colors.grey[700],
                         onPressed: () => _runGeminiTask(() => _geminiService.transcribeImage(File(recording.filePath)), recording),
                       ),
                  ],
                ),
              ),

              // 4. コンテンツ表示エリア
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : _currentMode == DisplayMode.summary
                    ? _buildSummaryView(recording)
                    : _buildTranscriptionList(recording),
              ),
            ],
          ),
        );
      },
    );
  }
}