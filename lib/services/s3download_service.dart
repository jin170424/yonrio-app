import 'dart:convert';
import 'package:http/http.dart' as http;

class S3DownloadService {
  static const String _apiUrl = 'https://p8925osehl.execute-api.us-east-1.amazonaws.com/dev/download';

  Future<String?> getPresignedUrl(String s3Key, String idToken) async {
    try {
      final String queryParams = '?s3_key=${Uri.encodeQueryComponent(s3Key)}';
      final uri = Uri.parse('$_apiUrl$queryParams');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': idToken,
        },
      );
      

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'];
      } else {
        print('署名付きURLの取得失敗: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('署名付きURLリクエストエラー: $e');
      return null;
    }
  }
}