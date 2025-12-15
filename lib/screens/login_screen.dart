import 'package:flutter/material.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import 'home_screen.dart'; // ログインできたらホームへ

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>{
  String? _validatePassword(String password) {
    if (password.length < 8) {
      return 'パスワードは8文字以上必要です。';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'パスワードには大文字を含めてください。';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'パスワードには小文字を含めてください。';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'パスワードには数字を含めてください。';
    }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'パスワードには記号(!@#など)を含めてください。';
    }
    return null; // 問題なし
  }

  // 入力された文字を管理するもの
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _preferredNameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoginMode = true; // ログインか、新規登録か
  bool _isConfirming = false; // 新規登録後の確認コード入力モードか

  // ログイン処理
  Future<void> _signIn() async {
    try {
      final result = await Amplify.Auth.signIn(
        username: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (result.isSignedIn) {
        _goToHome();
      } else {
        // 多要素認証などが必要な場合の処理
        print('Sign in result: $result');
      }
    } on AuthException catch (e) {
      _showError('ログインエラー: ${e.message}');
    }
  }

  // 新規登録処理
  Future<void> _signUp() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _passwordConfirmController.text.trim();

    if (password != confirmPassword) {
      _showError('パスワードが一致しません。');
      return;
    }

    final validationError = _validatePassword(password);
    if (validationError != null) {
      _showError(validationError);
    }

    try {
      final result = await Amplify.Auth.signUp(
        username: _emailController.text.trim(),
        password: password,
        options: SignUpOptions(
          userAttributes: {
            CognitoUserAttributeKey.email: _emailController.text.trim(),
            CognitoUserAttributeKey.preferredUsername: _preferredNameController.text.trim(),
          },
        ),
      );

      // 次のステップ（確認コード入力）へ画面を切り替え
      setState(() {
        _isConfirming = true; 
      });
      
      if (result.isSignUpComplete) {
         // 確認不要設定の場合はそのままログインへ
        _signIn();
      } 
      // else {
      //   _showError('確認コードをメールに送信しました。\nコードを入力してください。');
      // }

    } on AuthException catch (e) {
      _showError('登録エラー: ${e.message}');
    }
  }

  // 確認コード送信処理
  Future<void> _confirmSignUp() async {
    try {
      final result = await Amplify.Auth.confirmSignUp(
        username: _emailController.text.trim(),
        confirmationCode: _codeController.text.trim(),
      );

      if (result.isSignUpComplete) {
        _showError('登録完了！ログインします。');
        // 自動的にログイン処理へ
        await _signIn();
      }
    } on AuthException catch (e) {
      _showError('確認エラー: ${e.message}');
    }
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text(_isLoginMode ? 'ログイン' : '新規登録')),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             // メールアドレス入力
//             TextField(
//               controller: _emailController,
//               decoration: const InputDecoration(labelText: 'メールアドレス'),
//             ),
//             const SizedBox(height: 10),
            
//             // パスワード入力
//             TextField(
//               controller: _passwordController,
//               decoration: const InputDecoration(labelText: 'パスワード'),
//               obscureText: true, // パスワードを隠す
//             ),
//             const SizedBox(height: 30),
            
//             // 実行ボタン
//             ElevatedButton(
//               onPressed: () {
//                 // TODO: ここにAWS Cognitoのログイン処理を書く
//                 print("Email: ${_emailController.text}");
//                 print("Pass: ${_passwordController.text}");
                
//                 // 【ダミー】とりあえず無条件でホームへ進む
//                 Navigator.pushReplacement(
//                   context,
//                   MaterialPageRoute(builder: (context) => const HomeScreen()),
//                 );
//               },
//               child: Text(_isLoginMode ? 'ログイン' : '登録する'),
//             ),
            
//             // モード切替ボタン
//             TextButton(
//               onPressed: () {
//                 setState(() {
//                   _isLoginMode = !_isLoginMode;
//                 });
//               },
//               child: Text(_isLoginMode ? '新規登録はこちら' : 'ログインはこちら'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
  @override
    Widget build(BuildContext context) {
      // 画面構成
      return Scaffold(
        appBar: AppBar(title: Text(_isConfirming ? '確認コード入力' : (_isLoginMode ? 'ログイン' : '新規登録'))),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- 通常のログイン/登録フォーム ---
              if (!_isConfirming) ...[
                if (!_isLoginMode) ...[
                TextField(
                  controller: _preferredNameController,
                  decoration: const InputDecoration(labelText: 'ユーザー表示名'),
                ),
                const SizedBox(height: 10),
              ],
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'メールアドレス'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'パスワード'),
                  obscureText: true,
                ),
                const SizedBox(height: 10),
                if(!_isLoginMode) ...[
                  TextField(
                    controller: _passwordConfirmController,
                    decoration: const InputDecoration(labelText: 'パスワード（確認）'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 10)
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isLoginMode ? _signIn : _signUp,
                  child: Text(_isLoginMode ? 'ログイン' : '登録する'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLoginMode = !_isLoginMode;
                    });
                  },
                  child: Text(_isLoginMode ? '新規登録はこちら' : 'ログインはこちら'),
                ),
              ] 
              // --- 確認コード入力フォーム (新規登録直後に表示) ---
              // 開発時はスキップし、そのままログインする仕様
              else ...[
                const Text('メールに届いた6桁のコードを入力してください'),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: '確認コード'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _confirmSignUp,
                  child: const Text('認証してログイン'),
                ),
                TextButton(
                  onPressed: () => setState(() => _isConfirming = false),
                  child: const Text('戻る'),
                ),
              ],
            ],
          ),
        ),
      );
    }
  }