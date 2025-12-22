import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  // ★キーはそのままでOK！認証には成功しています。
  final String _apiKey = 'AIzaSyA5JJi6rRCabRmipr0L2-Y8jqFR65Tfj_I';

  late final GenerativeModel _model;

  GeminiService() {
    // Gemini 2.5 Lite だと動く(1.5は不可)
    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: _apiKey,
    );
  }

  // 1. 文字起こし (m4a対応)
  Future<String> transcribeAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        return "エラー: 音声ファイルが見つかりません\nパス: $audioPath";
      }

      // ファイルサイズチェック
      final length = await file.length();
      if (length > 20 * 1024 * 1024) {
        return "エラー: ファイルサイズが大きすぎます (20MB以下にしてください)";
      }

      final bytes = await file.readAsBytes();

      final content = [
        Content.multi([
          TextPart('この音声を日本語で文字起こししてください。話者分離（Aさん、Bさん）もお願いします。'),
          DataPart('audio/mp4', bytes), 
        ])
      ];

      final response = await _model.generateContent(content);
      return response.text ?? '（文字起こし結果が空でした）';

    } catch (e) {
      return 'AIエラー: $e';
    }
  }

  // 2. 要約
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

  // 3. 翻訳
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