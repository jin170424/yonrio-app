import 'package:isar/isar.dart';
import 'package:voice_app/models/transcript_segment.dart';

// 生成されるファイル名を指定
part 'recording.g.dart';

@collection
class Recording {
  // 自動採番ID
  Id id = Isar.autoIncrement;

  // DynamoDBのid(UUID)
  // ★修正: ローカル保存時(null)の重複を許容するため、ユニーク制約を外しました
  @Index()
  String? remoteId;

  late String ownerName;

  // タイトル (検索用にインデックス)
  @Index(type: IndexType.value)
  late String title;

  // 音声ファイルの保存パス
  late String filePath;

  // 録音時間（秒）
  int durationSeconds = 0;

  // 作成日時
  @Index()
  DateTime createdAt = DateTime.now();

  // 更新日時
  @Index()
  DateTime updatedAt = DateTime.now();

  // メタデータ同期の判定に使用
  DateTime? lastSyncTime;

  // ストリーミング再生用
  String? s3AudioUrl;

  // 翻訳データの再取得や同期用
  String? s3TranscriptJsonUrl;

  // 共有データの管理用
  String? sourceOriginalId;

  // ステータス (processing, completed, errorなど)
  String? status;

  // 文字起こし結果 (全文)
  @Index(type: IndexType.value, caseSensitive: false)
  String? transcription;

  // 要約結果
  @Index(type: IndexType.value, caseSensitive: false)
  String? summary;

  // お気に入りフラグ
  bool isFavorite = false;

  // 他のユーザーへの共有状況
  List<SharedUser>? sharedWith;

  // クラウド同期用のフラグ
  bool needsCloudUpdate = false;
  bool needsCloudDelete = false;
  
  // 1対多のリレーション
  final transcripts = IsarLinks<TranscriptSegment>();
}

@embedded
class SharedUser {
  String? userId;
  String? name;
}