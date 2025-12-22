import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart'; // v4.4.4
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
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

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        
        // ★ m4aファイル名
        final now = DateTime.now();
        final fileName = 'recording_${DateFormat('yyyyMMdd_HHmmss').format(now)}.m4a';
        final path = '${directory.path}/$fileName';

        await _audioRecorder.start(
          path: path,
          encoder: AudioEncoder.aacLc, // ★ m4a (AAC) エンコーダー
        );

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });
        _startTimer();
      } else {
        openAppSettings();
      }
    } catch (e) {
      print('録音エラー: $e');
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    // ここでアプリが落ちる場合は、実機で試すかWAVに戻してください
    final path = await _audioRecorder.stop();
    
    setState(() {
      _isRecording = false;
    });

    if (path != null) {
      await _saveToIsar(path, _recordDuration);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('録音を保存しました')),
      );
      Navigator.pop(context);
    }
  }

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
            Text(
              _formatDuration(_recordDuration),
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 50),
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