import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../models/recording.dart'; // モデルをインポート
import 'share_screen.dart';

class ResultScreen extends StatefulWidget {
  // 親(Home)からデータを受け取るための変数
  final Recording recording;

  const ResultScreen({super.key, required this.recording});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();
  
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