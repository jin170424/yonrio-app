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
  late String? remoteId;

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
  late DateTime createdAt;

  // 更新日時
  @Index()
  late DateTime updatedAt;

  // ★ここが抜けていました（メタデータ同期の判定に使います）
  late DateTime lastSyncTime;

  // ストリーミング再生用
  String? s3AudioUrl;

  // 翻訳データの再取得や同期用
  String? s3TranscriptJsonUrl;

  // 共有データの管理用(自分が作成したものか、共有されたものか)
  // 削除時にS3を消していいかの判定ロジックに使用
  String? sourceOriginalId;

  // DynamoDBのstatus
  late String status; // processing, completed, error

  // 文字起こし結果 (全文)
  @Index(type: IndexType.value, caseSensitive: false)
  String? transcription;

  // 要約結果
  @Index(type: IndexType.value, caseSensitive: false)
  String? summary;

  // ★追加: お気に入りフラグ (デフォルトは false)
  bool isFavorite = false;

  // 他のユーザーへの共有状況
  List<SharedUser>? sharedWith;

  // 1対多のリレーション (文字起こしセグメント)
  final transcripts = IsarLinks<TranscriptSegment>();
}

@embedded
class SharedUser {
  String? userId;
  String? name;
}