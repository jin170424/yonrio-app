import 'dart:async';
import 'dart:io'; 
import 'dart:math'; 
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:file_picker/file_picker.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_app/models/transcript_segment.dart';
import 'package:voice_app/services/user_service.dart'; 
import 'package:voice_app/utils/network_utils.dart';
import 'package:path/path.dart' as p;

import '../models/recording.dart';
import 'recording_screen.dart';
import 'result_screen.dart';
import 'login_screen.dart';
import '../repositories/recording_repository.dart';
import '../services/get_idtoken_service.dart';

enum RecordingFilterType { all, audio, image, favorite }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Stream<List<Recording>>? _recordingStream;
  late final RecordingRepository _repository;
  bool _isSyncing = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  RecordingFilterType _filterType = RecordingFilterType.all;
  Timer? _debounceTimer;
  

  @override
  void initState() {
    super.initState();

    final isar = Isar.getInstance();
    final dio = Dio();
    if (isar != null) {
      _repository = RecordingRepository(isar: isar, dio: dio);
      _searchController.addListener(_onSearchChanged);
      _updateRecordingStream(); 
      _quietSyncOnStartup();
      _initRecordingStream();
      _quietSyncOnStartup();
    }
    
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
        _updateRecordingStream();
      }
    });
  }

  // ★これが赤波の原因だった「命令の中身」です
  void _updateRecordingStream() {
    final isar = Isar.getInstance();
    if (isar == null) return;

    // 1. 基本フィルタ（削除待ちでないもの）
    QueryBuilder<Recording, Recording, QAfterFilterCondition> query =
        isar.recordings.filter().needsCloudDeleteEqualTo(false);

    // 2. 音声・画像の絞り込み
    if (_filterType == RecordingFilterType.image) {
      query = query.group((q) => q
          .filePathEndsWith('.jpg', caseSensitive: false).or()
          .filePathEndsWith('.jpeg', caseSensitive: false).or()
          .filePathEndsWith('.png', caseSensitive: false).or()
          .filePathEndsWith('.heic', caseSensitive: false));
    } else if (_filterType == RecordingFilterType.audio) {
      query = query.group((q) => q
          .not().filePathEndsWith('.jpg', caseSensitive: false).and()
          .not().filePathEndsWith('.jpeg', caseSensitive: false).and()
          .not().filePathEndsWith('.png', caseSensitive: false).and()
          .not().filePathEndsWith('.heic', caseSensitive: false));
    }
    else if (_filterType == RecordingFilterType.favorite) {
      query = query.and().isFavoriteEqualTo(true);
    }
    // 3. キーワード検索（タイトル、要約、文字起こしの中身）
    if (_searchQuery.isNotEmpty) {
      query = query.and().group((q) => q
          .titleContains(_searchQuery, caseSensitive: false)
          .or()
          .summaryContains(_searchQuery, caseSensitive: false)
          .or()
          .transcripts((t) => t.textContains(_searchQuery, caseSensitive: false))
      );
    }

    setState(() {
      _recordingStream = query.sortByCreatedAtDesc().watch(fireImmediately: true);
    });
  }

  // フィルタボタン（チップ）を作る部品
  Widget _buildFilterChip(String label, RecordingFilterType type) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          setState(() {
            if (selected) {
              _filterType = type;
              _updateRecordingStream();
            }
          });
        },
        selectedColor: Colors.blue.withOpacity(0.2),
        labelStyle: TextStyle(
          color: isSelected ? Colors.blue : Colors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  void _initRecordingStream() {
    final isar = Isar.getInstance();
    if (isar != null) {
      setState(() {
        _recordingStream = isar.recordings
            .where()
            .filter()
            .needsCloudDeleteEqualTo(false)
            .sortByCreatedAtDesc()
            .watch(fireImmediately: true);
      });
    }
  }

  Future<void> _quietSyncOnStartup() async {
    // ネット接続確認
    final bool isConnected = await InternetConnection().hasInternetAccess;
    if (!isConnected) {
      print("ホーム画面: オフラインのため起動時の同期をスキップしました");
      return;
    }
    
    // 画面が生きていれば同期実行
    if (mounted) {
      try {
        final tokenService = GetIdtokenService();
        final token = await tokenService.getIdtoken();
        if (token != null) {
          await _repository.syncPendingDeletions(token);
          await _repository.syncPendingChanges(token);
          await _syncMetadataList();
        }
      } catch (e) {
        print("起動時同期エラー: $e");
      }
    }
  }

  // ★追加: 一時的なユニークIDを生成する関数
  String _generateUniqueId() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (index) => chars[random.nextInt(chars.length)]).join();
  }

  // --- HEAD由来の機能: 名前変更・削除・メニュー ---

  // 名前変更ダイアログ
  void _showRenameDialog(Recording recording) {
    final TextEditingController controller = TextEditingController(text: recording.title);
    
    showDialog(
      context: context, 
      builder: (context) {
        return AlertDialog(
          title: const Text('名前を変更'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "新しいタイトルを入力"),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('キャンセル')
            ),
            ElevatedButton(
              onPressed: () async {
                final newTitle = controller.text.trim();
                if (newTitle.isNotEmpty) {
                  final isar = Isar.getInstance();
                  if (isar != null) {
                    await isar.writeTxn(() async {
                      recording.title = newTitle;
                      recording.updatedAt = DateTime.now();
                      recording.needsCloudUpdate = true;
                      await isar.recordings.put(recording);
                    });
                  }
                }
                Navigator.pop(context);
              }, 
              child: const Text('変更')
            ),
          ],
        );
      }
    );
  }

  // 削除確認ダイアログと削除実行
  Future<void> _confirmAndDelete(Recording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('削除しますか？'),
          content: Text('「${recording.title}」を削除します。\nこの操作は元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), // いいえ
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true), // はい
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (_) => Center(child: CircularProgressIndicator()),
      );
    
    try {
      // 追加 クラウドからの削除
      final isar = Isar.getInstance()!;
      final bool isConnected = await InternetConnection().hasInternetAccess;

      // オフラインの場合
      if (!isConnected || recording.remoteId == null) {
        // ローカルファイルの削除
        final localFilePath = recording.filePath;
        if (localFilePath.isNotEmpty) {
          final file = File(localFilePath);
          if (await file.exists()) {
            await file.delete();
          }
        }

        await isar.writeTxn(() async {
          if (recording.remoteId == null) {
            await recording.transcripts.load();
            for (var s in recording.transcripts) {
              await isar.transcriptSegments.delete(s.id);
            }
            await isar.recordings.delete(recording.id);
          } else {
            // クラウドにデータがある場合フラグ立てる
            recording.needsCloudDelete = true;
            recording.filePath = "";
            await isar.recordings.put(recording);
          }
        });

        if (mounted) Navigator.pop(context); // ローディング消す
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(recording.remoteId == null ? "削除しました" : "オフラインのため削除予約しました"))
          );
        }
        return;
      }

      // オンラインの場合
      final dio = Dio();
      final repository = RecordingRepository(isar: isar, dio: dio);
      final idToken = await GetIdtokenService().getIdtoken();

      if (idToken == null) {
        // トークンが取れない場合は例外を投げて catch ブロックへ移動させる
        throw Exception("認証トークンが取得できませんでした。再ログインしてください。");
      }
      final localFilePath = recording.filePath;
      // repository で api削除 -> Isar削除実行
      await repository.deleteRecording(recording, idToken);

      // 1. 実ファイルの削除 (スマホの容量を空けるため)
      if (localFilePath.isNotEmpty){
        final file = File(localFilePath);
        if (await file.exists()) {
          await file.delete();
          print('ローカル音声ファイルを削除しました。');
        }
      }

      if (mounted) Navigator.pop(context);
        
      if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除しました')),
        );
    } catch (e) {
      print("削除失敗: $e");
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました。通信状況を確認してください'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 長押し時のメニューシート
  void _showItemMenu(Recording recording) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  recording.isFavorite ? Icons.star : Icons.star_border,
                  color: recording.isFavorite ? Colors.orange : Colors.grey,
                ),
                title: Text(recording.isFavorite ? 'お気に入りを解除' : 'お気に入りに登録'),
                onTap: () async {
                  Navigator.pop(context); // メニューを閉じる
                  final isar = Isar.getInstance();
                  if (isar != null) {
                    await isar.writeTxn(() async {
                      recording.isFavorite = !recording.isFavorite;
                      // recording.needsCloudUpdate = true; // クラウド同期する場合はコメントアウトを外す
                      await isar.recordings.put(recording);
                    });
                    
                    // スナックバーで通知
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(recording.isFavorite ? 'お気に入りに登録しました' : 'お気に入りを解除しました'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  }
                },
              ),
              const Divider(), // 区切り線
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('名前を変更'),
                onTap: () {
                  Navigator.pop(context); // シートを閉じる
                  _showRenameDialog(recording); // 名前変更へ
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('削除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context); // シートを閉じる
                  _confirmAndDelete(recording); // 削除確認へ
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- origin/main由来の機能: 同期 ---

  Future<void> _syncMetadataList() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();

      if (token != null) {
        await _repository.syncMetadataList(token);
        print('メタデータ同期完了');
      } else {
        print('未ログインのため同期スキップ');
      }
    } catch (e) {
      print('同期エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同期エラー: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  // --- 共通機能 ---

  Future<void> _importFile() async {
    // try {
    //   final result = await FilePicker.platform.pickFiles(
    //     type: FileType.custom,
    //     allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'], 
    //   );

    //   if (result != null && result.files.single.path != null) {
    //     await _processImport(result.files.single.path!, result.files.single.name);
    //   }
    try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio, // customではなくaudioに変更
    );

    if (result != null && result.files.single.path != null) {
      await _processImport(result.files.single.path!, result.files.single.name);
    }
    } catch (e) {
      print('インポートエラー');
    }
  }

  Future<void> _processImport(String originalPath, String fileName) async {
    final ownerName = await UserService().getPreferredUsername();
      try{
        if (ownerName == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ユーザー情報が取得できません。再ログインしてください。')),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
          return;
        }

        // アプリ内の安全な場所にコピーする
        final appDir = await getApplicationDocumentsDirectory();
        // final newPath = '${appDir.path}/imported_$fileName';
        String ext = p.extension(originalPath);
        String safeFileName = fileName;
        if (!safeFileName.toLowerCase().endsWith(ext.toLowerCase())) {
           // 含まれていなければ、お尻にくっつける
          safeFileName = '$safeFileName$ext';
        }
        final newPath = '${appDir.path}/imported_$safeFileName';
        await File(originalPath).copy(newPath);

        // データベースに登録
        final isar = Isar.getInstance();
        if (isar != null) {
          final newRecording = Recording()
            ..title = "インポート: $fileName" 
            ..filePath = newPath
            ..ownerName = ownerName
            ..durationSeconds = 0
            ..createdAt = DateTime.now()
            ..updatedAt = DateTime.now()
            ..status = "processing";

          await isar.writeTxn(() async {
            await isar.recordings.put(newRecording);
          });
          
          if(!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ファイルをインポートしました')),
          );
        }
    } catch (e) {
      print('インポートエラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('インポート失敗: $e')),
      );
    }
  }

  Future<void> _pickAndSaveImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: source);

      if (photo == null) return;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImage = await File(photo.path).copy('${appDir.path}/$fileName');

      // ユーザーIDを取得して ownerName に入れる
      String currentUserId = 'unknown_user';
      try {
          final user = await Amplify.Auth.getCurrentUser();
          currentUserId = user.userId;
      } catch(e) {
          print("ユーザーID取得失敗(画像保存): $e");
      }

      final isar = Isar.getInstance();
      if (isar != null) {
        final newRecording = Recording()
          ..title = "画像: ${DateFormat('MM/dd HH:mm').format(DateTime.now())}" 
          ..filePath = savedImage.path
          ..durationSeconds = 0 
          ..createdAt = DateTime.now()
          ..updatedAt = DateTime.now()
          ..lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0)
          ..ownerName = currentUserId
          // ★修正: nullだと重複扱いされるため、一時的なIDを生成
          ..remoteId = _generateUniqueId()
          ..status = 'pending';

        await isar.writeTxn(() async {
          await isar.recordings.put(newRecording);
        });
      }

      if (!mounted) return;

      Navigator.pop(context); 

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リストに追加しました')),
      );

    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
         Navigator.pop(context);
      }
      print('画像保存エラー: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    }
  }

  void _showOcrSourceSelection() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('カメラで撮影'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSaveImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('アルバムから選択'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSaveImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(Recording recording) {
    if (recording.remoteId == null) {
      // 1. クラウドIDがない = 未保存
      return _statusBadge(Icons.cloud_off, '未保存', Colors.grey);
    } else if (recording.transcripts.isEmpty) {
      // 2. IDはあるが、データがまだローカルにない = 未解析
      // アイコンを「待機中/解析」っぽいものに変更
      return _statusBadge(Icons.analytics_outlined, '未解析', Colors.orange);
    } else {
      // 3. 文字起こしデータがある = 完了
      return _statusBadge(Icons.check_circle, '完了', Colors.green);
    }
  }

  // バッジのデザイン定義
  Widget _statusBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('録音・メモリスト'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2)
                  )
                : const Icon(Icons.sync),
            tooltip: 'リストを更新',
            onPressed: _isSyncing 
            ? null 
            : () {
              runWithNetworkCheck(
                context: context, 
                action: _syncMetadataList
              );
              },
          ),
          IconButton(
             icon: const Icon(Icons.file_upload),
             tooltip: "ファイルをインポート",
             onPressed: _importFile,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "リストを共有",
            onPressed: () {
               ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('リスト全体の共有機能は開発中です')),
                );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "ログアウト",
            onPressed: () async {
              try {
                await Amplify.Auth.signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } on AuthException catch (e) {
                safePrint('Error signing out: ${e.message}');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 検索バーとフィルタボタンのエリア
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: Colors.grey.shade50,
            child: Column(
              children: [
                // 検索ボックス
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'タイトルや文字起こし内容で検索',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = "");
                              _updateRecordingStream();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 8),
                // フィルタボタン
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('すべて', RecordingFilterType.all),
                      _buildFilterChip('お気に入り', RecordingFilterType.favorite),
                      _buildFilterChip('音声のみ', RecordingFilterType.audio),
                      _buildFilterChip('画像のみ', RecordingFilterType.image),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. 元々のリスト表示部分 (Expandedで囲むのが重要！)
          Expanded(
            child: _recordingStream == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<Recording>>(
                    stream: _recordingStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('エラー: ${snapshot.error}'));
                      }
                      final recordings = snapshot.data;
                      if (recordings == null || recordings.isEmpty) {
                        return const Center(child: Text('データがありません'));
                      }

                      return ListView.builder(
                        itemCount: recordings.length,
                        itemBuilder: (context, index) {
                          final recording = recordings[index];
                          
                          // ファイル名やアイコンの判定（既存のコード）
                          final path = recording.filePath.toLowerCase();
                          final fileName = path.split('/').last;
                          IconData leadIcon = Icons.mic;
                          Color iconColor = Colors.blue;
                          if (path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png')) {
                            leadIcon = Icons.image;
                            iconColor = Colors.purple;
                          } else if (fileName.startsWith('imported_')) {
                            leadIcon = Icons.folder;
                            iconColor = Colors.orange;
                          }

                          // ★追加: 文字起こし内でのヒット判定
                          bool hasHitInTranscript = false;
                          String? hitTextSnippet;

                          if (_searchQuery.isNotEmpty) {
                            // 文字起こしリストの中から、検索ワードを含む最初のセグメントを探す
                            for (var segment in recording.transcripts) {
                              if (segment.text.toLowerCase().contains(_searchQuery.toLowerCase())) {
                                hasHitInTranscript = true;
                                // ヒットした箇所の抜粋を作る（オプション）
                                // 長すぎる場合はカットするなどの処理も可能ですが、まずはシンプルに
                                hitTextSnippet = "本文に「$_searchQuery」が含まれます";
                                break; // 1つ見つかればOK
                              }
                            }
                            // もしtranscriptsが空でも、summaryにある場合もチェックしても良いかも
                            if (!hasHitInTranscript && recording.summary != null) {
                              if (recording.summary!.toLowerCase().contains(_searchQuery.toLowerCase())) {
                                  hasHitInTranscript = true;
                                  hitTextSnippet = "要約に「$_searchQuery」が含まれます";
                              }
                            }
                          }

                          return Card(
                            child: ListTile(
                              leading: Icon(leadIcon, color: iconColor),
                              title: Text(recording.title),
                              
                              // ★修正: サブタイトル部分を書き換え
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1. もともとの日付表示
                                  Text(DateFormat('yyyy/MM/dd HH:mm').format(recording.createdAt)),
                                  
                                  // ★追加: ここにステータスバッジを入れます
                                  const SizedBox(height: 4), // 少し隙間をあける
                                  _buildStatusChip(recording),
                                  
                                  // 2. ヒットした場合のメッセージ表示
                                  if (hasHitInTranscript && hitTextSnippet != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.manage_search, size: 16, color: Colors.orange),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              hitTextSnippet,
                                              style: const TextStyle(
                                                color: Colors.orange, 
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ResultScreen(
                                      recording: recording,
                                      searchKeyword: _searchQuery.isNotEmpty ? _searchQuery : null,
                                    ),
                                  ),
                                );
                              },
                              onLongPress: () {
                                _showItemMenu(recording);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'ocr',
            mini: true, 
            backgroundColor: Colors.purple,
            onPressed: _showOcrSourceSelection, 
            child: const Icon(Icons.camera_alt),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RecordingScreen()),
              );
            },
            child: const Icon(Icons.mic),
          ),
        ],
      ),
    );
  }
}