import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart'; 
import 'dart:io';
import 'package:isar/isar.dart';

import '../services/gemini_service.dart';
import '../models/recording.dart'; 
import 'share_screen.dart';
import '../services/s3upload_service.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import '../services/get_idtoken_service.dart';

class ResultScreen extends StatefulWidget {
  final Recording recording;

  const ResultScreen({super.key, required this.recording});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();
  final S3UploadService _s3UploadService = S3UploadService();
  
  late TextEditingController _textController;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = false;

  bool _isImage = false;

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
    
    final path = widget.recording.filePath.toLowerCase();
    _isImage = path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');

    _textController = TextEditingController(
      text: (widget.recording.transcription != null && widget.recording.transcription!.isNotEmpty)
          ? widget.recording.transcription
          : "（ボタンを押して解析を開始してください）" // 文言を少し変更
    );

    if (!_isImage) {
      _initAudioPlayer();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }

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

  Future<void> _saveData() async {
    final isar = Isar.getInstance();
    if (isar != null) {
      await isar.writeTxn(() async {
        widget.recording.transcription = _textController.text;
        await isar.recordings.put(widget.recording);
      });
      print("データを保存しました");
    }
  }

  Future<void> _runGeminiTask(Future<String> Function() task) async {
    setState(() => _isLoading = true);
    final result = await task();
    setState(() {
      _textController.text = result;
      _isLoading = false;
    });
    await _saveData();
  }

  Future<void> _showTranslationDialog() async {
    final currentText = _textController.text;
    if (currentText.isEmpty || currentText.startsWith("（")) {
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
                    _textController.text, 
                    targetLang: entry.value,
                  ),
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

  Future<void> s3Upload() async {
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
      final result = await uploadService.uploadAudioFile(file, idToken: token);
      final fileId = result['file_id'];
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アップロード完了 (ID: $fileId)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, 
      onPopInvoked: (didPop) async {
        if (didPop) {
          await _saveData(); 
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.recording.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                _saveData();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShareScreen(textContent: _textController.text),
                  ),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(widget.recording.filePath),
                          height: 200,
                          fit: BoxFit.contain,
                          errorBuilder: (c, o, s) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
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
                              const SizedBox(width: 10),
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
                                Text(_formatDuration(_position), style: TextStyle(color: Colors.blue.shade900)),
                                Text(_formatDuration(_duration), style: TextStyle(color: Colors.blue.shade900)),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              
              const SizedBox(height: 10),
              Text(widget.recording.filePath, 
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // ★修正: 1つのボタンで画像・音声を分岐実行
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () {
                        if (_isImage) {
                          // 画像の場合: OCRを実行
                          _runGeminiTask(
                            () => _geminiService.transcribeImage(File(widget.recording.filePath))
                          );
                        } else {
                          // 音声の場合: 文字起こしを実行
                          _runGeminiTask(
                            () => _geminiService.transcribeAudio(widget.recording.filePath)
                          );
                        }
                      },
                      // アイコンとラベルも切り替えるとお洒落です
                      icon: Icon(_isImage ? Icons.image_search : Icons.mic),
                      label: Text(_isImage ? '文字認識' : '文字起こし'),
                    ),
                    const SizedBox(width: 10),
                    
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _runGeminiTask(
                        () => _geminiService.summarizeText(_textController.text)
                      ),
                      icon: const Icon(Icons.summarize),
                      label: const Text('要約'),
                    ),
                    const SizedBox(width: 10),

                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : s3Upload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('S3 Upload'),
                    ),
                    const SizedBox(width: 10),

                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _showTranslationDialog,
                      icon: const Icon(Icons.translate),
                      label: const Text('翻訳'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}