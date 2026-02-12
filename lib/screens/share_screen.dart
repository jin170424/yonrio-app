import 'dart:io';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:voice_app/models/recording.dart';
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
            // ListTile(
            //   leading: Icon(Icons.link, 
            //     color: isUploaded ? Colors.green : Colors.grey),
            //   title: Text('音声リンクを発行 (S3)',
            //     style: TextStyle(color: isUploaded ? Colors.black : Colors.grey)),
            //   subtitle: isUploaded 
            //       ? const Text('誰でも聞けるURLを作成します (1時間有効)')
            //       : const Text('※クラウドへの保存が必要です'),
            //   enabled: isUploaded,
            //   onTap: isUploaded ? () {
            //     // TODO: Presigned URL発行処理
            //     const dummyUrl = "https://s3.aws.amazon.com/.../audio.m4a";
            //     Share.share("音声ファイルのリンクです: $dummyUrl");
            //   } : null,
            // ),
            // const Divider(),
            
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
                // _showUserShareDialog(context);
                _showUserShareModal(context);
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
                      final attributes = await Amplify.Auth.fetchUserAttributes();
                      final myEmail = attributes
                          .firstWhere(
                            (e) => e.userAttributeKey == AuthUserAttributeKey.email,
                            orElse: () => const AuthUserAttribute(userAttributeKey: AuthUserAttributeKey.email, value: ''),
                          )
                          .value;

                      if (email == myEmail) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('自分自身には共有できません'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        setState(() { isLoading = false; });
                        return; // ここで処理を中断
                      }
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

//   void _showUserShareModal(BuildContext context) {
//     if (recordingId == null) return;
    
//     final emailController = TextEditingController();
//     final shareService = ShareService();
//     final isar = Isar.getInstance(); // データを読み込むために取得

