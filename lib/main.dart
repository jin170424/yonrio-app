import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter/material.dart';
// 日本語対応（カレンダーやコピー貼り付けメニューなど）のために必要
import 'package:flutter_localizations/flutter_localizations.dart';

// データベース(Isar)を使うためのライブラリ
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voice_app/models/transcript_segment.dart';

// 自分で作ったファイルを読み込む
// ※ "voice_app" の部分は、pubspec.yamlのnameと同じにする
import 'package:voice_app/screens/home_screen.dart'; 
import 'package:voice_app/screens/login_screen.dart';
import 'package:voice_app/models/recording.dart'; // DBの設計図
import 'package:voice_app/services/processing_service.dart';
import 'package:voice_app/services/user_service.dart';

//amplify config
import 'amplifyconfiguration.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

// オフラインかどうか
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'services/network_service.dart';

late Isar isar;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// アプリのスタート地点
void main() async {
  // アプリが起動する前に、必要な準備（データベースの準備など）をするためのおまじない
  WidgetsFlutterBinding.ensureInitialized();

  // 1. データベース(Isar)を開く準備
  // スマホの中の「アプリ専用の保存場所」のパスを取得する
  final dir = await getApplicationDocumentsDirectory();

  // 2. Isarを開く
  // ここで開いておくと、アプリ中のどこからでも Isar.getInstance() で呼び出せるようになる
  isar = await Isar.open(
    [
      RecordingSchema,
      TranscriptSegmentSchema,
    ], // recording.g.dart で作られた「設計図」を渡す
    directory: dir.path, // 保存場所を指定
    inspector: true,
  );

  NetworkService().initialize();

  await _configureAmplify();
  await ProcessingService().initNotifications();

  // 準備ができたらアプリを画面に描画開始
  runApp(const MyApp());
}

Future<void> _configureAmplify() async {
  try {
    final auth = AmplifyAuthCognito();
    await Amplify.addPlugin(auth);

    await Amplify.configure(amplifyconfig);
    safePrint('Amplify configured successfully');
  } on Exception catch (e) {
    safePrint('Amplify config error: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLoading = true; // チェック中は true
  bool _isLoggedIn = false; // ログイン済みなら true

  @override
  void initState() {
    super.initState();
    // アプリ起動時にログインチェックを実行
    _checkAuthState();
  }

  // ログイン状態を確認する関数
  Future<void> _checkAuthState() async {
    // ネット接続状況を確認
    // オフラインの場合はamplifyへの問い合わせをスキップ
    final isConnected = await InternetConnection().hasInternetAccess;

    if (!isConnected) {
      safePrint('オフラインのためログインチェックをスキップします');
      setState(() {
        _isLoggedIn = true; // キャッシュの有無にかかわらずオフライン時はホーム画面に遷移
        _isLoading = false;
      });
      return;
    }

    // オンライン時はamplifyでログイン状態確認
    try {
      final user = await Amplify.Auth.getCurrentUser();
      safePrint('ログイン済みユーザー: ${user.username}');
      UserService().syncUserAttributes();
      setState(() {
        _isLoggedIn = true; // ログイン済み
        _isLoading = false; // チェック完了
      });
    } on AuthException catch (e) {
      safePrint('未ログイン状態です: ${e.message}');
      setState(() {
        _isLoggedIn = false; // 未ログイン
        _isLoading = false; // チェック完了
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // アプリのタイトル（Androidのタスク一覧などに表示される）
      title: '文字起こしアプリ',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      // --- 日本語化の設定 ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'), // 日本語に対応させる
      ],
      // --------------------

      // アプリ全体のデザイン設定
      theme: ThemeData(
        primarySwatch: Colors.blue, // メインカラー
        useMaterial3: true, // 新しいGoogleのデザインルールを使う
      ),
      // アプリ起動時に最初に表示する画面
      // ログイン機能を実装済みなら LoginScreen()
      // まだなら HomeScreen() にしておく
      home: _isLoading
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : _isLoggedIn
        ? const HomeScreen()
        : const LoginScreen(), 
    );
  }
}