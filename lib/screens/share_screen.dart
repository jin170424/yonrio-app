import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class ShareScreen extends StatelessWidget {
  // 共有したいテキストを受け取る
  final String textContent;
  // ★音声ファイルのパスも受け取るように追加
  final String audioPath;
  
  const ShareScreen({
    super.key, 
    required this.textContent,
    required this.audioPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('共有・エクスポート')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('共有方法を選択してください', 
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // 1. テキストだけ共有 (LINEなどに文字を送る)
          ListTile(
            leading: const Icon(Icons.text_fields, color: Colors.blue),
            title: const Text('テキストのみ共有'),
            subtitle: const Text('文字起こし結果をLINEやメールに貼り付けます'),
            onTap: () {
              // share_plus を使って共有
              Share.share(textContent);
            },
          ),
          const Divider(),

          // 2. 音声ファイルそのものを共有 (NEW!)
          ListTile(
            leading: const Icon(Icons.audio_file, color: Colors.purple),
            title: const Text('音声ファイルを共有'),
            subtitle: const Text('m4aやmp3ファイルをLINEやドライブに送ります'),
            onTap: () async {
              // ファイルをXFile形式に変換して共有
              final xFile = XFile(audioPath);
              await Share.shareXFiles([xFile], text: '音声ファイル ($audioPath)');
            },
          ),
          const Divider(),

          // 3. 音声ファイルのリンク発行 (AWS S3)
          ListTile(
            leading: const Icon(Icons.link, color: Colors.green),
            title: const Text('音声リンクを発行 (S3)'),
            subtitle: const Text('誰でも聞けるURLを作成します (1時間有効)'),
            onTap: () {
              // TODO: ここにS3アップロード & URL発行処理を書く
              const dummyUrl = "https://s3.aws.amazon.com/example/audio.m4a";
              
              // URLを共有する
              Share.share("音声ファイルのリンクです: $dummyUrl");
            },
          ),
          const Divider(),
          
          // 4. アプリ内共有 (オプション機能)
          ListTile(
            leading: const Icon(Icons.people, color: Colors.orange),
            title: const Text('ユーザーを指定して送信'),
            subtitle: const Text('アプリ内の受信トレイに直接送ります'),
            onTap: () {
              // TODO: DynamoDB連携処理
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('この機能は開発中です')),
              );
            },
          ),
        ],
      ),
    );
  }
}
