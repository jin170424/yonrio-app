import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class S3UploadService {
  final String _lambdaApiUrl = 'https://lyykfzqqz7.execute-api.us-east-1.amazonaws.com/dev/presigned';

  /// メイン処理: アップロードを行い、作成されたファイルIDなどの情報を返す
  /// 戻り値: { 'file_id':String, 's3_key':String, ... }
  Future<Map<String, dynamic>> uploadAudioFile(File audioFile, String title, {String? idToken, String? recordingId}) async {
    try {
      // とりあえずwav固定
      String fileName = audioFile.path.split('/').last;
      String contentType = 'audio/wav'; 

      print('署名付きURL取得開始...');

      // Lambdaからレスポンス (url, file_id, s3_key) を取得
      final presignedData = await _getPresignedUrl(
        fileName: fileName,
        contentType: contentType,
        title: title,
        idToken: idToken,
        recordingId: recordingId,
      );

      String uploadUrl = presignedData['upload_url'];
      String responseRecordingId = presignedData['recording_id'];
      print('   -> URL取得成功 ID: $recordingId');

      print('S3アップロード開始...');
      
      // S3へPUT
      await _uploadToS3(
        url: uploadUrl,
        file: audioFile,
        contentType: contentType,
        recordingId: responseRecordingId,
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
    required String title,
    String? idToken,
    String? recordingId,

  }) async {
    final bodyMap = {
      "filename": fileName,
      "contentType": contentType,
      "title": title,
    };

    if (recordingId != null){
      bodyMap["recording_id"] = recordingId;
    }

    final body = jsonEncode(bodyMap);

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
      // { "upload_url": "...", "meeting_id": "UUID" } が返る
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
    required String recordingId,
  }) async {
    
    // List<int> fileBytes = await file.readAsBytes();

    final int length = await file.length();
    final stream = http.ByteStream(file.openRead());
    final request = http.StreamedRequest('PUT', Uri.parse(url));

    request.headers['Content-Type'] = contentType;
    request.contentLength = length;
    stream.pipe(request.sink);
    final response = await http.Response.fromStream(await request.send());
    
    // final headers = {
    //   "Content-Type": contentType,
    // };

    // final response = await http.put(
    //   Uri.parse(url),
    //   headers: headers,
    //   body: fileBytes,
    // );

    if (response.statusCode != 200) {
      print('S3 Upload Failed: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('S3 Upload Error: ${response.statusCode} ${response.body}');
    }
  }
}