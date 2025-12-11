import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart'; // バージョン4.4.4
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';

// DBの設計図をインポート
import '../models/recording.dart'; 

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final _audioRecorder = Record();
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  // 時間を 00:00 形式にする
  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  // 録音開始
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        
        // ファイル名: recording_20251211_120000.m4a
        final now = DateTime.now();
        final fileName = 'recording_${DateFormat('yyyyMMdd_HHmmss').format(now)}.m4a';
        final path = '${directory.path}/$fileName';

        // 録音スタート
        await _audioRecorder.start(
          path: path,
          encoder: AudioEncoder.aacLc, // 軽量で高音質
        );

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });

        _startTimer();
      } else {
        // 許可がない場合、設定画面へ誘導
        openAppSettings();
      }
    } catch (e) {
      print('録音エラー: $e');
    }
  }

  // 録音停止 & 保存
  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _audioRecorder.stop();
    
    setState(() {
      _isRecording = false;
    });

    if (path != null) {
      // ★ここでデータベース(Isar)に保存！
      await _saveToIsar(path, _recordDuration);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('録音を保存しました')),
      );
      
      // ホームに戻る
      Navigator.pop(context);
    }
  }

  // DB保存処理
  Future<void> _saveToIsar(String filePath, int duration) async {
    final isar = Isar.getInstance();
    if (isar != null) {
      final newRecording = Recording()
        ..title = DateFormat('yyyy/MM/dd HH:mmの録音').format(DateTime.now())
        ..filePath = filePath
        ..durationSeconds = duration
        ..createdAt = DateTime.now();

      await isar.writeTxn(() async {
        await isar.recordings.put(newRecording);
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _recordDuration++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新規録音')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // タイマー表示
            Text(
              _formatDuration(_recordDuration),
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 50),
            
            // 録音ボタン
            GestureDetector(
              onTap: () {
                if (_isRecording) {
                  _stopRecording();
                } else {
                  _startRecording();
                }
              },
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isRecording ? Colors.red.withOpacity(0.5) : Colors.blue.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(_isRecording ? '録音中...' : 'タップして開始'),
          ],
        ),
      ),
    );
  }
}