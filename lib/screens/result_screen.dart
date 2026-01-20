import 'package:flutter/material.dart';
import 'package:voice_app/repositories/recording_repository.dart';
import '../services/gemini_service.dart';
import '../models/recording.dart';
import 'share_screen.dart';
import 'dart:io';
import '../services/s3upload_service.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import '../services/get_idtoken_service.dart';
import '../main.dart';

enum DisplayMode { transcription, summary }

class ResultScreen extends StatefulWidget {
  // 親(Home)からデータを受け取るための変数
  final Recording recording;

  const ResultScreen({super.key, required this.recording});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();
  late final RecordingRepository _repository;

  // -------
  late Stream<Recording?> _recordingStream;
  DisplayMode _currentMode = DisplayMode.transcription;
  bool _isProcessing = false;
  String _transcriptionText = "（文字起こしボタンを押してください）";
  String _summaryText = "要約ボタンを押してください";
  String _displayText = "";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _repository = RecordingRepository(isar);

    // ストリームセットアップ
    _recordingStream = isar.recordings.watchObject(widget.recording.id, fireImmediately: true);
    // 画面起動時に自動同期
    _autoSyncIfNeeded();

    // _loadLocalData();

    // if (widget.recording.remoteId != null) {
    //   _syncFromCloud(silent: true);
    // }
  }

  Future<void> _autoSyncIfNeeded() async {
    final recording = await isar.recordings.get(widget.recording.id);
    if (recording == null || recording.remoteId == null) return;

    // データが不完全、または古い場合は同期を実行
    // 例: 文字起こしがない、または最終同期から時間が経っているなど
    // とりあえず毎回最新を確認する
    print("バックグラウンド同期を開始...");
    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();
      if (token != null) {
        await _repository.syncTranscriptionAndSummary(recording, token);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('最新データを取得しました'), duration: Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      print("バックグラウンド同期失敗 (無視可): $e");
    }
  }

  // 手動同期アクション
  Future<void> _manualSync() async {
    setState(() => _isProcessing = true);
    final recording = await isar.recordings.get(widget.recording.id);
    if (recording != null) {
      try {
          final tokenService = GetIdtokenService();
          final token = await tokenService.getIdtoken();
          if (token == null) throw Exception("ログインが必要です");
          
          await _repository.syncTranscriptionAndSummary(recording, token);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同期完了')));
          }
      } catch (e) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同期エラー: $e')));
          }
      }
    }
    setState(() => _isProcessing = false);
  }


  // void _loadLocalData() {
  //   setState(() {
  //     final summary = widget.recording.summary;
  //     final transcription = widget.recording.transcription;
  //     if (summary != null && summary.isNotEmpty) {
  //       // 要約がある場合
  //       _summaryText = summary;
  //     } else {
  //       _summaryText = "まだ要約がありません";
  //       // TODO : 要約同期処理
  //     }
  //     if (transcription != null && transcription.isNotEmpty){
  //       _transcriptionText = transcription;
  //     } else {
  //       _transcriptionText = "まだ文字起こしがありません";
  //       // TODO : 文字起こし同期処理
  //     }
  //     _displayText = _transcriptionText;
  //   });
  // }

  // // クラウドからデータ取得
  // Future<void> _syncFromCloud({bool silent = false}) async {
  //   if (widget.recording.remoteId == null) return;

  //   if (!silent) setState(() => _isLoading = true);

  //   try {
  //     final tokenService = GetIdtokenService();
  //     final token = await tokenService.getIdtoken();

  //     if (token == null) {
  //       if (!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ログインが必要です')));
  //       return;
  //     }

  //     // リポジトリ経由で同期実行
  //     // リポジトリ内でIsarへの保存(put)が行われる
  //     await _repository.syncTranscriptionAndSummary(widget.recording, token);

  //     // 成功したら画面のテキストを更新
  //     _loadLocalData();

  //     if (!silent) {
  //       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('クラウドと同期しました')));
  //     }
  //   } catch (e) {
  //     print("同期エラー: $e");
  //     // silent実行時はユーザーにエラーを見せない（または控えめに表示）
  //     if (!silent) {
  //       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同期失敗: まだ処理中かもしれません')));
  //     }
  //   } finally {
  //     if (!silent) setState(() => _isLoading = false);
  //   }
  // }

  Future<void> _runGeminiTask(Function task) async {
    setState(() => _isLoading = true);
    final result = await task();
    setState(() {
      _transcriptionText = result;
      _isLoading = false;
    });
  }

