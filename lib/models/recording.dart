import 'package:isar/isar.dart';

// ファイル名と同じにする必要がある (コード生成用)
part 'recording.g.dart';

@collection
class Recording {
  // 自動採番のID
  Id id = Isar.autoIncrement;

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

  // 文字起こしテキスト (全文検索用)
  @Index(type: IndexType.value)
  String? transcription;

  // AI要約
  String? summary;
  
  // タグなどのリンクはここに追加
  // final tags = IsarLinks<Tag>();
}