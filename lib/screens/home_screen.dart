import 'dart:io'; // File操作用
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:file_picker/file_picker.dart'; // インポート用
import 'package:path_provider/path_provider.dart'; // パス取得用
import 'package:share_plus/share_plus.dart'; // 共有用
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

  // ★インポート処理
  Future<void> _importFile() async {
    try {
      // ファイル選択画面を開く
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'], 
      );

      if (result != null && result.files.single.path != null) {
        await runWithNetworkCheck(
          context: context,
          action: () async {
            await _processImport(result.files.single.path!, result.files.single.name);
          }
        );
      }
    } catch (e) {
      print('インポート前処理エラー: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('録音リスト'),
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
          // 念のためAppBarにもログアウトボタンを置いておきます
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await Amplify.Auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                }
              } on AuthException catch (e) {
                safePrint('Error signing out: ${e.message}');
              }
            },
          )
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
                  return const Center(child: Text('録音・インポートしたファイルがありません'));
                }

                return ListView.builder(
                  itemCount: recordings.length,
                  itemBuilder: (context, index) {
                    final recording = recordings[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          recording.title.startsWith("インポート") 
                              ? Icons.folder 
                              : Icons.mic, 
                          color: Colors.blue
                        ),
                        title: Text(recording.title),
                        subtitle: Text(
                          '${DateFormat('yyyy/MM/dd HH:mm').format(recording.createdAt)}'
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ResultScreen(
                                recording: recording,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),

      // ★ここがボタンエリアです。4つ全て復活させました！
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 1. ログイン画面に戻る（ログアウト）
          FloatingActionButton(
            heroTag: 'logout',
            mini: true,
            backgroundColor: Colors.grey,
            onPressed: () async {
               // ログアウト処理をしてログイン画面へ
               await Amplify.Auth.signOut();
               if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
               }
            },
            child: const Icon(Icons.logout),
          ),

          const SizedBox(width: 12),

          // 2. 共有ボタン（ダミー）
          FloatingActionButton(
            heroTag: 'share',
            mini: true,
            backgroundColor: Colors.green,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('リスト全体の共有機能は開発中です')),
              );
            },
            child: const Icon(Icons.share),
          ),

          const SizedBox(width: 12),

          // 3. インポートボタン（オレンジ色）
          FloatingActionButton(
            heroTag: 'import',
            backgroundColor: Colors.orange,
            onPressed: _importFile, 
            child: const Icon(Icons.file_upload),
          ),

          const SizedBox(width: 12),

          // 4. 録音追加ボタン（メイン）
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RecordingScreen(),
                ),
              );
            },
            child: const Icon(Icons.mic),
          ),
        ],
      ),
    );
  }
}