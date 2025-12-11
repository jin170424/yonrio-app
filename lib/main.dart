import 'package:flutter/material.dart';
// 日本語の日付表示などに対応させる設定
import 'package:flutter_localizations/flutter_localizations.dart';

// 先ほど作ったホーム画面のファイルを読み込む
// ※ "voice_app" の部分は pubspec.yaml の name と同じにする
import 'package:voice_app/screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文字起こしアプリ',
      // 日本語対応の設定（カレンダーなどが日本語になります）
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'), // 日本語
      ],
      
      // アプリのテーマカラー（今回は青）
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true, // 新しいデザインを有効化
      ),
      
      // アプリ起動時に最初に表示する画面
      home: const LoginScreen(),
    );
  }
}