import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:voice_app/main.dart';
import 'package:voice_app/models/recording.dart';
import 'package:voice_app/repositories/recording_repository.dart';
import 'package:voice_app/screens/result_screen.dart';
import 'package:voice_app/services/get_idtoken_service.dart';
import 'package:voice_app/services/s3upload_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:voice_app/widgets/top_notification_overlay.dart';

// アプリ全体で通知を出すためのGlobalKey
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
void onNotificationTap(NotificationResponse response) {
  final String? payload = response.payload;
  if (payload != null) {
    // ID(int)を文字列で受け取るのでパースして遷移処理へ
    final int? recordingId = int.tryParse(payload);
    if (recordingId != null) {
      _navigateToResultScreen(recordingId);
    }
  }
}

Future<void> _navigateToResultScreen(int recordingId) async {
  print("画面遷移リクエスト: ID=$recordingId");
  
  // navigatorKeyが接続されているかチェック
  if (navigatorKey.currentState == null) {
    print("エラー: navigatorKey.currentState が null です。main.dartを確認してください。");
    return;
  }
  final isar = Isar.getInstance();
  if (isar == null) return;
  final recording = await isar.recordings.get(recordingId);
  if (recording != null) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => ResultScreen(recording: recording),
      )
    );
  }
}

class ProcessingService with WidgetsBindingObserver{
  static final ProcessingService _instance = ProcessingService._internal();
  factory ProcessingService() => _instance;
  ProcessingService._internal();

  final S3UploadService _uploadService = S3UploadService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  bool _isInForeground = true;

  Future<void> initNotifications() async {
    if (_isInitialized) return;
    WidgetsBinding.instance.addObserver(this);

    // Android用設定 (アプリアイコンを指定。mipmap/ic_launcher が一般的)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS用設定
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notificationsPlugin.initialize(
      settings,
      // onDidReceiveBackgroundNotificationResponse: (NotificationResponse response) async {
      //   final String? payload = response.payload;
      //   if (payload != null) {
      //     final int? recordingId = int.tryParse(payload);
      //     if (recordingId != null) {
      //       await _navigateToResultScreen(recordingId);
      //     }
      //   }
      // }
      onDidReceiveNotificationResponse: onNotificationTap,
    );
    
    _isInitialized = true;
    print("Local Notifications Initialized");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // resumed = アプリが手前にある状態
    _isInForeground = (state == AppLifecycleState.resumed);
    print("App State Changed: $_isInForeground");
  }

  // 処理を開始するメソッド
  Future<void> startUploadAndProcessing(Recording recording, Isar isar, RecordingRepository repository) async {
    // ステータスを更新 (UIに反映させるため)
    if (!_isInitialized) await initNotifications();
    await isar.writeTxn(() async {
      recording.status = 'uploading'; 
      await isar.recordings.put(recording);
    });

    _processbackground(recording, isar, repository);
  }


  Future<void> _processbackground(Recording recording, Isar isar, RecordingRepository repository) async {
    try {
      final token = await GetIdtokenService().getIdtoken();
      if (token == null) throw Exception("ログインが必要です");

      // --- Upload ---
      final file = File(recording.filePath);
      final result = await _uploadService.uploadAudioFile(
        file, 
        recording.title,
        idToken: token,
        recordingId: recording.remoteId,
      );

      final newRemoteId = result['recording_id'];
      final s3Key = result['s3_key'];

      await isar.writeTxn(() async {
        recording.remoteId = newRemoteId;
        recording.s3AudioUrl = s3Key;
        recording.status = 'processing'; // アップロード完了、解析中へ
        await isar.recordings.put(recording);
      });

      // --- Polling ---
      await _pollForCompletion(recording, isar, repository);

    } catch (e) {
      print("バックグラウンド処理エラー: $e");
      await isar.writeTxn(() async {
        recording.status = 'failed'; // エラー状態
        await isar.recordings.put(recording);
      });
      
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('処理失敗: ${recording.title} ($e)'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pollForCompletion(Recording recording, Isar isar, RecordingRepository repository) async {
    const int maxAttempts = 60; // 5分程度待つ
    const Duration interval = Duration(seconds: 5);

    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);
      try {
        final token = await GetIdtokenService().getIdtoken();
        if (token == null) break;

        // Isar上の最新状態を確認（削除されてないかなど）
        final currentRec = await isar.recordings.get(recording.id);
        if (currentRec == null) return; // 削除された

        // APIから最新情報を同期
        await repository.syncTranscriptionAndSummary(currentRec, token);

        // 文字起こしが入ったか確認 (syncTranscriptionAndSummary内でtranscriptsが更新される)
        final updatedRec = await isar.recordings.get(recording.id);
        if (updatedRec != null && updatedRec.transcripts.isNotEmpty) {
          
          await isar.writeTxn(() async {
            updatedRec.status = 'completed';
            await isar.recordings.put(updatedRec);
          });

          if (!_isInForeground) {
            await _showCompletionNotification(
              "解析完了", 
              "「${updatedRec.title}」の文字起こしが完了しました",
              updatedRec.id.toString(),
            );
          }

          // 完了通知
          showTopNotification(
            navigatorKey,
            title: "解析完了",
            body: "「${updatedRec.title}」の文字起こしが完了しました",
            onTap: () {
              // ここで遷移処理を呼ぶ
              _navigateToResultScreen(updatedRec.id);
            },
          );
          return;
        }
      } catch (e) {
        print("Polling error (retry): $e");
      }
    }
    
    // タイムアウト
    await isar.writeTxn(() async {
      final r = await isar.recordings.get(recording.id);
      if (r != null) {
        r.status = 'timeout'; // または processingのままにする
        await isar.recordings.put(r);
      }
    });
  }

  // 通知を出すメソッド
  Future<void> _showCompletionNotification(String title, String body, String payload) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'transcription_channel', // チャンネルID
        '文字起こし通知',          // チャンネル名
        channelDescription: '文字起こし完了時に通知します',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );
      
      const iosDetails = DarwinNotificationDetails();
      
      const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      
      // IDはユニークにするか、0で上書きするか。今回は現在時刻でユニーク化
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      print("通知表示エラー: $e");
    }
  }


}