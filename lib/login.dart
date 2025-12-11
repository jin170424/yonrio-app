import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  // 入力フィールドのコントローラー
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // ログインボタンが押されたときの処理
  void _login() {
    // フォームのバリデーションを実行
    if (_formKey.currentState!.validate()) {
      // バリデーションが成功した場合の処理
      final email = _emailController.text;
      final password = _passwordController.text;

      // 実際にはここで認証APIを呼び出すなどの処理を行います
      print('ログイン試行:');
      print('メールアドレス: $email');
      print('パスワード: $password');

      // 成功メッセージを表示
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログインに成功しました (仮)')));

      // 画面遷移などの処理は省略
    }
  }

  // アカウント作成リンクが押されたときの処理
  void _goToSignUp() {
    print('アカウント作成画面へ遷移');
    // 実際にはNavigator.pushでサインアップ画面へ遷移します
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('アカウント作成画面へ遷移 (仮)')));
  }

  @override
  void dispose() {
    // コントローラーを破棄してメモリリークを防ぐ
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 画像のように外枠を模したデザインにするため、PaddingとCardを使用
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400), // PCでの見栄えを考慮
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // LOGIN タイトル
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30.0),
                      child: Text(
                        'LOGIN',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),

                    // メールアドレス入力フィールド
                    _buildTextField(
                      controller: _emailController,
                      labelText: 'メールアドレス',
                      hintText: 'user@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'メールアドレスを入力してください';
                        }
                        // 簡単なメールアドレス形式のチェック
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return '有効なメールアドレスを入力してください';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // パスワード入力フィールド
                    _buildTextField(
                      controller: _passwordController,
                      labelText: 'パスワード',
                      obscureText: true, // パスワードを非表示にする
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'パスワードを入力してください';
                        }
                        if (value.length < 6) {
                          return 'パスワードは6文字以上で入力してください';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 40),

                    // LOGIN ボタン
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300, // 画像に近い色
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                            side: const BorderSide(
                              color: Colors.black54,
                            ), // 画像のような薄い枠線
                          ),
                        ),
                        child: const Text(
                          'LOGIN',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // アカウントの作成 リンク
                    TextButton(
                      onPressed: _goToSignUp,
                      child: const Text(
                        'アカウントの作成',
                        style: TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // テキストフィールドを共通化するヘルパーメソッド
  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelText, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.grey.shade200, // 画像の薄いグレーの背景
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Colors.black54), // 画像のような薄い枠線
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Colors.black54),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

class HomeScreen extends StatelessWidget {
  final String email;
  const HomeScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ホーム画面')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'ようこそ！ログインに成功しました',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text('認証ユーザー: $email'),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // ログアウト処理（ログイン画面に戻る）
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
              child: const Text('ログアウト'),
            ),
          ],
        ),
      ),
    );
  }
}
