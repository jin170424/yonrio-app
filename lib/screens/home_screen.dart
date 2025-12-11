import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'recording_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('録音リスト')),
      
      // リスト表示部分 (本来はIsarからデータを取得して表示する)
      body: ListView.builder(
        itemCount: 3, // ダミーで3件表示
        itemBuilder: (context, index) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.mic),
              title: Text('会議の録音 ${index + 1}'),
              subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // タップしたら詳細(結果)画面へ
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ResultScreen()),
                );
              },
            ),
          );
        },
      ),
      
      // 録音画面へ行くボタン
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
}