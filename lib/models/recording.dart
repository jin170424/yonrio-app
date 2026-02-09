import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:voice_app/models/transcript_segment.dart';

// ファイル名と同じにする必要がある (コード生成用)
part 'recording.g.dart';

@collection
class Recording {
  // 自動採番のID
  Id id = Isar.autoIncrement;

  // DynamoDBのid(UUID)
  @Index(unique: true, replace:true)
  String? remoteId;

  @Index()
  String? ownerId;
  
  late String ownerName;

  // タイトル (検索用にインデックスを貼る)
  @Index(type: IndexType.value)
  late String title;

  // 音声ファイルの保存パス
  late String filePath;

  // 録音時間（秒）
  int durationSeconds = 0;

  // 作成日時 (並び替え用)
  @Index()
  DateTime createdAt = DateTime.now();

  // 更新日時
  @Index()
  DateTime updatedAt = DateTime.now();

  // ストリーミング再生用
  String? s3AudioUrl;

  // 翻訳データの再取得や同期用
  String? s3TranscriptJsonUrl;

  // 共有データの管理用(自分が作成したものか、共有されたものか)
  // 削除時にS3を消していいかの判定ロジックに使用
  String? sourceOriginalId;

  // DynamoDBのstatus
  late String? status;

  // 文字起こしテキスト全文
  @Index(type: IndexType.value)
  String? transcription;

  // AI要約
  String? summary;
  List<TranslationData>? summaryTranslations;

  String? originalLanguage;

  DateTime? lastSyncTime;

  List<SharedUser>? sharedWith;

  bool needsCloudUpdate = false;

  bool needsCloudDelete = false;
  
  final transcripts = IsarLinks<TranscriptSegment>();
}

@embedded
class SharedUser {
  String? userId;
  String? name;
}