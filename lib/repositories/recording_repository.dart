import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:voice_app/models/recording.dart';
import 'package:voice_app/models/transcript_segment.dart';


class RecordingRepository {
  final Isar isar;

  final String apiUrl = "https://p8925osehl.execute-api.us-east-1.amazonaws.com/dev/download";
  final String apiBaseUrl = "https://658ajc4jf7.execute-api.us-east-1.amazonaws.com/dev/list";

  RecordingRepository(this.isar);

  Future<void> syncTranscriptionAndSummary(
    Recording targetRecording,
    String idToken
  ) async {
    if (targetRecording.remoteId == null) {
      throw Exception("remoteIdが設定されていないため、データ取得できません");
      // TODO: s3にアップロードする処理
    }

    final String filenameParam = "${targetRecording.remoteId}.json";

    try {
      final uri = Uri.parse('$apiUrl?filename=$filenameParam');
      final apiResponse = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization':idToken,
        },
      );

      if (apiResponse.statusCode != 200) {
        throw Exception('API Error: ${apiResponse.body}');
      }

      final apiBody = jsonDecode(apiResponse.body);
      final String downloadUrl = apiBody['download_url'];
      final String s3Key = apiBody['s3_key'];

      // 書名付きURLを使ってs3からjsonをダウンロード
      final s3Response = await http.get(Uri.parse(downloadUrl));

      if (s3Response.statusCode != 200) {
        throw Exception('S3 Download Error (${s3Response.statusCode}): ファイルが見つかりません');
      }

      // 日本語文字化け対策
      final Map<String, dynamic> jsonContent = jsonDecode(utf8.decode(s3Response.bodyBytes));

      // isar更新
      await isar.writeTxn(() async {
        // 親データ
        targetRecording.summary = jsonContent['summary'] as String?;
        targetRecording.transcription = jsonContent['full_transcript'] as String?;
        targetRecording.s3TranscriptJsonUrl = s3Key;
        targetRecording.updatedAt = DateTime.now();

        await isar.recordings.put(targetRecording);
        
        // 子データ
        // 既存のものをクリア
        await isar.transcriptSegments.filter().recording((q) => q.idEqualTo(targetRecording.id)).deleteAll();

        // セグメントの作成
        final speakersList = jsonContent['speakers'] as List<dynamic>?;

        if (speakersList != null) {
          final List<TranscriptSegment> newSegments = [];

          for (var item in speakersList) {
            final segment = TranscriptSegment()
              ..speaker = item['speaker'] ?? 'Unknown'
              ..text = item['text'] ?? ''
              ..startTimeMs = ((item['startTime'] ?? 0) * 1000).toInt()
              ..endTimeMs = ((item['endTime'] ?? 0) * 1000).toInt()
              ..searchTokens = (item['searchTokens'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList()
              ..recording.value = targetRecording;
          
            newSegments.add(segment);
          }

          // 保存
          await isar.transcriptSegments.putAll(newSegments);

          // 親リンクも保存
          targetRecording.transcripts.addAll(newSegments);
          await targetRecording.transcripts.save();
        }

        // 親データを保存
        await isar.recordings.put(targetRecording);
      });

      print('同期完了: ${targetRecording.remoteId}');
    } catch (e) {
      print('エラー: $e');
      rethrow;
    }

  }

  // DynamoDBのメタデータ一覧を同期する
  Future<void> syncMetadataList(String idToken) async {
    try {
      final uri = Uri.parse('$apiBaseUrl');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': idToken,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('API List Error: ${response.body}');
      }

      // DynamoDBからのレスポンスリスト(Items)
      final List<dynamic> remoteItems = jsonDecode(utf8.decode(response.bodyBytes));

      await isar.writeTxn(() async {
        for (var item in remoteItems) {
          final String remoteId = item['id'];

          // ローカルに同じIDのデータがあるか
          Recording? localRecording = await isar.recordings
            .filter()
            .remoteIdEqualTo(remoteId)
            .findFirst();

          List<SharedUser>? sharedWithList;
          if (item['sharedWith'] != null) {
            sharedWithList = (item['sharedWith'] as List).map((s) {
              // JSONの中身がオブジェクトかID文字列かで分岐
              if (s is Map) {
                return SharedUser()
                  ..userId = s['userId']
                  ..name = s['name'];
              } else {
                // 文字列だけのリストだった場合のフォールバック
                return SharedUser()..userId = s.toString();
              }
            }).toList();
          }

          // 新規作成 または 既存更新
          if (localRecording == null) {
            // 新規作成
            localRecording = Recording()
              ..remoteId = remoteId
              ..filePath = ""
              ..transcription = "（未取得）"
              ..summary = "（未取得）";
          }

          // サーバーのデータでフィールド更新(Upsert)
          localRecording
            ..title = item['title'] ?? localRecording.title
            ..status = item['status'] ?? 'processing'
            ..s3AudioUrl = item['s3AudioUrl']
            ..s3TranscriptJsonUrl = item['s3TranscriptJsonUrl']
            ..ownerName = item['ownerName'] ?? localRecording.ownerName
            ..createdAt = DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now()
            ..updatedAt = DateTime.now()
            ..lastSyncTime = DateTime.now()
            ..sourceOriginalId = item['sourceOriginalId']
            ..sharedWith = sharedWithList;
          
          await isar.recordings.put(localRecording);
        }
      });
      print('メタデータ同期完了: ${remoteItems.length}件');
    } catch (e) {
      print('メタデータ同期エラー: $e');
      rethrow;
    }

    }
  }