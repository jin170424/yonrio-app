import 'package:flutter/material.dart';
// 日本語対応（カレンダーやコピー貼り付けメニューなど）のために必要
import 'package:flutter_localizations/flutter_localizations.dart';

// データベース(Isar)を使うためのライブラリ
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

// 自分で作ったファイルを読み込む
// ※ "voice_app" の部分は、pubspec.yamlのnameと同じにする
import 'package:voice_app/screens/home_screen.dart'; 
import 'package:voice_app/screens/login_screen.dart';
import 'package:voice_app/models/recording.dart'; // DBの設計図

// アプリのスタート地点
void main() async {
  // アプリが起動する前に、必要な準備（データベースの準備など）をするためのおまじない
  WidgetsFlutterBinding.ensureInitialized();

  // 1. データベース(Isar)を開く準備
  // スマホの中の「アプリ専用の保存場所」のパスを取得する
  final dir = await getApplicationDocumentsDirectory();

  // 2. Isarを開く
  // ここで開いておくと、アプリ中のどこからでも Isar.getInstance() で呼び出せるようになる
  await Isar.open(
    [RecordingSchema], // recording.g.dart で作られた「設計図」を渡す
    directory: dir.path, // 保存場所を指定
  );

  // 準備ができたらアプリを画面に描画開始
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // アプリのタイトル（Androidのタスク一覧などに表示される）
      title: '文字起こしアプリ',

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
      home: const LoginScreen(), 
    );
  }
}