//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true, // キーボードで隠れないように全画面対応にする
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (context) {
//         return DraggableScrollableSheet(
//           initialChildSize: 0.7, // 画面の7割くらいの高さで表示
//           minChildSize: 0.5,
//           maxChildSize: 0.95,
//           expand: false,
//           builder: (context, scrollController) {
//             // Isarから最新のデータを取得して表示する (リスト更新のため)
//             return StreamBuilder<List<Recording>>(
//               stream: isar!.recordings
//                   .filter()
//                   .remoteIdEqualTo(recordingId)
//                   .watch(fireImmediately: true),
//               builder: (context, snapshot) {
//                 final recording = snapshot.data?.firstOrNull;
//                 final sharedUsers = recording?.sharedWith ?? [];

//                 return Padding(
//                   // キーボードが出たときに底上げする設定
//                   padding: EdgeInsets.only(
//                     bottom: MediaQuery.of(context).viewInsets.bottom,
//                   ),
//                   child: Column(
//                     children: [
//                       // --- ヘッダー ---
//                       Padding(
//                         padding: const EdgeInsets.all(16.0),
//                         child: Row(
//                           children: [
//                             const Icon(Icons.people, color: Colors.orange),
//                             const SizedBox(width: 8),
//                             const Text(
//                               'チームメンバーに共有',
//                               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                             ),
//                             const Spacer(),
//                             IconButton(
//                               icon: const Icon(Icons.close),
//                               onPressed: () => Navigator.pop(context),
//                             ),
//                           ],
//                         ),
//                       ),
//                       const Divider(height: 1),

//                       StatefulBuilder(
//                         builder: (context, setState) {
//                           bool isLoading = false;
//                           String? errorText; // エラーメッセージ用変数

//                           // 内部関数: エラーをセットして再描画
//                           void setError(String? text) {
//                             setState(() {
//                               errorText = text;
//                               isLoading = false;
//                             });
//                           }

//                           return Padding(
//                             padding: const EdgeInsets.all(16.0),
//                             child: Row(
//                               crossAxisAlignment: CrossAxisAlignment.start, // エラーが出てもボタンの位置がずれないように
//                               children: [
//                                 Expanded(
//                                   child: TextField(
//                                     controller: emailController,
//                                     decoration: InputDecoration(
//                                       labelText: 'メールアドレスを追加',
//                                       border: const OutlineInputBorder(),
//                                       contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                                       isDense: true,
//                                       //  エラーがあれば赤文字で下に表示される
//                                       errorText: errorText, 
//                                     ),
//                                     keyboardType: TextInputType.emailAddress,
//                                     onChanged: (_) {
//                                       // 入力を開始したらエラーを消す
//                                       if (errorText != null) {
//                                         setState(() => errorText = null);
//                                       }
//                                     },
//                                   ),
//                                 ),
//                                 const SizedBox(width: 8),
//                                 // 送信ボタン
//                                 ElevatedButton(
//                                   onPressed: isLoading ? null : () async {
//                                     final email = emailController.text.trim();
//                                     if (email.isEmpty) return;

//                                     setState(() {
//                                       isLoading = true;
//                                       errorText = null; // リセット
//                                     });

//                                     try {
//                                       // 自分自身への共有チェック
//                                       final attributes = await Amplify.Auth.fetchUserAttributes();
//                                       final myEmail = attributes
//                                           .firstWhere(
//                                             (e) => e.userAttributeKey == AuthUserAttributeKey.email,
//                                             orElse: () => const AuthUserAttribute(userAttributeKey: AuthUserAttributeKey.email, value: ''),
//                                           )
//                                           .value;

//                                       if (email.toLowerCase() == myEmail.toLowerCase()) {
//                                         setError('自分自身には共有できません');
//                                         return;
//                                       }

//                                       await shareService.shareRecording(recordingId!, email);
                                      
//                                       // 成功時の処理
//                                       emailController.clear();
//                                       setState(() => isLoading = false);
                                      
//                                       if (context.mounted) {
//                                         // 成功通知は控えめなSnackBarで
//                                         ScaffoldMessenger.of(context).showSnackBar(
//                                           const SnackBar(content: Text('追加しました')),
//                                         );
//                                         // キーボードを閉じるなら以下を追加
//                                         // FocusScope.of(context).unfocus(); 
//                                       }
//                                     } catch (e) {
//                                       // エラー時は入力欄の下に表示
//                                       setError(e.toString().replaceAll("Exception: ", ""));
//                                     }
//                                   },
//                                   style: ElevatedButton.styleFrom(
//                                     backgroundColor: Colors.orange,
//                                     foregroundColor: Colors.white,
//                                     // エラー表示で高さが変わってもボタンが潰れないように少し調整
//                                     minimumSize: const Size(64, 48), 
//                                   ),
//                                   child: isLoading 
//                                     ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
//                                     : const Text('追加'),
//                                 ),
//                               ],
//                             ),
//                           );
//                         },
//                       ),

//                       // --- 共有済みリストの見出し ---
//                       Container(
//                         width: double.infinity,
//                         color: Colors.grey[100],
//                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                         child: Text(
//                           '共有済みのユーザー (${sharedUsers.length})',
//                           style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
//                         ),
//                       ),

//                       // --- リスト表示エリア ---
//                       Expanded(
//                         child: sharedUsers.isEmpty
//                             ? const Center(
//                                 child: Text("まだ共有しているユーザーはいません", style: TextStyle(color: Colors.grey)),
//                               )
//                             : ListView.builder(
//                                 controller: scrollController, // スクロール連携
//                                 itemCount: sharedUsers.length,
//                                 itemBuilder: (context, index) {
//                                   final user = sharedUsers[index];
//                                   return ListTile(
//                                     leading: CircleAvatar(
//                                       backgroundColor: Colors.orange.shade100,
//                                       child: Text(
//                                         (user.name ?? user.userId ?? "?").substring(0, 1).toUpperCase(),
//                                         style: const TextStyle(color: Colors.orange),
//                                       ),
//                                     ),
//                                     title: Text(user.name ?? "名称未設定"),
//                                     subtitle: Text(user.userId ?? ""),
//                                     // 将来的に削除機能をつけるならここ
//                                     // trailing: IconButton(icon: Icon(Icons.delete_outline), onPressed: (){...}),
//                                   );
//                                 },
//                               ),
//                       ),
//                     ],
//                   ),
//                 );
//               }
//             );
//           },
//         );
//       },
//     );
//   }

// }
void _showUserShareModal(BuildContext context) {
    if (recordingId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            // 中身を別ウィジェットに切り出して、状態管理を正常化する
            return _ShareModalContent(
              recordingId: recordingId!,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

// ShareScreenクラスの外側（ファイルの末尾など）にこのクラスを追加する
class _ShareModalContent extends StatefulWidget {
  final String recordingId;
  final ScrollController scrollController;

  const _ShareModalContent({
    required this.recordingId,
    required this.scrollController,
  });

  @override
  State<_ShareModalContent> createState() => _ShareModalContentState();
}

class _ShareModalContentState extends State<_ShareModalContent> {
  final TextEditingController _emailController = TextEditingController();
  final ShareService _shareService = ShareService();
  final Isar _isar = Isar.getInstance()!;
  
  bool _isLoading = false;
  String? _errorText; // 入力欄に表示するエラー
  String? _generalError; // モーダル上部のエラー
  String? _successMessage; // 成功通知

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _setError(String? text) {
    setState(() {
      _errorText = text;
      _generalError = null;
      _successMessage = null;
      _isLoading = false;
    });
  }

  void _setGeneralError(String? text) {
    setState(() {
      _generalError = text;
      _errorText = null;
      _successMessage = null;
      _isLoading = false;
    });
  }

  void _setSuccessMessage(String text) {
    setState(() {
      _successMessage = text;
      _generalError = null;    // 成功したらエラーは消す
      _errorText = null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Recording>>(
      stream: _isar.recordings
          .filter()
          .remoteIdEqualTo(widget.recordingId)
          .watch(fireImmediately: true),
      builder: (context, snapshot) {
        final recording = snapshot.data?.firstOrNull;
        // sharedUsersリストを取得（nullなら空リスト）
        final sharedUsers = recording?.sharedWith ?? [];

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // --- ヘッダー ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Text(
                      'チームメンバーに共有',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // 全体メッセージ表示エリア
              if (_generalError != null)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade50,
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _generalError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                        onPressed: () => setState(() => _generalError = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    ],
                  ),
                ),
          

              // 成功メッセージがある場合
              if (_successMessage != null)
                Container(
                  width: double.infinity,
                  color: Colors.green.shade50,
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.green),
                        onPressed: () => setState(() => _successMessage = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    ],
                  ),
                ),

              // --- 入力エリア ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'メールアドレスを入力',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          isDense: true,
                          errorText: _errorText, // エラーを表示
                          errorMaxLines: 2,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) {
                          // 入力し直したらエラーを消す
                          if (_errorText != null || _generalError != null|| _successMessage != null) {
                            setState(() { 
                              _errorText = null;
                              _generalError = null;  
                              _successMessage = null;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    // --- 追加ボタン ---
                    ElevatedButton(
                      onPressed: _isLoading ? null : () async {
                        final email = _emailController.text.trim();
                        if (email.isEmpty) return;

                        // キーボードを閉じる
                        FocusScope.of(context).unfocus();

                        setState(() {
                          _isLoading = true;
                          _errorText = null;
                          _generalError = null;
                          _successMessage = null;
                        });

                        try {
                          // 自分自身への共有チェック
                          final attributes = await Amplify.Auth.fetchUserAttributes();
                          final myEmail = attributes
                              .firstWhere(
                                (e) => e.userAttributeKey == AuthUserAttributeKey.email,
                                orElse: () => const AuthUserAttribute(userAttributeKey: AuthUserAttributeKey.email, value: ''),
                              )
                              .value;

                          if (email.toLowerCase() == myEmail.toLowerCase()) {
                            _setError('自分自身には共有できません');
                            return;
                          }

                          // 重複チェック (クライアントサイド)
                          // 既存のsharedUsersリストの中に、入力されたemailがあるか確認
                          final isDuplicate = sharedUsers.any((user) => 
                            (user.userId?.toLowerCase() == email.toLowerCase())                        );

                          if (isDuplicate) {
                            _setError('このユーザーは既に追加されています');
                            return;
                          }

                          // API送信
                          await _shareService.shareRecording(widget.recordingId, email);

                          // 成功時の処理
                          _emailController.clear();
                          setState(() => _isLoading = false);
                          _setSuccessMessage('$email に共有しました');

                        } catch (e) {
                          // サーバーからのエラーを表示
                          _setError(e.toString().replaceAll("Exception: ", ""));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(64, 48),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('共有'),
                    ),
                  ],
                ),
              ),

              // --- リスト見出し ---
              Container(
                width: double.infinity,
                color: Colors.grey[100],
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '共有済みのユーザー (${sharedUsers.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),

              // --- リスト表示 ---
              Expanded(
                child: sharedUsers.isEmpty
                    ? const Center(
                        child: Text("まだ共有しているユーザーはいません", style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        itemCount: sharedUsers.length,
                        itemBuilder: (context, index) {
                          final user = sharedUsers[index];
                          final userEmail = user.userId ?? "";
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Text(
                                (user.name ?? user.userId ?? "?").substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.orange),
                              ),
                            ),
                            title: Text(user.name ?? "名称未設定"),
                            subtitle: Text(user.userId ?? ""),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey),
                              onPressed: () async {
                                // 削除確認ダイアログ
                                final bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("共有を解除"),
                                    content: Text("$userEmail への共有を解除しますか？\n相手のアプリからもデータが削除されます。"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text("キャンセル"),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text("解除する"),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true) return;

                                // 削除処理実行
                                try {
                                  setState(() => _generalError = null);
                                  await _shareService.unshareRecording(widget.recordingId, userEmail);
                                  
                                  _setSuccessMessage('共有を解除しました');
                                } catch (e) {
                                  if (mounted) {
                                    _setGeneralError(e.toString().replaceAll("Exception: ", ""));
                                  }
                                }
                              },
                            )
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}