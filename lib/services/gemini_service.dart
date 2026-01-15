import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
// mimeタイプを判定するためにpathライブラリを使います（標準で入っています）
import 'package:path/path.dart' as p;

class GeminiService {
  // ★認証済みのキー（そのまま）
  final String _apiKey = 'AIzaSyDH1A24geMSTxF0GMKzM-Lo_3Z-ZIFgDmo';

  late final GenerativeModel _model;

  GeminiService() {
    // 無料で使える軽量モデル
    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: _apiKey,
    );
  }

  // 1. 文字起こし (全フォーマット対応版)
  Future<String> transcribeAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        return "エラー: 音声ファイルが見つかりません\nパス: $audioPath";
      }

      // ファイルサイズチェック (20MB制限)
      final length = await file.length();
      if (length > 20 * 1024 * 1024) {
        return "エラー: ファイルサイズが大きすぎます (20MB以下にしてください)";
      }

      final bytes = await file.readAsBytes();
      
      // ★拡張子からMIMEタイプを自動判定
      final extension = p.extension(audioPath).toLowerCase().replaceAll('.', '');
      String mimeType;
      
      switch (extension) {
        case 'mp3':
          mimeType = 'audio/mp3';
          break;
        case 'wav':
          mimeType = 'audio/wav';
          break;
        case 'm4a':
        case 'mp4':
        case 'aac':
          mimeType = 'audio/mp4';
          break;
        case 'ogg':
        case 'oga':
          mimeType = 'audio/ogg';
          break;
        default:
          // 分からない場合は汎用的なものを指定（WAVとして送ってみる）
          mimeType = 'audio/wav';
      }

      final content = [
        Content.multi([
          TextPart('この音声を日本語で文字起こししてください。話者分離（Aさん、Bさん）もお願いします。'),
          // ★自動判定したmimeタイプを使う
          DataPart(mimeType, bytes), 
        ])
      ];

      final response = await _model.generateContent(content);
      return response.text ?? '（文字起こし結果が空でした）';

    } catch (e) {
      return 'AIエラー: $e';
    }
  }

  // （要約・翻訳機能は変更なしなので省略可、そのままでOK）
  Future<String> summarizeText(String text) async {
    if (text.isEmpty || text.contains("エラー")) return "要約するテキストがありません。";
    try {
      final content = [Content.text('以下の文章を要約してください。\n\n$text')];
      final response = await _model.generateContent(content);
      return response.text ?? '（要約不可）';
    } catch (e) {
      return '要約エラー: $e';
    }
  }

  Future<String> translateText(String text) async {
    if (text.isEmpty || text.contains("エラー")) return "翻訳するテキストがありません。";
    try {
      final content = [Content.text('Translate to English:\n\n$text')];
      final response = await _model.generateContent(content);
      return response.text ?? '（翻訳不可）';
    } catch (e) {
      return '翻訳エラー: $e';
    }
  }
}