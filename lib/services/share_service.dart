import 'package:dio/dio.dart'; // HTTPクライアント
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:voice_app/main.dart';
import 'package:voice_app/models/recording.dart';
import 'package:voice_app/repositories/recording_repository.dart';
import 'package:voice_app/services/get_idtoken_service.dart';

class ShareService {
  final Dio _dio = Dio();
  final String _shareApiUrl = 'https://658ajc4jf7.execute-api.us-east-1.amazonaws.com/dev';
  final repository = RecordingRepository(isar: Isar.getInstance()!, dio: Dio());

  Future<void> shareRecording(String recordingId, String targetEmail) async {
    final tokenService = GetIdtokenService();
    final token = await tokenService.getIdtoken();
    
    try {
      final response = await _dio.post(
        '$_shareApiUrl/share',
        data: {
          'recordingId': recordingId,
          'targetEmail': targetEmail,
        },
        options: Options(
          headers: {
            'Authorization': token,
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        debugPrint('Share successful: ${response.data}');
        final data = response.data;
        if (data['addedUser'] != null) {
          final addedUserMap = data['addedUser'];

          // isarに変換
          final newSharedUser = SharedUser()
          ..userId = addedUserMap['userId']
          ..name = addedUserMap['name'];
          
          final recording = await repository.isar.recordings
            .filter()
            .remoteIdEqualTo(recordingId)
            .findFirst();

          if (recording != null) {

            // ローカルのisar更新
            await isar.writeTxn(() async {
              // 現在のリストコピーして新しいユーザーを追加
              final List<SharedUser> currentList = recording?.sharedWith?.toList() ?? [];

              // 重複チェック
              final exists = currentList.any((u) => u.userId == newSharedUser.userId);
              if (!exists) {
                currentList.add(newSharedUser);
                recording!.sharedWith = currentList;

                await isar.recordings.put(recording);
                print("ローカルIsarへの共有ユーザー追加完了: ${newSharedUser.name}");
              } else {
                debugPrint("すでにローカルリストには存在します");
              }
            });
          } else {
            debugPrint("ローカルデータが見つかりませんでした (remoteId: $recordingId)");
          }
        }
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final statusCode = e.response!.statusCode;
        final data = e.response!.data;
        
        // エラーメッセージを取得 (Lambdaが {'message': '...'} を返している前提)
        String? serverMessage;
        if (data is Map && data['message'] != null) {
          serverMessage = data['message'].toString();
        }

        if (statusCode == 404) {
          throw Exception("ユーザーが見つかりませんでした");
        } 
        else if (statusCode == 409) {
          throw Exception("すでに共有済みです");
        } 
        else if (statusCode == 400) {
          // ★ここでメッセージ内容によって分岐させる
          if (serverMessage != null) {
            if (serverMessage.contains('yourself')) {
              throw Exception("自分自身には共有できません");
            }
            if (serverMessage.contains('Already shared')) {
              throw Exception("すでに共有済みです");
            }
            // その他の400エラー
            throw Exception("エラー: $serverMessage");
          }
          throw Exception("不正なリクエストです");
        }
      }
      
      // その他のエラー
      throw Exception("共有に失敗しました: ${e.message}");
    }
  }

  Future<void> unshareRecording(String recordingId, String targetEmail) async {
    final tokenService = GetIdtokenService();
    final token = await tokenService.getIdtoken();
    
    try {
      final response = await _dio.post( 
        '$_shareApiUrl/unshare',
        data: {
          'recordingId': recordingId,
          'targetEmail': targetEmail,
        },
        options: Options(
          headers: {
            'Authorization': token,
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        debugPrint('Unshare successful');
        
        // ローカルIsarの更新
        final recording = await repository.isar.recordings
          .filter()
          .remoteIdEqualTo(recordingId)
          .findFirst();

        if (recording != null) {
          await repository.isar.writeTxn(() async {
            final currentList = recording.sharedWith?.toList() ?? [];
            // リストから該当ユーザーを削除
            currentList.removeWhere((u) => u.userId == targetEmail);
            
            recording.sharedWith = currentList;
            await repository.isar.recordings.put(recording);
          });
        }
      }
    } on DioException catch (e) {
      throw Exception("共有解除に失敗しました: ${e.message}");
    }
  }

}