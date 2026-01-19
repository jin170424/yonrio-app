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
  
  // ★変更点1: 文字列変数の代わりにコントローラーを使います
  late TextEditingController _textController;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero; // 全体の長さ
  Duration _position = Duration.zero; // 現在の再生位置
  bool _isLoading = false;

  // ★対応言語リスト (表示名 : Geminiに渡す英語名)
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
    // 初期値をセット
    _textController = TextEditingController(text: "（文字起こしボタンを押してください）");
    _initAudioPlayer();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _textController.dispose(); // ★コントローラーは破棄が必要です
    super.dispose();
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

  // ★変更点2: 結果をコントローラーに反映するように修正
  Future<void> _runGeminiTask(Future<String> Function() task) async {
    setState(() => _isLoading = true);
    
    // タスク実行
    final result = await task();
    
    setState(() {
      _textController.text = result; // 結果で上書き
      _isLoading = false;
    });
  }

  // ★言語選択ダイアログを表示して翻訳を実行する関数
  Future<void> _showTranslationDialog() async {
    // ★現在のテキストボックスの中身を取得してチェック
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
                Navigator.pop(context); // ダイアログを閉じる
                
                // 選択された言語でGeminiを実行
                _runGeminiTask(
                  // ★編集後のテキスト(_textController.text)を渡す
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
                  // ★シェア画面にも編集後のテキストを渡す
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
                    // ★要約時も編集後のテキストを渡す
                    onPressed: _isLoading ? null : () => _runGeminiTask(
                      () => _geminiService.summarizeText(_textController.text)
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

                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _showTranslationDialog,
                    icon: const Icon(Icons.translate),
                    label: const Text('翻訳'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // ★変更点3: 表示エリアを TextField に変更して編集可能にする
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
                    child: TextField( // ここをTextからTextFieldに変更
                      controller: _textController,
                      maxLines: null, // 行数無制限
                      keyboardType: TextInputType.multiline, // 改行キーを表示
                      decoration: const InputDecoration(
                        border: InputBorder.none, // 枠線はContainerで描画してるので消す
                      ),
                      style: const TextStyle(fontSize: 16, height: 1.5), // 読みやすいように調整
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}