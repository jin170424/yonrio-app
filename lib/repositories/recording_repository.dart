import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:voice_app/models/recording.dart';
import 'package:voice_app/models/transcript_segment.dart';


class RecordingRepository {
  final Isar isar;
  final Dio dio;
  final String apiUrl = "https://p8925osehl.execute-api.us-east-1.amazonaws.com/dev/download";
  final String apiBaseUrl = "https://658ajc4jf7.execute-api.us-east-1.amazonaws.com/dev";

  RecordingRepository({required this.isar, required this.dio});

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
      // final Map<String, dynamic> jsonContent = jsonDecode(utf8.decode(s3Response.bodyBytes));
      final dynamic decoded = jsonDecode(utf8.decode(s3Response.bodyBytes));


      if (decoded is Map) {
        print("S3 JSON Keys: ${decoded.keys.toList()}"); // キーの一覧を表示
        print("Full Transcript Value: ${decoded['full_transcript']?.toString().substring(0, 20)}..."); // 先頭だけ表示してみる
      } else {
        print("S3 JSON is List format");
      }

    
      String? fetchedSummary;
      String? fetchedTranscription;
      Map<String, dynamic> jsonContent;
      List<dynamic>? speakersList;

      if (decoded is List) {
        print("古い形式(List)のJSONを検出しました。互換モードで処理します。");
        // jsonContent = {}; // 空のマップを入れておく
        speakersList = decoded;
        fetchedSummary = null;
      } else if (decoded is Map) {
        final dynamic speakersRaw = decoded['speakers'];
        if (speakersRaw is List) {
          speakersList = speakersRaw;
        } else if (speakersRaw != null) {
          print("警告: 'speakers' がリスト形式ではありません。型: ${speakersRaw.runtimeType}, 値: $speakersRaw");
          speakersList = []; // 空リストにしてクラッシュを防ぐ
        }
        fetchedSummary = decoded['summary'] as String?;
        fetchedTranscription = decoded['full_transcript'] as String?;
      } else {
        throw Exception("不明なJSON形式です: ${decoded.runtimeType}");
      }

      if ((fetchedTranscription == null || fetchedTranscription.isEmpty) && speakersList != null) {
        fetchedTranscription = speakersList
            .map((item) => item['text'] as String? ?? '')
            .join(""); 
      }