Future<void> s3Upload(String title) async {
  // ファイルパスの取得（TODO: 念のため空チェックいれる）
  final file = File(widget.recording.filePath);

  // トークンの取得処理
  try {
    final tokenService = GetIdtokenService();
    final token = await tokenService.getIdtoken();

    // トークンがない場合（未ログインなど）はここで終了
    if (token == null) {
      print("トークンが取得できませんでした（未ログイン）");
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインが必要です')),
      );
      return;
    }

    print("トークン取得成功: ${token.substring(0, 10)}...");

    // アップロード処理
    final uploadService = S3UploadService();

    String? existingId = widget.recording.remoteId;
    
    // アップロード実行
    final result = await uploadService.uploadAudioFile(
      file, 
      title,
      idToken: token,
      recordingId: existingId,
    );

    // 成功時の処理
    final recordingId = result['recording_id'];
    final s3Key = result['s3_key'];
    
    print("保存完了！ ID: $recordingId");

    if (widget.recording.remoteId == null){
      await isar.writeTxn(() async {
      widget.recording.remoteId = recordingId;
      await isar.recordings.put(widget.recording);
    });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('アップロード完了 (ID: $recordingId)')),
    );

  } catch (e) {
    // エラーハンドリング
    print("アップロード失敗: $e");
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('エラーが発生しました: $e')),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Recording?>
      (stream: _recordingStream, 
      builder: (context, snapshot){
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting){
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final recording = snapshot.data;
        if (recording == null) {
          return const Scaffold(body: Center(child: Text('データが見つかりません')));
        }

        // 表示するテキストの決定
        String displayText;
        if (_currentMode == DisplayMode.summary){
          displayText = (recording.summary != null && recording.summary!.isNotEmpty) 
            ? recording.summary!
            : "要約はまだありません (同期中または生成待ち)";
        }else {
          displayText = (recording.transcription != null && recording.transcription!.isNotEmpty)
              ? recording.transcription!
              : "文字起こしはまだありません (同期中または生成待ち)";
        }
        final String shareContent = "【要約】\n${_summaryText ?? 'なし'}\n\n【全文】\n${_transcriptionText ?? 'なし'}";
        return Scaffold(
      appBar: AppBar(
        // タイトルを受け取ったデータの日付などにする
        title: Text(widget.recording.title),
        actions: [
          // クラウドと同期
          if (widget.recording.remoteId != null)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'クラウドから結果を取得',
              onPressed: _isProcessing ? null : () => _manualSync(),
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShareScreen(textContent: shareContent),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ファイル情報の表示（デバッグ用にも便利）
            Text("ファイルパス: ${widget.recording.filePath}", 
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    // onPressed: _isLoading ? null : () {
                    //   setState(() {
                    //     _displayText = _transcriptionText;
                    //   });
                    // },

                    onPressed: () => setState(() => _currentMode = DisplayMode.transcription),
                    style: ElevatedButton.styleFrom(
                          backgroundColor: _currentMode == DisplayMode.transcription ? Colors.blue[100] : null,
                        ),

                    icon: const Icon(Icons.mic),
                    label: const Text('文字起こし'),
                  ),
                  const SizedBox(width: 10),
                  
                  ElevatedButton.icon(

                    // onPressed: _isLoading ? null : () {
                    //   setState(() {
                    //     _displayText = _summaryText;
                    //   });
                    // },

                    onPressed: () => setState(() => _currentMode = DisplayMode.summary),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _currentMode == DisplayMode.summary ? Colors.blue[100] : null,
                        ),

                    icon: const Icon(Icons.summarize),
                    label: const Text('要約'),
                  ),
                  const SizedBox(width: 10),

                  // ---------------------------
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => s3Upload(widget.recording.title),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent, // 目立つように色を変更
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('S3 Upload (テスト)'),
                  ),
                  const SizedBox(width: 10),
                  // ---------------------------

                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _runGeminiTask(
                      () => _geminiService.translateText(_displayText)
                    ),
                    icon: const Icon(Icons.translate),
                    label: const Text('英語へ翻訳'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(displayText),
                    ),
                  ),
            ),
          ],
        ),
      ),
      );
      },
    );
  }
}