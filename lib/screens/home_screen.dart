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
                      ),
                    );
                  },
                );
              },
            ),

      // ===== 右下のボタン群 =====
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // ログイン画面に戻るボタン
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

          // 共有ボタン
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

          // 録音追加ボタン
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

  // 秒数を 00:00 に変換
  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}
