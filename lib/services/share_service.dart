import 'package:dio/dio.dart'; // HTTPクライアント
import 'package:flutter/material.dart';
import 'package:voice_app/services/get_idtoken_service.dart';

class ShareService {
  final Dio _dio = Dio();
  final String _shareApiUrl = 'https://658ajc4jf7.execute-api.us-east-1.amazonaws.com/dev/share';

  Future<void> shareRecording(String recordingId, String targetEmail) async {
    final tokenService = GetIdtokenService();
    final token = await tokenService.getIdtoken();
    
    try {
      final response = await _dio.post(
        _shareApiUrl,
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
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception("ユーザーが見つかりませんでした");
      } else if (e.response?.statusCode == 400) {
        throw Exception("すでに共有済みです");
      }
      throw Exception("共有に失敗しました: ${e.message}");
    }
  }
}