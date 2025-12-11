import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 💡 修正: main関数を非同期にし、SharedPreferencesを初期化します
void main() async {
  // Flutterエンジンとの連携を保証
  WidgetsFlutterBinding.ensureInitialized();

  // SharedPreferencesのインスタンスを事前に取得し、初期化が完了するのを待つ
  await SharedPreferences.getInstance();

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

  // ===================================================================
  // 💡 挿入箇所 (1) コントローラー定義の直後
  // ===================================================================
  // 追加: テスト用認証情報
  static const String _testEmail = 'test@example.com';
  static const String _testPassword = 'password123';

  // 追加: テストアカウントを作成して自動ログインするヘルパー
  Future<void> _createTestAccountAndLogin() async {
    final prefs = await SharedPreferences.getInstance();
    // 登録処理と同じロジックでテストアカウントをローカルに作成
    await prefs.setString(_testEmail, _testPassword);

    // フィールドにセットしてログイン処理を呼ぶ　あとで消してもいい
    _emailController.text = _testEmail;
    _passwordController.text = _testPassword;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('テストアカウント作成: $_testEmail / $_testPassword')),
    );

    // 登録処理完了を待ってから、ログイン処理を呼び出す
    await Future.delayed(const Duration(milliseconds: 200));
    _login();
  }
  // ===================================================================

  // 💡 追加: 画面遷移のヘルパーメソッド
  void _navigateToHomeScreen(BuildContext context, String email) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => HomeScreen(email: email)),
    );
  }

  // 💡 変更: ログインボタンが押されたときの処理 (SharedPreferencesと照合)
  void _login() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      final inputEmail = _emailController.text;
      final inputPassword = _passwordController.text;

      final storedPassword = prefs.getString(inputEmail);

      if (storedPassword != null && storedPassword == inputPassword) {
        // 認証成功
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ ログイン成功!'),
            backgroundColor: Colors.blue,
          ),
        );
        print('ログイン成功: $inputEmail');

        // 成功したら次の画面（HomeScreen）へ遷移
        _navigateToHomeScreen(context, inputEmail);
      } else if (storedPassword == null) {
        // メールアドレスが登録されていない
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登録されていないメールアドレスです。'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        // パスワードが一致しない
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('パスワードが違います。'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 💡 追加: 仮の登録処理 (SharedPreferencesに保存)
  Future<void> _signUp() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      final email = _emailController.text;
      final password = _passwordController.text;

      await prefs.setString(email, password);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 登録完了: $email'),
          backgroundColor: Colors.green,
        ),
      );
      print('アカウントが登録されました: $email');

      _emailController.clear();
      _passwordController.clear();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
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

                    // メールアドレス入力フィールド (変更なし)
                    _buildTextField(
                      controller: _emailController,
                      labelText: 'メールアドレス',
                      hintText: 'user@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'メールアドレスを入力してください';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return '有効なメールアドレスを入力してください';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // パスワード入力フィールド (変更なし)
                    _buildTextField(
                      controller: _passwordController,
                      labelText: 'パスワード',
                      obscureText: true,
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

                    // LOGIN ボタン (変更なし)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                            side: const BorderSide(color: Colors.black54),
                          ),
                        ),
                        child: const Text(
                          'LOGIN',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // アカウントの作成 リンク (変更なし)
                    TextButton(
                      onPressed: _signUp,
                      child: const Text(
                        'アカウントの作成 (登録)',
                        style: TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),

                    // 追加: テストアカウントを作成してログインするボタン
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _createTestAccountAndLogin,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(
                            color: Colors.black54,
                          ), // 外枠線を追加
                          foregroundColor: Colors.black, // 文字色を黒に設定
                        ),
                        child: const Text('テストアカウントでワンクリックログイン'),
                      ),
                    ),
                    // ===================================================================
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // テキストフィールドを共通化するヘルパーメソッド (変更なし)
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
            fillColor: Colors.grey.shade200,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Colors.black54),
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

// 💡 ログイン後の仮のホーム画面 (変更なし)
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
