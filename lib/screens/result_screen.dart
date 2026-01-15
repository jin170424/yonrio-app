import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../models/recording.dart'; // モデルをインポート
import 'share_screen.dart';
import 'dart:io';
import '../services/s3upload_service.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import '../services/get_idtoken_service.dart';

class ResultScreen extends StatefulWidget {
  // 親(Home)からデータを受け取るための変数
  final Recording recording;

  const ResultScreen({super.key, required this.recording});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();
  final S3UploadService _s3UploadService = S3UploadService();
  
  String _displayText = "（文字起こしボタンを押してください）";
  bool _isLoading = false;

  Future<void> _runGeminiTask(Function task) async {
    setState(() => _isLoading = true);
    final result = await task();
    setState(() {
      _displayText = result;
      _isLoading = false;
    });
  }

Future<void> s3Upload() async {
  // ファイルパスの取得（TODO: 念のため空チェックいれる）
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
    final s3Key = result['s3_key'];
    
    print("保存完了！ ID: $fileId");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('アップロード完了 (ID: $fileId)')),
    );

    // TODO: DynamoDB保存APIの呼び出しなどをここに記述

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
        // タイトルを受け取ったデータの日付などにする
        title: Text(widget.recording.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShareScreen(
                    textContent: _displayText,
                    audioPath: widget.recording.filePath,
                  ),
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
            // ファイル情報の表示（デバッグ用にも便利）
            Text("ファイルパス: ${widget.recording.filePath}", 
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _runGeminiTask(
                      // ★ここで実際のファイルパスを渡す！
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

                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _runGeminiTask(
                      () => _geminiService.translateText(_displayText)
                    ),
                    icon: const Icon(Icons.translate),
                    label: const Text('英語へ翻訳'),
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