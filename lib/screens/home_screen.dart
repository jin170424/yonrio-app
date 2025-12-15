import 'package:flutter/material.dart';
import 'package:isar/isar.dart'; // データベースを使う
import 'package:intl/intl.dart';  // 日付表示用

// 作ったファイルをインポート
import '../models/recording.dart';
import 'recording_screen.dart';
import 'result_screen.dart';

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
            .sortByCreatedAtDesc() // 新しい順
            .watch(fireImmediately: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('録音リスト')),
      
      // StreamBuilderを使うと、DBが更新されるたびに画面も勝手に更新される
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
                        title: Text(recording.title), // DBのタイトル
                        subtitle: Text(
                          // 日付と長さを表示
                          '${DateFormat('yyyy/MM/dd HH:mm').format(recording.createdAt)}  (${_formatDuration(recording.durationSeconds)})'
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // 詳細画面へデータを渡して移動
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ResultScreen(
                                recording: recording // ★ここでデータを渡す！
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
      
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RecordingScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // 秒数を 00:00 にする関数
  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}