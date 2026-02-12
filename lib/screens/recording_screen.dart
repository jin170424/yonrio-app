import 'dart:async';
import 'dart:io';
// ★追加: ランダムID生成用
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:voice_app/main.dart';
import 'package:voice_app/repositories/recording_repository.dart';
import 'package:voice_app/services/user_service.dart';

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
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  Future<void> _fetchUser() async {
    final userService = UserService();
    final userId = await userService.getCurrentUserSub();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
      });
    }
  }

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

  // ★追加: 一時的なユニークID生成
  String _generateUniqueId() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (index) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _startRecording() async {
    if (_currentUserId == null) {
      await _fetchUser();
      if (_currentUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ユーザー情報の取得に失敗しました。再ログインしてください。')),
        );
        return;
      }
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        
        final now = DateTime.now();
        final fileName = 'recording_${DateFormat('yyyyMMdd_HHmmss').format(now)}.wav';
        final path = '${directory.path}/$fileName';

        await _audioRecorder.start(
          path: path,
          encoder: AudioEncoder.wav, 
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
    final path = await _audioRecorder.stop();
    
    setState(() {
      _isRecording = false;
    });

    if (path != null) {
      if (_currentUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ユーザーIDが見つかりません。保存できませんでした。')),
        );
        return;
      }
      final ownerName = await UserService().getPreferredUsername();
      // await _saveToIsar(path, _recordDuration);
      final dio = Dio();
      await RecordingRepository(isar: isar, dio: dio).saveRecording(
        filePath: path,
        duration: _recordDuration, 
        ownerName: ownerName ?? 'unknown_user',
        ownerId: _currentUserId!,
        );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('録音を保存しました')),
      );
      Navigator.pop(context);
    }
  }

  // Future<void> _saveToIsar(String filePath, int duration) async {
  //   final isar = Isar.getInstance();
  //   if (isar != null) {

  //     String currentUserId = 'unknown_user';
  //     try {
  //       final user = await Amplify.Auth.getCurrentUser();
  //       currentUserId = user.userId;
  //     } catch (e) {
  //       print("Auth error (offline or not logged in): $e");
  //     }

  //     final newRecording = Recording()
  //       ..title = DateFormat('yyyy/MM/dd HH:mmの録音').format(DateTime.now())
  //       ..filePath = filePath
  //       ..durationSeconds = duration
  //       ..createdAt = DateTime.now()
  //       ..updatedAt = DateTime.now()
  //       ..ownerName = currentUserId
  //       ..status = 'processing';

  //     await isar.writeTxn(() async {
  //       await isar.recordings.put(newRecording);
  //     });
  //   }
  // }

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