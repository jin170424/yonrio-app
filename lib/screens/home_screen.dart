import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:file_picker/file_picker.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart'; 

import '../models/recording.dart';
import 'recording_screen.dart';
import 'result_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Stream<List<Recording>>? _recordingStream;

  @override
  void initState() {
    super.initState();
    _initRecordingStream();
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

  // ★名前変更ダイアログを表示する関数
  void _showRenameDialog(Recording recording) {
    final TextEditingController _controller = TextEditingController(text: recording.title);
    
    showDialog(
      context: context, 
      builder: (context) {
        return AlertDialog(
          title: const Text('名前を変更'),
          content: TextField(
            controller: _controller,
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
                final newTitle = _controller.text.trim();
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

        final isar = Isar.getInstance();
        if (isar != null) {
          final newRecording = Recording()
            ..title = "インポート: $fileName" 
            ..filePath = newPath
            ..durationSeconds = 0 
            ..createdAt = DateTime.now();

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
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await Amplify.Auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
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
                              builder: (context) => ResultScreen(recording: recording),
                            ),
                          );
                        },
                        // ★ここを追加！長押しで名前変更
                        onLongPress: () {
                          _showRenameDialog(recording);
                        },
                      ),
                    );
                  },
                );
              },
            ),

      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'logout',
            mini: true,
            backgroundColor: Colors.grey,
            onPressed: () async {
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
          FloatingActionButton(
            heroTag: 'import',
            backgroundColor: Colors.orange,
            onPressed: _importFile, 
            child: const Icon(Icons.file_upload),
          ),
          const SizedBox(width: 12),
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