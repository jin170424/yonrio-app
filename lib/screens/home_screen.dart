import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

import '../models/recording.dart';
import 'recording_screen.dart';
import 'result_screen.dart';
import 'login_screen.dart';
import '../repositories/recording_repository.dart';
import '../services/get_idtoken_service.dart';

// 検索フィルタの種類
enum SearchType { all, audio, image }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Stream<List<Recording>>? _recordingStream;
  late final RecordingRepository _repository;
  bool _isSyncing = false;

  // 検索用ステート
  final TextEditingController _searchController = TextEditingController();
  SearchType _selectedType = SearchType.all;

  @override
  void initState() {
    super.initState();

    final isar = Isar.getInstance();
    if (isar != null) {
      _repository = RecordingRepository(isar);
      // 初期表示（全件取得）
      _updateRecordingStream();
      // 画面表示時にメタデータ同期を実行
      _syncMetadataList();
    }

    // 検索文字が変わるたびにリストを更新
    _searchController.addListener(() {
      _updateRecordingStream();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ★検索条件に基づいてストリームを更新する処理
  void _updateRecordingStream() {
    final isar = Isar.getInstance();
    if (isar == null) return;

    final queryText = _searchController.text.trim();

    // 【重要】型合わせのためのダミー条件 (実質全件)
    var q = isar.recordings.filter().idGreaterThan(-1);

    // 1. キーワード検索 (タイトル OR 文字起こし OR 要約)
    if (queryText.isNotEmpty) {
      q = q.and().group((g) => g
        .titleContains(queryText, caseSensitive: false)
        .or()
        .transcriptionContains(queryText, caseSensitive: false)
        .or()
        .summaryContains(queryText, caseSensitive: false)
      );
    }

    // 2. タイプ別フィルタ (拡張子で判定)
    if (_selectedType == SearchType.image) {
      // 画像の場合
      q = q.and().group((g) => g
        .filePathEndsWith('.jpg', caseSensitive: false).or()
        .filePathEndsWith('.jpeg', caseSensitive: false).or()
        .filePathEndsWith('.png', caseSensitive: false)
      );
    } else if (_selectedType == SearchType.audio) {
      // 音声の場合
      q = q.and().group((g) => g
        .filePathEndsWith('.wav', caseSensitive: false).or()
        .filePathEndsWith('.m4a', caseSensitive: false).or()
        .filePathEndsWith('.mp3', caseSensitive: false).or()
        .filePathEndsWith('.aac', caseSensitive: false)
      );
    }

    // 3. 作成日時の新しい順で監視
    setState(() {
      _recordingStream = q.sortByCreatedAtDesc().watch(fireImmediately: true);
    });
  }

  // 一時的なユニークIDを生成
  String _generateUniqueId() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (index) => chars[random.nextInt(chars.length)]).join();
  }

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

  // 削除確認ダイアログ
  Future<void> _confirmAndDelete(Recording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('削除しますか？'),
          content: Text('「${recording.title}」を削除します。\nこの操作は元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        if (recording.filePath.isNotEmpty) {
           final file = File(recording.filePath);
           if (await file.exists()) {
             await file.delete();
           }
        }
      } catch (e) {
        print("ファイル削除エラー: $e");
      }

      final isar = Isar.getInstance();
      if (isar != null) {
        await isar.writeTxn(() async {
          await isar.recordings.delete(recording.id);
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除しました')),
        );
      }
    }
  }

  // アイテム長押しメニュー
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
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('名前を変更'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(recording);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('削除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmAndDelete(recording);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // メタデータ同期
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

  // ファイルインポート
  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
      );

      if (result != null && result.files.single.path != null) {
        final originalPath = result.files.single.path!;
        final fileName = result.files.single.name;

        final appDir = await getApplicationDocumentsDirectory();
        final newPath = '${appDir.path}/imported_$fileName';
        await File(originalPath).copy(newPath);

        String currentUserId = 'unknown_user';
        try {
            final user = await Amplify.Auth.getCurrentUser();
            currentUserId = user.userId;
        } catch(e) {
            print("ユーザーID取得失敗(インポート): $e");
        }

        final isar = Isar.getInstance();
        if (isar != null) {
          final newRecording = Recording()
            ..title = "インポート: $fileName"
            ..filePath = newPath
            ..durationSeconds = 0
            ..createdAt = DateTime.now()
            ..updatedAt = DateTime.now()
            ..lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0)
            ..ownerName = currentUserId
            ..remoteId = _generateUniqueId()
            ..status = 'pending';

          await isar.writeTxn(() async {
            await isar.recordings.put(newRecording);
          });

          if(!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ファイルをインポートしました')),
          );
        }
      }
    } catch (e) {
      print('インポートエラー: $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('インポート失敗: $e')),
        );
      }
    }
  }

  // 画像保存
  Future<void> _pickAndSaveImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: source);

      if (photo == null) return;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => const Center(child: CircularProgressIndicator()),
      );

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImage = await File(photo.path).copy('${appDir.path}/$fileName');

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

  // 画像ソース選択
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

  // フィルタチップのウィジェット
  Widget _buildFilterChip(String label, SearchType type, {IconData? icon}) {
    final isSelected = _selectedType == type;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 4)
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (bool selected) {
        setState(() {
          if (isSelected && type != SearchType.all) {
             _selectedType = SearchType.all;
          } else {
             _selectedType = type;
          }
          _updateRecordingStream();
        });
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.blueAccent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.grey.shade300),
      ),
      showCheckmark: false,
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
            onPressed: _isSyncing ? null : _syncMetadataList,
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
          // 検索バーとフィルタチップエリア
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                // 検索フィールド
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'タイトル・文字起こし内容を検索...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 10),
                // フィルタ切り替え
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('すべて', SearchType.all),
                      const SizedBox(width: 8),
                      _buildFilterChip('音声のみ', SearchType.audio, icon: Icons.mic),
                      const SizedBox(width: 8),
                      _buildFilterChip('画像のみ', SearchType.image, icon: Icons.image),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // リスト表示エリア
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
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search_off, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                ? 'データがありません'
                                : '見つかりませんでした',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: recordings.length,
                      padding: const EdgeInsets.only(bottom: 80),
                      itemBuilder: (context, index) {
                        final recording = recordings[index];
                        final path = recording.filePath.toLowerCase();
                        final fileName = path.split('/').last;

                        // 通常のアイコンロジック
                        IconData leadIcon = Icons.mic;
                        Color iconColor = Colors.blue;

                        if (path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png')) {
                          leadIcon = Icons.image;
                          iconColor = Colors.purple;
                        } else if (fileName.startsWith('imported_')) {
                          leadIcon = Icons.folder;
                          iconColor = Colors.orange;
                        }

                        // ★変更点: ヒット箇所の判定ロジック
                        final queryText = _searchController.text.trim().toLowerCase();
                        final bool isSearching = queryText.isNotEmpty;
                        
                        // タイトルに含まれているか
                        final bool isTitleMatch = recording.title.toLowerCase().contains(queryText);
                        
                        // 本文に含まれているか
                        final bool isTranscriptMatch = (recording.transcription ?? '').toLowerCase().contains(queryText);
                        
                        // 要約に含まれているか
                        final bool isSummaryMatch = (recording.summary ?? '').toLowerCase().contains(queryText);

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                                backgroundColor: iconColor.withOpacity(0.1),
                                child: Icon(leadIcon, color: iconColor),
                            ),
                            title: Text(recording.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(DateFormat('yyyy/MM/dd HH:mm').format(recording.createdAt)),
                                
                                // ★変更点: ヒットした箇所の表示
                                if (isSearching && !isTitleMatch) ...[
                                  const SizedBox(height: 4),
                                  if (isTranscriptMatch)
                                    Row(
                                      children: [
                                        const Icon(Icons.description, size: 12, color: Colors.blueGrey),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '本文に「${_searchController.text}」が含まれています',
                                            style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (!isTranscriptMatch && isSummaryMatch)
                                    Row(
                                      children: [
                                        const Icon(Icons.summarize, size: 12, color: Colors.orange),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '要約に「${_searchController.text}」が含まれています',
                                            style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ResultScreen(
                                    recording: recording,
                                    searchQuery: _searchController.text.isNotEmpty 
                                        ? _searchController.text 
                                        : null,
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