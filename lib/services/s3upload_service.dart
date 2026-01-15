import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class S3UploadService {
  final String _lambdaApiUrl = 'https://lyykfzqqz7.execute-api.us-east-1.amazonaws.com/dev/presigned';

  /// メイン処理: アップロードを行い、作成されたファイルIDなどの情報を返す
  /// 戻り値: { 'file_id':String, 's3_key':String, ... }
  Future<Map<String, dynamic>> uploadAudioFile(File audioFile, {String? idToken}) async {
    try {
      // とりあえずwav固定
      String fileName = audioFile.path.split('/').last;
      String contentType = 'audio/wav'; 

      print('署名付きURL取得開始...');

      // Lambdaからレスポンス (url, file_id, s3_key) を取得
      final presignedData = await _getPresignedUrl(
        fileName: fileName,
        contentType: contentType,
        idToken: idToken,
      );

      String uploadUrl = presignedData['upload_url'];
      print('   -> URL取得成功: $uploadUrl');

      print('S3アップロード開始...');
      
      // S3へPUT
      await _uploadToS3(
        url: uploadUrl,
        file: audioFile,
        contentType: contentType,
      );

      print('   -> ★アップロード完了');

      // Lambdaから受け取っていたメタデータを呼び出し元へ返す
      return presignedData; 

    } catch (e) {
      print('エラー発生: $e');
      rethrow;
    }
  }

  /// Lambdaへリクエストを送る内部メソッド
  Future<Map<String, dynamic>> _getPresignedUrl({
    required String fileName,
    required String contentType,
    String? idToken,
  }) async {
    final body = jsonEncode({
      "filename": fileName,
      "contentType": contentType,
    });

    Map<String, String> headers = {
      "Content-Type": "application/json",
    };

    if (idToken != null) {
      headers["Authorization"] = idToken; 
    }

    final response = await http.post(
      Uri.parse(_lambdaApiUrl),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      // { "upload_url": "...", "file_id": "...", "s3_key": "..." } が返る
      return jsonDecode(response.body);
    } else {
      throw Exception('Lambda Error: ${response.statusCode} ${response.body}');
    }
  }

  /// S3へバイナリデータを送る内部メソッド
  Future<void> _uploadToS3({
    required String url,
    required File file,
    required String contentType,
  }) async {
    List<int> fileBytes = await file.readAsBytes();

    final response = await http.put(
      Uri.parse(url),
      headers: {
        // 署名時と同じContentTypeを指定する
        "Content-Type": contentType, 
      },
      body: fileBytes,
    );

    if (response.statusCode != 200) {
      throw Exception('S3 Upload Error: ${response.statusCode} ${response.body}');
    }
  }
}