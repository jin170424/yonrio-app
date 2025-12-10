import 'package:flutter/material.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool isRecording = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新規録音')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 録音時間を表示するタイマー (TODO)
            const Text(
              '00:00:00',
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 50),
            
            // 録音ボタン
            GestureDetector(
              onTap: () {
                setState(() {
                  isRecording = !isRecording;
                });
                if (isRecording) {
                  // TODO: ここで record.start() を呼ぶ
                  print("録音開始");
                } else {
                  // TODO: ここで record.stop() を呼び、保存処理へ
                  print("録音停止 -> 保存");
                  Navigator.pop(context); // ホームに戻る
                }
              },
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: isRecording ? Colors.red : Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(isRecording ? 'タップして停止' : 'タップして録音開始'),
          ],
        ),
      ),
    );
  }
}