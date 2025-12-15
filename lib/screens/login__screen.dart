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
      // 最初の画面はログイン画面のまま
      home: const LoginPage(),
    );
  }
}

// =========================================================================
// 既存のログイン画面 (LoginPage)
// =========================================================================

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

  // 追加: テスト用認証情報 (変更なし)
  static const String _testEmail = 'test@example.com';
  static const String _testPassword = 'password123';

  // 追加: テストアカウントを作成して自動ログインするヘルパー (変更なし)
  Future<void> _createTestAccountAndLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_testEmail, _testPassword);

    _emailController.text = _testEmail;
    _passwordController.text = _testPassword;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('テストアカウント作成: $_testEmail / $_testPassword')),
    );

    await Future.delayed(const Duration(milliseconds: 200));
    _login();
  }

  // 💡 追加: 画面遷移のヘルパーメソッド (変更なし)
  void _navigateToHomeScreen(BuildContext context, String email) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => HomeScreen(email: email)),
    );
  }

  // 💡 変更: ログインボタンが押されたときの処理 (変更なし)
  void _login() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      final inputEmail = _emailController.text;
      final inputPassword = _passwordController.text;

      final storedPassword = prefs.getString(inputEmail);

      if (storedPassword != null && storedPassword == inputPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ ログイン成功!'),
            backgroundColor: Colors.blue,
          ),
        );
        _navigateToHomeScreen(context, inputEmail);
      } else if (storedPassword == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登録されていないメールアドレスです。'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('パスワードが違います。'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 💡 削除: _signUpメソッドはログイン画面では不要になったため削除
  /*
  Future<void> _signUp() async {
    // ... (削除)
  }
  */

  // 💡 追加: アカウント作成画面へ遷移するメソッド
  void _goToSignUp() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SignUpPage()));
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
                    // ... (LOGIN タイトル、メール、パスワード入力フィールド) ...
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
                    _buildTextField(
                      controller: _emailController,
                      labelText: 'メールアドレス',
                      hintText: 'user@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'メールアドレスを入力してください';
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value))
                          return '有効なメールアドレスを入力してください';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _passwordController,
                      labelText: 'パスワード',
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'パスワードを入力してください';
                        if (value.length < 6) return 'パスワードは6文字以上で入力してください';
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

                    // 💡 修正: アカウントの作成 リンクを SignUpPage への遷移に変更
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

                    // テストアカウントボタン (変更なし)
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _createTestAccountAndLogin,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.black54),
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('テストアカウントでワンクリックログイン'),
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

  // テキストフィールドを共通化するヘルパーメソッド (変更なし)
  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    // ... (変更なし) ...
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

// =========================================================================
// 💡 追加: アカウント作成画面 (SignUpPage)
// =========================================================================

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();

  // 入力フィールドのコントローラー
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 💡 登録処理 (SharedPreferencesに保存)
  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      final email = _emailController.text;
      final password = _passwordController.text;

      // メールアドレスをキーとしてパスワードを保存
      await prefs.setString(email, password);
      // ユーザー名は今回保存しない（必要に応じて拡張可能）

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 登録完了: $email'),
          backgroundColor: Colors.green,
        ),
      );
      print('アカウントが登録されました: $email');

      // 登録完了後、ログイン画面に戻る
      _goToLogin();
    }
  }

  // 💡 ログイン画面に戻るメソッド
  void _goToLogin() {
    // 現在の画面を置き換える（戻るボタンで再び登録画面に戻らないようにするため）
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
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
                    // タイトル
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30.0),
                      child: Text(
                        'アカウントを作成',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),

                    // ユーザー名入力フィールド
                    _buildTextField(
                      controller: _usernameController,
                      labelText: 'ユーザー名',
                      hintText: 'ユーザー名を入力',
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'ユーザー名を入力してください';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

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

                    // 登録ボタン
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                            side: const BorderSide(color: Colors.black54),
                          ),
                        ),
                        child: const Text('登録', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // ログイン画面に戻るリンク
                    TextButton(
                      onPressed: _goToLogin,
                      child: const Text(
                        'ログイン画面に戻る',
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

  // TextFielld Helper (SignUpPage内で再利用できるよう、スコープ外に移動または修正が必要ですが、今回はそのまま再定義せず、既存のLoginPageStateのものを使用します。
  // ただし、_buildTextFieldは_LoginPageStateのプライベートメソッドなので、SignUpPageStateから直接はアクセスできません。
  // 便宜上、今回は_SignUpPageStateの直後にその定義をコピーします。)

  // 💡 注意: 実際のプロジェクトでは、このヘルパーメソッドはクラス外に移動して共有するのが一般的です。
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

// =========================================================================
// ログイン後の仮のホーム画面 (変更なし)
// =========================================================================

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