      // isar更新
      await isar.writeTxn(() async {
        // 親データ
        if (fetchedSummary != null){
          targetRecording.summary = fetchedSummary;
        }
        if (fetchedTranscription != null) {
          targetRecording.transcription = fetchedTranscription;
        }
        targetRecording.s3TranscriptJsonUrl = s3Key;
        targetRecording.updatedAt = DateTime.now();
        targetRecording.lastSyncTime = DateTime.now();

        await isar.recordings.put(targetRecording);
        
        // 子データ
        // 既存のものをクリア
        if (speakersList != null){
        await isar.transcriptSegments.filter().recording((q) => q.idEqualTo(targetRecording.id)).deleteAll();

        // セグメントの作成
        final List<TranscriptSegment> newSegments = [];

          for (var item in speakersList) {
            if (item is! Map<String, dynamic>) continue;

            final segment = TranscriptSegment()
              ..speaker = item['speaker'] ?? 'Unknown'
              ..text = item['text'] ?? ''
              ..startTimeMs = ((item['startTime'] as num? ?? 0) * 1000).toInt()
              ..endTimeMs = ((item['endTime'] as num? ?? 0) * 1000).toInt()
              ..searchTokens = (item['searchTokens'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList();

            if (item['translations'] != null && item['translations'] is List) {
              final List<dynamic> trList = item['translations'];
              segment.translations = trList.map((t) {
                if (t is Map<String, dynamic>) {
                  return TranslationData()
                    ..langCode = t['langCode']
                    ..text = t['text'];
                }
                return TranslationData()..text = "";
              }).toList();
            }
            segment.recording.value = targetRecording;
            newSegments.add(segment);
          }

          // 保存
          if (newSegments.isNotEmpty){
            await isar.transcriptSegments.putAll(newSegments);

            // 親リンクも保存
            targetRecording.transcripts.addAll(newSegments);
            await targetRecording.transcripts.save();
          }
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
  Future<void> syncMetadataList(String idToken, String currentUserId) async {
    try {
      final uri = Uri.parse('$apiBaseUrl/list');
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

      final dynamic decodedResponse = jsonDecode(utf8.decode(response.bodyBytes));
      print("API Response Type: ${decodedResponse.runtimeType}");
      if (decodedResponse is Map) {
        // APIが {"message": "Internal Server Error"} などを返している場合への対策
        print("API Unexpected Response: $decodedResponse");
        throw Exception("サーバーから予期しないデータが返されました: ${decodedResponse['message'] ?? decodedResponse}");
      }

      if (decodedResponse is! List) {
        throw Exception("リスト形式ではありません: $decodedResponse");
      }

      // DynamoDBからのレスポンスリスト(Items)
      final List<dynamic> remoteItems = decodedResponse;

      final Set<String> activeServerIds = remoteItems
          .map((json) => json['id'] as String)
          .toSet();

      await isar.writeTxn(() async {
        for (var item in remoteItems) {
          final String remoteId = item['id'];

          // ローカルに同じIDのデータがあるか
          Recording? localRecording = await isar.recordings
            .filter()
            .remoteIdEqualTo(remoteId)
            .and()
            .ownerIdEqualTo(currentUserId)
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

          if (localRecording != null && localRecording.needsCloudUpdate) {
            print("ローカルで変更があるため、クラウドからの上書きをスキップ");
            continue;
          }
          
          // 新規作成 または 既存更新
          if (localRecording == null) {
            // 新規作成
            localRecording = Recording()
              ..remoteId = remoteId
              ..ownerId = currentUserId
              ..filePath = ""
              ..transcription = "（未取得）"
              ..summary = "（未取得）";
          }

          // サーバーのデータでフィールド更新(Upsert)
          localRecording
            ..title = item['title'] ?? localRecording.title
            ..status = item['status'] ?? 'processing'
            ..summary = item['summary'] ?? localRecording.summary
            ..ownerId = currentUserId
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
      await _deleteOrphanedSharedRecords(activeServerIds, currentUserId);
      print('メタデータ同期完了: ${remoteItems.length}件');
    } catch (e) {
      print('メタデータ同期エラー: $e');
      rethrow;
    }

  }

  Future<void> _deleteOrphanedSharedRecords(Set<String> activeServerIds, String currentUserId) async {
    
    // ローカルにある「共有された(コピー)レコード」を全て取得
    // - 自分のデータである (念のため)
    // - remoteId が入っている (クラウド同期済み)
    // - sourceOriginalId が入っている (＝共有されたコピーである)
    final sharedLocalRecordings = await isar.recordings
        .filter()
        .ownerIdEqualTo(currentUserId)
        .remoteIdIsNotNull()
        // .sourceOriginalIdIsNotNull() // 自分の未アップロードデータを守る
        .needsCloudUpdateEqualTo(false) // ★追加: アップロード待ちのデータは消さないように保護
        .needsCloudDeleteEqualTo(false)
        .findAll();

    // サーバーIDリストに存在しないものを特定
    final idsToDelete = <int>[];
    
    for (final recording in sharedLocalRecordings) {
      // ローカルのremoteIdが、サーバーのリストになければ削除対象
      if (!activeServerIds.contains(recording.remoteId)) {
        print('削除対象を検知: ${recording.title} (Server ID missing)');
        idsToDelete.add(recording.id);
        
        // 音声ファイルの実体も消すならここでFile(recording.filePath).delete()などを行う
        if (recording.filePath.isNotEmpty) {
          final file = File(recording.filePath);
          if (await file.exists()) {
            await file.delete();
            print('ローカル音声削除: ${recording.filePath}');
          }
        }
      }
    }

    // 一括削除実行
    if (idsToDelete.isNotEmpty) {
      await isar.writeTxn(() async {
        for (final id in idsToDelete) {
          final recording = await isar.recordings.get(id);
          
          if (recording != null) {
            await recording.transcripts.load();
            final segmentIds = recording.transcripts.map((e) => e.id).toList();
            if (segmentIds.isNotEmpty) {
              await isar.transcriptSegments.deleteAll(segmentIds);
            }
            await isar.recordings.delete(id);
          }
        }
        
      });
      print('${idsToDelete.length} 件の共有解除されたデータを削除しました。');
    }
  }

  Future<void> saveRecording({
    required String filePath,
    required int duration,
    required String ownerName,
    required String ownerId,
  }) async {

    final newRecording = Recording()
      ..title = DateFormat('yyyy/MM/dd HH:mmの録音').format(DateTime.now())
      ..filePath = filePath
      ..durationSeconds = duration
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now()
      ..ownerName = ownerName
      ..ownerId = ownerId
      ..status = 'processing';

    await isar.writeTxn(() async {
      await isar.recordings.put(newRecording);
    });
  }

  Future<void> updateRecording(Recording recording, String idToken, {bool syncTranscripts = false}) async {
  try {
    // Isar更新
    await isar.writeTxn(() async {
      recording.updatedAt = DateTime.now();
      await isar.recordings.put(recording);
      // Transcriptssegment変わった場合はここでput処理
    });

    final response = await dio.post(
      '$apiBaseUrl/update',
      options: Options(headers: {
          'Authorization': idToken,
          'Content-Type': 'application/json',
        }),
        data: {
          'id': recording.remoteId, // DynamoDBのキー
          'title': recording.title,
          'summary': recording.summary,
          'status': recording.status,
          'needsJsonUpload': syncTranscripts, // 文字起こし内容も変更したかフラグ
        },
    );

    // json同期必要
    if (syncTranscripts && response.data['json_upload_url'] != null) {
      final uploadUrl = response.data['json_upload_url'];
      final fullJson = await _generateFullTranscriptJson(recording);

      await dio.put(
        uploadUrl,
        data: jsonEncode(fullJson),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );
      print('json s3 upload completed');
    }
    print('Update Completed successfully');
  } catch (e) {
    print('Update failed: $e');
      // 失敗した場合、ローカルに「未同期フラグ」を立てて、
      // 次回起動時にリトライする
      rethrow;
    }
  }

  Future<void> deleteRecording(Recording recording, String idToken) async {
    try {
      // リモート削除
      await dio.delete(
        '$apiBaseUrl/delete',
        queryParameters: {'id': recording.remoteId},
        options: Options(headers: {
          'Authorization': idToken,
        }),
      );

      // リモート削除成功後にIsar削除
      await isar.writeTxn(() async {
        await recording.transcripts.load();
        
        // 紐づいているセグメントを全削除
        for (var segment in recording.transcripts) {
          await isar.transcriptSegments.delete(segment.id);
        }

        // 本体削除
        await isar.recordings.delete(recording.id);
      });

      print('Delete Completed successfully');

    } catch (e) {
      print('Delete failed: $e');

      // オフライン時対応必要な場合は「ネット接続してください」or 削除キューに入れて復帰時に削除実行する

      rethrow;
    }
  }

  Future<Map<String, dynamic>> _generateFullTranscriptJson(Recording recording) async {
    await recording.transcripts.load();
    final sortedTranscripts = recording.transcripts.toList()
      ..sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    
    return {
      "summary": recording.summary,
      // テキスト全文結合（検索用など）
      "full_transcript": sortedTranscripts.map((e) => e.text).join(""),
      // 詳細セグメント
      "speakers": sortedTranscripts.map((t) => {
        // IsarのIDではなく、UUIDなどを管理しているならそちらを使う
        "id": t.id, 
        "speaker": t.speaker,
        "text": t.text,
        "startTime": t.startTimeMs / 1000.0, // 秒換算
        "endTime": t.endTimeMs / 1000.0,
        "searchTokens": t.searchTokens,
        "translations": t.translations?.map((tr) => {
          "langCode": tr.langCode,
          "text": tr.text
        }).toList(),
      }).toList(),
    };
  }
  
  Future<void> syncPendingChanges(String idToken, String currentUserId) async {
    // 更新待ちのデータを取得
    final pendingUpdates = await isar.recordings
        .filter()
        .ownerIdEqualTo(currentUserId) // 自分の変更だけを対象にする
        .and()
        .needsCloudUpdateEqualTo(true)
        .findAll();

    for (var rec in pendingUpdates) {
      try {
        print("未同期データのアップロード中: ${rec.title}");
        // 更新実行
        await updateRecording(rec, idToken, syncTranscripts: true);
        
        // 成功したらフラグを下ろす
        await isar.writeTxn(() async {
          rec.needsCloudUpdate = false;
          await isar.recordings.put(rec);
        });
      } catch (e) {
        print("未同期データのアップロード失敗: $e");
        // 失敗しても次へ（次回リトライ）
      }
    }

  }

  Future<void> syncPendingDeletions(String idToken, String currentUserId) async {
    final pendingDeletes = await isar.recordings
      .filter()
      .ownerIdEqualTo(currentUserId) // 自分の削除リクエストだけを対象にする
      .and()
      .needsCloudDeleteEqualTo(true)
      .findAll();

    for (var rec in pendingDeletes) {
      try {
        print("未同期データの削除を実行中...");
        // クラウドから削除
        await dio.delete(
          '$apiBaseUrl/delete',
          queryParameters: {'id': rec.remoteId},
          options: Options(
            headers: {'Authorization': idToken,}
          ),
        );

        // 成功したらisarも削除
        await isar.writeTxn(() async {
          await rec.transcripts.load();
          for (var segment in rec.transcripts) {
            await isar.transcriptSegments.delete(segment.id);
          }
          await isar.recordings.delete(rec.id);
        });

        print("削除同期完了: ${rec.title}");
      } catch (e) {
        print("削除同期失敗: $e");
      }
    }
  }

  Future<void> requestTranslation(String recordingId, String targetLang, String idToken) async {
    final uri = Uri.parse('$apiBaseUrl/translate');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': idToken,
      },
      body: jsonEncode({
        'recordingId': recordingId,
        'targetLang': targetLang,
      }),
    );

    if (response.statusCode != 202 && response.statusCode != 200) {
      throw Exception('Translation Request Failed: ${response.body}');
    }
  }

}