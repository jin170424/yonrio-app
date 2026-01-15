import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart'; // 再生用ライブラリ
import 'dart:io';

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
  
  // ★プレイヤー関連の変数
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero; // 全体の長さ
  Duration _position = Duration.zero; // 現在の再生位置
  
  String _displayText = "（文字起こしボタンを押してください）";
  bool _isLoading = false;

  // ★追加: 対応言語リスト (表示名 : Geminiに渡す英語名)
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
    _initAudioPlayer();
  }

  // ★音声ファイルのセットアップとイベント監視
  Future<void> _initAudioPlayer() async {
    try {
      if (await File(widget.recording.filePath).exists()) {
        
        // 1. 再生位置（シークバー用）の監視
        _audioPlayer.positionStream.listen((p) {
          if (mounted) setState(() => _position = p);
        });

        // 2. 音声の長さの監視
        _audioPlayer.durationStream.listen((d) {
          if (mounted) setState(() => _duration = d ?? Duration.zero);
        });

        // 3. 再生状態（再生中/停止中）の監視
        _audioPlayer.playerStateStream.listen((state) {
          if (mounted) {
            setState(() {
              _isPlaying = state.playing;
            });
            // 最後まで再生したら停止状態に戻して頭出し
            if (state.processingState == ProcessingState.completed) {
              _audioPlayer.seek(Duration.zero);
              _audioPlayer.pause();
            }
          }
        });

        // ファイルをセット
        await _audioPlayer.setFilePath(widget.recording.filePath);
      }
    } catch (e) {
      print("オーディオ読み込みエラー: $e");
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); 
    super.dispose();
  }

  void _togglePlay() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  // 時間を「00:00」形式にする便利関数
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _runGeminiTask(Function task) async {
    setState(() => _isLoading = true);
    final result = await task();
    setState(() {
      _displayText = result;
      _isLoading = false;
    });
  }

  // ★追加: 言語選択ダイアログを表示して翻訳を実行する関数
  Future<void> _showTranslationDialog() async {
    // テキストがない場合は警告を出して終了
    if (_displayText.isEmpty || _displayText.startsWith("（")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('翻訳するテキストがありません')),
      );
      return;
    }

    // ダイアログ表示
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('翻訳先の言語を選択'),
          children: _targetLanguages.entries.map((entry) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context); // ダイアログを閉じる
                
                // 選択された言語でGeminiを実行
                _runGeminiTask(
                  () => _geminiService.translateText(
                    _displayText,
                    targetLang: entry.value, // Mapの値(Englishなど)を渡す
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(entry.key, style: const TextStyle(fontSize: 16)), // Mapのキー(英語など)を表示
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> s3Upload() async {
    // ファイルパスの取得
    final file = File(widget.recording.filePath);

    // トークンの取得処理
    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();

      // トークンがない場合（未ログインなど）はここで終了
      if (token == null) {
        print("トークンが取得できませんでした（未ログイン）");
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインが必要です')),
        );
        return;
      }

      print("トークン取得成功: ${token.substring(0, 10)}...");

      // アップロード処理
      final uploadService = S3UploadService();
      
      // アップロード実行
      final result = await uploadService.uploadAudioFile(
        file, 
        idToken: token
      );

      // 成功時の処理
      final fileId = result['file_id'];
      
      print("保存完了！ ID: $fileId");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アップロード完了 (ID: $fileId)')),
      );

    } catch (e) {
      // エラーハンドリング
      print("アップロード失敗: $e");
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recording.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShareScreen(textContent: _displayText),
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
            // ★再生プレイヤーUI (シークバー付き)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
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
                      // シークバー
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: _duration.inMilliseconds.toDouble(),
                          value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                          onChanged: (value) {
                            // スライダーを動かしたときの位置へ移動
                            _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                    ],
                  ),
                  // 時間表示 (現在の時間 / 全体の時間)
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

            // ファイルパス（デバッグ用）
            Text(widget.recording.filePath, 
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _runGeminiTask(
                      () => _geminiService.transcribeAudio(widget.recording.filePath)
                    ),
                    icon: const Icon(Icons.mic),
                    label: const Text('文字起こし'),
                  ),
                  const SizedBox(width: 10),
                  
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _runGeminiTask(
                      () => _geminiService.summarizeText(_displayText)
                    ),
                    icon: const Icon(Icons.summarize),
                    label: const Text('要約'),
                  ),
                  const SizedBox(width: 10),

                  // ---------------------------
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : s3Upload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent, // 目立つように色を変更
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('S3 Upload (テスト)'),
                  ),
                  const SizedBox(width: 10),
                  // ---------------------------

                  // ★変更: 翻訳ボタン (ダイアログを表示)
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(_displayText),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}