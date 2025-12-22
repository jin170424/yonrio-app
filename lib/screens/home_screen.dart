// home_screen.dart

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';

// 作ったファイルをインポート
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
  // 録音リストをデータベースからリアルタイムで監視する
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
        // データベースの変更を監視して、新しい順に並べる
        _recordingStream = isar.recordings
            .where()
            .sortByCreatedAtDesc()
            .watch(fireImmediately: true);
      });
    }
  }

  // 名前変更ダイアログを表示するメソッド
  void _showRenameDialog(BuildContext context, Recording recording) {
    final TextEditingController titleController = TextEditingController(text: recording.title);

    showDialog(
      context: context,
      builder: (dialogContext) { // ダイアログ専用のcontextとして扱う
        return AlertDialog(
          title: const Text('録音名を変更'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(hintText: "新しい録音名"),
            onSubmitted: (value) {
              _saveNewTitle(dialogContext, recording, value);
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('キャンセル'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            FilledButton(
              child: const Text('保存'),
              onPressed: () {
                _saveNewTitle(dialogContext, recording, titleController.text);
              },
            ),
          ],
        );
      },
    );
  }

  // 新しい名前をデータベースに保存するメソッド
  void _saveNewTitle(BuildContext context, Recording recording, String newTitle) async {
    final trimmedTitle = newTitle.trim();
    
    // SnackBarを表示するためのメッセンジャーを先に取得しておく（pop後のcontextエラー防止）
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (trimmedTitle.isEmpty) {
      Navigator.of(context).pop();
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('タイトルは空にできません。')),
      );
      return;
    }

    // データベースを更新
    await recording.updateTitle(trimmedTitle);
    
    // ダイアログを閉じる（contextがまだ有効か確認）
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // 保存したメッセンジャーを使って通知を表示
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('タイトルを更新しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('録音リスト')),

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
                  return const Center(child: Text('まだ録音がありません'));
                }

                return ListView.builder(
                  itemCount: recordings.length,
                  itemBuilder: (context, index) {
                    final recording = recordings[index];

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.mic, color: Colors.blue),
                        title: Text(recording.title),
                        subtitle: Text(
                          '${DateFormat('yyyy/MM/dd HH:mm').format(recording.createdAt)}'
                          ' (${_formatDuration(recording.durationSeconds)})',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ResultScreen(),
                            ),
                          );
                        },
                        // 長押しで名前変更ダイアログを開く
                        onLongPress: () {
                          _showRenameDialog(context, recording);
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
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
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
                const SnackBar(content: Text('共有ボタンが押されました')),
              );
            },
            child: const Icon(Icons.share),
          ),
          const SizedBox(width: 12),
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
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}