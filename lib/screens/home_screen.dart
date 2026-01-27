import 'dart:io'; 
// ★追加: ランダムID生成用
import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:file_picker/file_picker.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:image_picker/image_picker.dart'; 
import 'package:voice_app/utils/network_utils.dart';

import '../models/recording.dart';
import 'recording_screen.dart';
import 'result_screen.dart';
import 'login_screen.dart';
import '../repositories/recording_repository.dart';
import '../services/get_idtoken_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Stream<List<Recording>>? _recordingStream;
  late final RecordingRepository _repository;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();

    final isar = Isar.getInstance();
    if (isar != null) {
      _repository = RecordingRepository(isar);
      _initRecordingStream();
      _quietSyncOnStartup();
    }
  }

  void _initRecordingStream() {
    final isar = Isar.getInstance();
    if (isar != null) {
      setState(() {
        _recordingStream = isar.recordings
            .where()
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
      await _syncMetadataList();
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

    if (confirmed == true) {
      // 1. 実ファイルの削除 (スマホの容量を空けるため)
      try {
        final file = File(recording.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print("ファイル削除エラー: $e");
        // ファイル削除に失敗してもDBからは消すように進める
      }

      // 2. データベース(Isar)から削除
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

  Future<String?> getPreferredUsername() async {
  try {
    final attributes = await Amplify.Auth.fetchUserAttributes();

    for (final element in attributes) {
      // CognitoUserAttributeKey.preferredUsername を使用して比較
      if (element.userAttributeKey == CognitoUserAttributeKey.preferredUsername) {
        return element.value;
      }
    }
    
    // 見つからなかった場合
    print('preferred_username is not set for this user.');
    return null;

  } on AuthException catch (e) {
    // ログインしていない、またはセッション切れの場合などのエラー処理
    print('Error fetching user attributes: ${e.message}');
    return null;
  } catch (e) {
    print('Unknown error: $e');
    return null;
  }
}
  // --- 共通機能 ---

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'], 
      );

      if (result != null && result.files.single.path != null) {
        await _processImport(result.files.single.path!, result.files.single.name);
      }
    } catch (e) {
      print('インポートエラー');
    }
  }

  Future<void> _processImport(String originalPath, String fileName) async {
    final ownerName = await getPreferredUsername();
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
        final newPath = '${appDir.path}/imported_$fileName';
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
      body: _recordingStream == null
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

                    return Card(
                      child: ListTile(
                        leading: Icon(leadIcon, color: iconColor),
                        title: Text(recording.title),
                        subtitle: Text(
                          DateFormat('yyyy/MM/dd HH:mm').format(recording.createdAt)
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ResultScreen(recording: recording),
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