import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart'; // HEAD由来
import 'package:isar/isar.dart';
import 'dart:io';

// Main由来
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

  const ResultScreen({super.key, required this.recording});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();
  late final RecordingRepository _repository;

  // Stream & UI State (Main由来)
  late Stream<Recording?> _recordingStream;
  DisplayMode _currentMode = DisplayMode.transcription;
  bool _isProcessing = false;
  bool _isLoading = false;

  // Audio Player & Image State (HEAD由来)
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isImage = false;
  
  // 翻訳用言語マップ (HEAD由来)
  final Map<String, String> _targetLanguages = {
    '英語': 'English',
    '中国語': 'Simplified Chinese',
    '韓国語': 'Korean',
    'スペイン語': 'Spanish',
    'フランス語': 'French',
    'ドイツ語': 'German',
  };

  @override
  void initState() {
    super.initState();
    final isar = Isar.getInstance(); // main.dart等で確保されている前提
    if (isar != null) {
      _repository = RecordingRepository(isar);
      // ストリームセットアップ
      _recordingStream = isar.recordings.watchObject(widget.recording.id, fireImmediately: true);
    }
    
    // 画像判定 (HEAD由来)
    final path = widget.recording.filePath.toLowerCase();
    _isImage = path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');

    // プレイヤー初期化 (HEAD由来)
    if (!_isImage) {
      _initAudioPlayer();
    }

    // 自動同期 (Main由来)
    _autoSyncIfNeeded();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- Audio Player Logic (HEAD由来) ---
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

  // --- Sync Logic (Main由来) ---
  Future<void> _autoSyncIfNeeded() async {
    final isar = Isar.getInstance();
    if (isar == null) return;
    
    final recording = await isar.recordings.get(widget.recording.id);
    if (recording == null || recording.remoteId == null) return;

    print("バックグラウンド同期を開始...");
    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();
      if (token != null) {
        await _repository.syncTranscriptionAndSummary(recording, token);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('最新データを取得しました'), duration: Duration(seconds: 1)),
          );
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

  // --- S3 Upload Logic (Main由来 - より堅牢) ---
  Future<void> s3Upload(String title) async {
    final file = File(widget.recording.filePath);
    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();

      if (token == null) {
        print("トークンが取得できませんでした（未ログイン）");
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
      
      // Isar更新
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

  // --- Gemini / Translation Logic (HEAD & Main統合) ---
  Future<void> _runGeminiTask(Future<String> Function() task, Recording recording) async {
    setState(() => _isLoading = true);
    try {
      final result = await task();
      
      // 結果を保存
      final isar = Isar.getInstance();
      if (isar != null) {
        await isar.writeTxn(() async {
          // ※簡易的にtranscriptionに入れる（本来はリスト構造への変換が望ましいが、一旦文字列として保存）
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

  // --- View Builders (Main由来) ---
  Widget _buildTranscriptionList(Recording recording) {
    final segments = recording.transcripts.toList();

    // セグメントがない場合は全文テキストを表示 (HEADの互換性)
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

    return ListView.builder(
      itemCount: segments.length,
      padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      itemBuilder: (context, index) {
        final segment = segments[index];
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Text(
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
    // MainのStreamBuilder構造を採用
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
              // 1. プレイヤー / 画像表示エリア (HEADのデザインを採用)
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

              // 2. 操作ボタンエリア (MainとHEADを統合)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // 文字起こしモード
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _currentMode = DisplayMode.transcription),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentMode == DisplayMode.transcription ? Colors.blue[100] : null,
                      ),
                      icon: const Icon(Icons.description),
                      label: const Text('文字起こし'),
                    ),
                    const SizedBox(width: 10),
                    
                    // 要約モード
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _currentMode = DisplayMode.summary),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentMode == DisplayMode.summary ? Colors.blue[100] : null,
                      ),
                      icon: const Icon(Icons.summarize),
                      label: const Text('要約'),
                    ),
                    const SizedBox(width: 10),

                    // クラウドアップロード
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

                    // 翻訳 (HEADの機能)
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _showTranslationDialog(recording),
                      icon: const Icon(Icons.translate),
                      label: const Text('翻訳'),
                    ),
                    
                    // ローカル処理 (HEADの機能: 必要な場合)
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

              // 3. コンテンツ表示エリア (Mainのロジックを採用)
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