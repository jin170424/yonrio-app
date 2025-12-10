import 'package:flutter/material.dart';
import 'home_screen.dart'; // ログインできたらホームへ

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 入力された文字を管理するもの
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoginMode = true; // ログインか、新規登録か

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLoginMode ? 'ログイン' : '新規登録')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // メールアドレス入力
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'メールアドレス'),
            ),
            const SizedBox(height: 10),
            
            // パスワード入力
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'パスワード'),
              obscureText: true, // パスワードを隠す
            ),
            const SizedBox(height: 30),
            
            // 実行ボタン
            ElevatedButton(
              onPressed: () {
                // TODO: ここにAWS Cognitoのログイン処理を書く
                print("Email: ${_emailController.text}");
                print("Pass: ${_passwordController.text}");
                
                // 【ダミー】とりあえず無条件でホームへ進む
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                );
              },
              child: Text(_isLoginMode ? 'ログイン' : '登録する'),
            ),
            
            // モード切替ボタン
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoginMode = !_isLoginMode;
                });
              },
              child: Text(_isLoginMode ? '新規登録はこちら' : 'ログインはこちら'),
            ),
          ],
        ),
      ),
    );
  }
}