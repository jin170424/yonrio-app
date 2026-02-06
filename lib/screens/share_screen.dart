import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:voice_app/services/share_service.dart';

class ShareScreen extends StatelessWidget {
  // 共有したいテキストを受け取る
  final String textContent;
  final String? recordingId;
  final String filePath;
  final bool hasTranscript;
  final bool isOwner;
  
  const ShareScreen({
    super.key, 
    required this.textContent,
    required this.recordingId,
    required this.filePath,
    required this.hasTranscript,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    final bool isUploaded = recordingId != null;
    final bool canShareText = hasTranscript;
    final bool canShareLocalFile = File(filePath).existsSync();

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
            leading: Icon(Icons.text_fields, 
              color: canShareText ? Colors.blue : Colors.grey),
            title: Text('テキストのみ共有',
              style: TextStyle(color: canShareText ? Colors.black : Colors.grey)),
            subtitle: canShareText 
              ? const Text('文字起こし結果をLINEやメールに貼り付けます')
              : const Text('※文字起こしデータがありません'),
            enabled: canShareText,
            onTap: canShareText ? () {
              Share.share(textContent);
            } : null,
          ),
          const Divider(),
          
          if (isOwner) ...[
            // ローカル音声ファイル共有 (オフラインでもOK)
            ListTile(
              leading: Icon(Icons.audio_file, 
                color: canShareLocalFile ? Colors.purple : Colors.grey),
              title: Text('音声ファイルを送信',
                style: TextStyle(color: canShareLocalFile ? Colors.black : Colors.grey)),
              subtitle: canShareLocalFile
                ? const Text('録音データ(.m4a)を直接送信します')
                : const Text('※ファイルが見つかりません'),
              enabled: canShareLocalFile,
              onTap: canShareLocalFile ? () async {
                // XFileを使ってファイルを共有
                final xFile = XFile(filePath);
                await Share.shareXFiles([xFile], text: '録音データ');
              } : null,
            ),
            const Divider(),

            // 音声ファイルのリンク発行 (AWS S3)
            ListTile(
              leading: Icon(Icons.link, 
                color: isUploaded ? Colors.green : Colors.grey),
              title: Text('音声リンクを発行 (S3)',
                style: TextStyle(color: isUploaded ? Colors.black : Colors.grey)),
              subtitle: isUploaded 
                  ? const Text('誰でも聞けるURLを作成します (1時間有効)')
                  : const Text('※クラウドへの保存が必要です'),
              enabled: isUploaded,
              onTap: isUploaded ? () {
                // TODO: Presigned URL発行処理
                const dummyUrl = "https://s3.aws.amazon.com/.../audio.m4a";
                Share.share("音声ファイルのリンクです: $dummyUrl");
              } : null,
            ),
            const Divider(),
            
            // 3. アプリ内共有 (オプション機能)
            ListTile(
              leading: Icon(Icons.people, 
                color: isUploaded ? Colors.orange : Colors.grey),
              title: Text('ユーザーを指定して送信',
                style: TextStyle(color: isUploaded ? Colors.black : Colors.grey)),
              subtitle: isUploaded 
                  ? const Text('相手のアプリ内に共有データを送信します')
                  : const Text('※クラウドへの保存が必要です'),
              enabled: isUploaded,
              onTap: isUploaded ? () {
                _showUserShareDialog(context);
              } : null,
            ),
          ]
        ],
      ),
    );
  }

  void _showUserShareDialog(BuildContext context) {
    if (recordingId == null) return;
    final emailController = TextEditingController();
    final shareService = ShareService();
    bool isLoading = false;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('チームメンバーに共有'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('相手のメールアドレスを入力してください。'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'メールアドレス',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !isLoading,
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    final email = emailController.text.trim();
                    if (email.isEmpty) return;
                    setState(() { isLoading = true; });
                    try {
                      await shareService.shareRecording(recordingId!, email);
                      if (context.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('共有に成功しました')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        setState(() { isLoading = false; });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('共有する'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}