import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:isar/isar.dart';
import 'dart:io';
// ★追加: スクロール制御用
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
  final String? searchQuery; // ★追加: 検索ワード受け取り

  const ResultScreen({
    super.key, 
    required this.recording,
    this.searchQuery, // コンストラクタに追加
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
  bool _isProcessing = false;
  bool _isLoading = false;

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

  // ★追加: 自動スクロール用コントローラー
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    final isar = Isar.getInstance(); 
    if (isar != null) {
      _repository = RecordingRepository(isar);
      // ストリームセットアップ
      _recordingStream = isar.recordings.watchObject(widget.recording.id, fireImmediately: true);
    }
    
    // 画像判定
    final path = widget.recording.filePath.toLowerCase();
    _isImage = path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');

    // プレイヤー初期化
    if (!_isImage) {
      _initAudioPlayer();
    }

    // 自動同期
    _autoSyncIfNeeded();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
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
    if (recording == null || recording.remoteId == null) return;

    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();
      if (token != null) {
        await _repository.syncTranscriptionAndSummary(recording, token);
        if (mounted) {
          // 同期完了メッセージは頻繁に出すと煩わしいので抑制してもOK
          // ScaffoldMessenger.of(context).showSnackBar(...);
        }
      }
    } catch (e) {
      print("バックグラウンド同期失敗 (無視可): $e");
    }
  }

  Future<void> _manualSync() async {
    setState(() => _isProcessing = true);
    final isar = Isar.getInstance();
    if (isar != null) {
      final recording = await isar.recordings.get(widget.recording.id);
      if (recording != null) {
        try {
            final tokenService = GetIdtokenService();
            final token = await tokenService.getIdtoken();
            if (token == null) throw Exception("ログインが必要です");
            
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

  // --- S3 Upload Logic ---
  Future<void> s3Upload(String title) async {
    final file = File(widget.recording.filePath);
    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();

      if (token == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインが必要です')),
        );
        return;
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
      
      final isar = Isar.getInstance();
      if (isar != null && widget.recording.remoteId == null) {
        await isar.writeTxn(() async {
          widget.recording.remoteId = recordingId;
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

  // ★追加: ハイライト表示用のテキスト生成メソッド
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
          backgroundColor: Colors.yellow, // ハイライト色
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

  // --- View Builders ---
  Widget _buildTranscriptionList(Recording recording) {
    final segments = recording.transcripts.toList();

    // セグメントがない場合は全文テキストを表示
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

    // ★追加: 最初にマッチするインデックスを探してスクロール
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      final index = segments.indexWhere((s) => 
        s.text.toLowerCase().contains(widget.searchQuery!.toLowerCase())
      );
      if (index != -1) {
        // 描画後にジャンプさせる
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if(_itemScrollController.isAttached) {
             _itemScrollController.jumpTo(index: index);
          }
        });
      }
    }

    // ★変更: ScrollablePositionedListに変更
    return ScrollablePositionedList.builder(
      itemCount: segments.length,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      itemBuilder: (context, index) {
        final segment = segments[index];
        
        // ★ハイライト判定
        final bool isMatch = (widget.searchQuery != null && widget.searchQuery!.isNotEmpty &&
            segment.text.toLowerCase().contains(widget.searchQuery!.toLowerCase()));

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                child: Text(
                  segment.speaker,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color:Colors.grey,
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // ヒットしている場合は背景を少し黄色くし、枠線をオレンジにする
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
                // テキストハイライト関数を使用
                child: widget.searchQuery != null 
                    ? _buildHighlightedText(segment.text, widget.searchQuery!)
                    : Text(
                        segment.text,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
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
        child: Text(text, style: const TextStyle(fontSize: 16)),
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

        return Scaffold(
          appBar: AppBar(
            title: Text(recording.title),
            actions: [
              if (recording.remoteId != null)
                IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: 'クラウドから結果を取得',
                  onPressed: _isProcessing ? null : () => _manualSync(),
                ),
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
                padding: const EdgeInsets.all(8),
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
                                child: Slider(
                                  min: 0,
                                  max: _duration.inMilliseconds.toDouble(),
                                  value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                                  onChanged: (value) {
                                    _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                  },
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(_position)),
                                Text(_formatDuration(_duration)),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),

              // 2. 操作ボタンエリア
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _currentMode = DisplayMode.transcription),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentMode == DisplayMode.transcription ? Colors.blue[100] : null,
                      ),
                      icon: const Icon(Icons.description),
                      label: const Text('文字起こし'),
                    ),
                    const SizedBox(width: 10),
                    
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _currentMode = DisplayMode.summary),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentMode == DisplayMode.summary ? Colors.blue[100] : null,
                      ),
                      icon: const Icon(Icons.summarize),
                      label: const Text('要約'),
                    ),
                    const SizedBox(width: 10),

                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => s3Upload(recording.title),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('保存'),
                    ),
                    const SizedBox(width: 10),

                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _showTranslationDialog(recording),
                      icon: const Icon(Icons.translate),
                      label: const Text('翻訳'),
                    ),
                    
                    if (_isImage)
                       Padding(
                         padding: const EdgeInsets.only(left: 10),
                         child: IconButton(
                           icon: const Icon(Icons.refresh), 
                           tooltip: "再解析",
                           onPressed: () => _runGeminiTask(() => _geminiService.transcribeImage(File(recording.filePath)), recording),
                         ),
                       ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 3. コンテンツ表示エリア
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