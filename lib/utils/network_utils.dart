import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import 'package:voice_app/screens/login_screen.dart';


///  クラウド処理が必要な操作をする場合にrunWithNetworkCheckで囲んで使用
///
///  import 'package:voice_app/utils/network_utils.dart';
///  
///  ElevatedButton(
///   onPressed: () {
///     // 関数で包む
///     runWithNetworkCheck(
///       context: context,
///       action: () async {
///         // --- ここにネットが必要な処理を書く ---

///        print("クラウドにデータを送信中...");
///        // await Amplify... など

///         // 完了メッセージなどもここ
///         ScaffoldMessenger.of(context).showSnackBar(
///           const SnackBar(content: Text('送信完了しました')),
///         );
///       },
///     );
///   },
/// ),

/// ネット接続とログインセッションを確認してから処理を実行する関数
/// 接続がない場合はSnackBarを表示して終了する
Future<void> runWithNetworkCheck({
  required BuildContext context,
  required Future<void> Function() action, // 実行したい処理
}) async {
  // ネットに接続されているか
  final bool isConnected = await InternetConnection().hasInternetAccess;

  // 画面が閉じられていたら何もしない
  if (!context.mounted) return;

  // オフラインの場合
  if (!isConnected) {
    // SnackBarを出す
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ネットワークに接続してください'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
        backgroundColor: Colors.black87,
      ),
    );
    return; // 処理を中断
  }

  try {
    // Amplifyにセッション問い合わせ
    final session = await Amplify.Auth.fetchAuthSession();

    if (!session.isSignedIn) {
      throw const AuthNotAuthorizedException('Not signed in');
    }
    // オンラインの場合、本来やりたかった処理を実行
    await action();
  } on AuthException catch (e) {
    // セッション切れ
    safePrint('セッション切れエラー: $e');

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ログイン期限が切れました。再ログインしてください。'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        backgroundColor: Colors.black87,
      ),
    );
    // ログイン画面に強制遷移
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  } catch (e) {
    // その他エラー
    safePrint('エラー: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('エラーが発生しました')),
    );
  }
}