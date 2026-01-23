import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:voice_app/repositories/recording_repository.dart';
import 'package:voice_app/utils/network_utils.dart';
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
  bool _isUploading = false;
  String _uploadStatusText = 'アップロード';

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

    final bool isConnected = await InternetConnection().hasInternetAccess;
    if (!isConnected) {
      print("オフラインのため自動同期をスキップします。ローカルデータを表示します。");
      return;
    }

    if (!mounted) return;

    await runWithNetworkCheck(context: context, action: () async {
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
    });
  }

  // 手動同期アクション
  Future<void> _manualSync() async {
    runWithNetworkCheck(
      context: context, 
      action: () async {
        setState(() => _isProcessing = true);
        try {
          final recording = await isar.recordings.get(widget.recording.id);
          if (recording != null) {
            final tokenService = GetIdtokenService();
            final token = await tokenService.getIdtoken();
            if (token == null) throw Exception("ログインが必要です");

            await _repository.syncTranscriptionAndSummary(recording, token);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同期完了')));
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同期エラー: $e')));
          }
        } finally {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      }
    );
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
    if (_isUploading) return;
    runWithNetworkCheck(
      context: context, 
      action: () async {
        setState(() {
          _isUploading = true;
          _uploadStatusText = 'アップロード中...';
        });

        // トークンの取得処理
        try {
          final file = File(widget.recording.filePath);
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

          print("アップロード完了。AI処理待ち開始");

          await _pollForUpdates(recordingId);

        } catch (e) {
          // エラーハンドリング
          // print("アップロード失敗: $e");
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('エラーが発生しました: $e')),
          );
        } finally {
          if (mounted) {
            setState(() {
              // _isLoading = false;
              _isUploading = false;
              _uploadStatusText = 'アップロード';
            });
          }
        }
      });
  }

  Future<void> _pollForUpdates(String recordingId) async {
    setState(() {
      _uploadStatusText = '処理中...';
    });

    const int maxAttempts = 30;
    const Duration interval = Duration(seconds: 5);

    for (int i = 0; i < maxAttempts; i++){
      try {
        print("ポーリング試行: ${i + 1}/$maxAttempts");

        final tokenService = GetIdtokenService();
        final token = await tokenService.getIdtoken();

        // isarから最新を取得
        final latestRecording = await isar.recordings.get(widget.recording.id);

        if (token != null && latestRecording != null) {
          await _repository.syncTranscriptionAndSummary(latestRecording, token);

          // データが入ったかチェック
          final checkRecording = await isar.recordings.get(widget.recording.id);

          if (checkRecording != null && checkRecording.transcripts.isNotEmpty) {
            print("文字起こしデータ受信完了");
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文字起こしが完了しました！')),
            );

            setState(() {
              _currentMode = DisplayMode.transcription;
            });

            return;
          }
        }
      } catch (e) {
        print('ポーリング中のエラー(続行): $e');
      }
      await Future.delayed(interval);
    }
    // 回数切れ
    if (mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('処理に時間がかかっています。後ほど「最新情報を確認」ボタンを押してください。')),
      );
    }

  }

  Widget _buildTranscriptionList(Recording recording) {
    final segments = recording.transcripts.toList();
    segments.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    if (segments.isEmpty) {
      if (recording.remoteId != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text(
                "クラウドで処理中、または同期中です...",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _manualSync,
                icon: const Icon(Icons.refresh),
                label: const Text("最新情報を確認"),
              ),
            ],
          ),
        );
      }

      if (recording.transcription != null && recording.transcription!.isNotEmpty){
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(recording.transcription!),
        );
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size:48, color:Colors.grey),
            const SizedBox(height: 16),
            const Text("文字起こしデータがありません"),
            const SizedBox(height: 8),
            const Text("アップロードしてください", style:TextStyle(fontSize: 12, color:Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: segments.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, index) {
        final segment = segments[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal:4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 話者ラベル
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                child: Text(
                  segment.speaker,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color:Colors.grey,
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segment.text, // 原文
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                    // 翻訳がある場合はここに表示する拡張も可能
                    if (segment.translations != null && segment.translations!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          segment.translations!.first.text ?? "",
                          style: const TextStyle(color: Colors.blueGrey),
                        ),
                      ),
                  ],
                ),
              ),
              
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryView(Recording recording) {
    final text = (recording.summary != null && recording.summary!.isNotEmpty) 
            ? recording.summary!
            : "要約はまだありません (同期中または生成待ち)";
            
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
           color: Colors.orange.withOpacity(0.05), // 要約だとわかるように背景色を少し変える
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
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

        // // 表示するテキストの決定
        // String displayText;
        // if (_currentMode == DisplayMode.summary){
        //   displayText = (recording.summary != null && recording.summary!.isNotEmpty) 
        //     ? recording.summary!
        //     : "要約はまだありません (同期中または生成待ち)";
        // }else {
        //   displayText = (recording.transcription != null && recording.transcription!.isNotEmpty)
        //       ? recording.transcription!
        //       : "文字起こしはまだありません (同期中または生成待ち)";
        // }
        final String currentSummary = recording.summary ?? "なし";
        final String currentTrans = recording.transcripts.map((e) => "${e.speaker}: ${e.text}").join("\n");
        final String shareContent = "【要約】\n$currentSummary\n\n【全文】\n$currentTrans";

        _displayText = _currentMode == DisplayMode.summary ? currentSummary : currentTrans;
        return Scaffold(
          appBar: AppBar(
          // タイトルを受け取ったデータの日付などにする
          title: Row(
            children: [
              Tooltip(
                message: recording.remoteId != null
                  ? 'クラウドに保存済み'
                  : '未アップロード(ローカルのみ)',
                child: Icon(
                  recording.remoteId != null
                    ? Icons.cloud_done
                    : Icons.cloud_off,
                  color:recording.remoteId != null
                    ? Colors.green
                    : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),

              // タイトル
              Expanded(
                child: Text(
                  recording.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
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

                    onPressed: () { 
                      setState(() => _currentMode = DisplayMode.transcription);
                      if (recording.transcripts.isEmpty && recording.remoteId != null){
                        _manualSync();
                      }
                    },
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
                    onPressed: (_isLoading || _isUploading) ? null : () => s3Upload(widget.recording.title),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent, // 目立つように色を変更
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.orangeAccent.withOpacity(0.6),
                      disabledForegroundColor: Colors.white,
                    ),
                    icon: _isUploading
                      ? const SizedBox(
                        width: 20, 
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.cloud_upload),
                    label: Text(_uploadStatusText),
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
                : _currentMode == DisplayMode.summary
                  ? _buildSummaryView(recording)
                  :_buildTranscriptionList(recording)
                // : Container(
                //     width: double.infinity,
                //     padding: const EdgeInsets.all(8),
                //     decoration: BoxDecoration(
                //       border: Border.all(color: Colors.grey),
                //       borderRadius: BorderRadius.circular(8),
                //     ),
                //     child: SingleChildScrollView(
                //       child: Text(displayText),
                //     ),
                //   ),
            ),
          ],
        ),
      ),
      );
      },
    );
  }
}