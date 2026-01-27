import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart'; // HEAD由来
import 'package:isar/isar.dart';
import 'dart:io';

// Main由来
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:voice_app/repositories/recording_repository.dart';
import 'package:voice_app/services/s3download_service.dart';
import 'package:voice_app/utils/network_utils.dart';
import '../services/gemini_service.dart';
import '../models/recording.dart';
import 'share_screen.dart';
import '../services/s3upload_service.dart';
import '../services/get_idtoken_service.dart';
import '../services/s3download_service.dart';
import '../main.dart'; // isarインスタンス取得用

enum DisplayMode { transcription, summary }

class ResultScreen extends StatefulWidget {
  final Recording recording;

  const ResultScreen({super.key, required this.recording});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();
  late final RecordingRepository _repository;

  // Stream & UI State (Main由来)
  Stream<Recording?>? _recordingStream;
  DisplayMode _currentMode = DisplayMode.transcription;
  bool _isProcessing = false;
  bool _isLoading = false;
  String _displayText = "";

  // Audio Player & Image State (HEAD由来)
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isImage = false;
  
  // 翻訳用言語マップ (HEAD由来)
  final Map<String, String> _targetLanguages = {
    '英語': 'English',
    '中国語': 'Simplified Chinese',
    '韓国語': 'Korean',
    'スペイン語': 'Spanish',
    'フランス語': 'French',
    'ドイツ語': 'German',
  };
  bool _isUploading = false;
  String _uploadStatusText = '保存';

  @override
  void initState() {
    super.initState();
    final isar = Isar.getInstance(); // main.dart等で確保されている前提
    if (isar != null) {
      _repository = RecordingRepository(isar);
      // ストリームセットアップ
      _recordingStream = isar.recordings.watchObject(widget.recording.id, fireImmediately: true);
    }
    
    // 画像判定 (HEAD由来)
    final path = widget.recording.filePath.toLowerCase();
    _isImage = path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');

    // プレイヤー初期化 (HEAD由来)
    if (!_isImage) {
      _initAudioPlayer();
    }

    // 自動同期 (Main由来)
    _autoSyncIfNeeded();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- Audio Player Logic (HEAD由来) ---
  // Future<void> _initAudioPlayer() async {
  //   try {
  //     if (await File(widget.recording.filePath).exists()) {
  //       _audioPlayer.positionStream.listen((p) {
  //         if (mounted) setState(() => _position = p);
  //       });
  //       _audioPlayer.durationStream.listen((d) {
  //         if (mounted) setState(() => _duration = d ?? Duration.zero);
  //       });
  //       _audioPlayer.playerStateStream.listen((state) {
  //         if (mounted) {
  //           setState(() {
  //             _isPlaying = state.playing;
  //           });
  //           if (state.processingState == ProcessingState.completed) {
  //             _audioPlayer.seek(Duration.zero);
  //             _audioPlayer.pause();
  //           }
  //         }
  //       });
  //       await _audioPlayer.setFilePath(widget.recording.filePath);
  //     }
  //   } catch (e) {
  //     print("オーディオ読み込みエラー: $e");
  //   }
  // }

  Future<void> _initAudioPlayer() async {
    try {
      final localFile = File(widget.recording.filePath);
      final bool localExists = await localFile.exists();

      if (localExists) {
        print("ローカル再生: ${widget.recording.filePath}");
        _setupAudioListeners();
        await _audioPlayer.setFilePath(widget.recording.filePath);
      }
      // ローカルなし、s3情報アリ
      else if (widget.recording.s3AudioUrl != null && widget.recording.s3AudioUrl!.isNotEmpty) {
        print("ローカルファイルが見つかりません。S3から再生します。");
        // ロード中の画面表示してもOK ↓
        // SetState(() => _isLoading = true);

        final tokenService = GetIdtokenService();
        final token = await tokenService.getIdtoken();

        if (token != null) {
          final downloadService = S3DownloadService();
          final presignedUrl = await downloadService.getPresignedUrl(
            widget.recording.s3AudioUrl!,
            token
          );

          if (presignedUrl != null) {
            print("署名付きURL取得成功: $presignedUrl");

            _setupAudioListeners();

            await _audioPlayer.setUrl(presignedUrl);
          } else {
            print("署名付きURLの取得に失敗しました");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("音声ファイルのURL取得に失敗しました")),
              );
            }
          }
        } else {
          print("トークン取得失敗");
        }
      } else {
        print("再生可能な音声がありません");
      }
    } catch (e) {
      print("オーディオ読み込みエラー: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('再生エラー: $e')),
        );
      }
    }
  }

  void _setupAudioListeners() {
    _audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _position = p); 
    });
    _audioPlayer.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
        if (state.processingState == ProcessingState.completed) {
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.pause();
        }
      }
    });
  }

  void _togglePlay() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // --- Sync Logic (Main由来) ---
  Future<void> _autoSyncIfNeeded() async {
    final isar = Isar.getInstance();
    if (isar == null) return;
    
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

  // Future<void> _runGeminiTask(Function task) async {
  //   setState(() => _isLoading = true);
  //   final result = await task();
  //   setState(() {
  //     _transcriptionText = result;
  //     _isLoading = false;
  //   });
  // }

Future<void> s3Upload(String title) async {
  setState(() {
    _isUploading = true;
    _uploadStatusText = '保存中...';
  });
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

          await isar.writeTxn(() async {
            if (widget.recording.remoteId == null){
              widget.recording.remoteId = recordingId;
            }
            
            // s3AudioPath に s3Key (パス) を保存
            widget.recording.s3AudioUrl = s3Key;

            await isar.recordings.put(widget.recording);
          });

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

  // --- Gemini / Translation Logic (HEAD & Main統合) ---
  Future<void> _runGeminiTask(Future<String> Function() task, Recording recording) async {
    setState(() => _isLoading = true);
    try {
      final result = await task();
      
      // 結果を保存
      final isar = Isar.getInstance();
      if (isar != null) {
        await isar.writeTxn(() async {
          // ※簡易的にtranscriptionに入れる（本来はリスト構造への変換が望ましいが、一旦文字列として保存）
          recording.transcription = result;
          await isar.recordings.put(recording);
        });
      }
    } catch (e) {
      print("Geminiエラー: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("エラー: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showTranslationDialog(Recording recording) async {
    final currentText = recording.transcription ?? "";
    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('翻訳するテキストがありません')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('翻訳先の言語を選択'),
          children: _targetLanguages.entries.map((entry) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                _runGeminiTask(
                  () => _geminiService.translateText(
                    currentText, 
                    targetLang: entry.value,
                  ),
                  recording
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(entry.key, style: const TextStyle(fontSize: 16)),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // --- View Builders (Main由来) ---
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
      padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      itemBuilder: (context, index) {
        final segment = segments[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                child: Row(
                  children: [
                    Text(
                      segment.speaker,
                      style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color:Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),


                    // ======= 再生同期ボタン ==========
                    const Icon(
                      Icons.play_arrow_outlined,
                      size: 20,
                      color: Colors.blue,
                    ),
                    // ================================
                  ],
                  
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
                child: Text(
                  segment.text,
                  style: const TextStyle(fontSize: 15, height: 1.4),
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
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
           color: Colors.orange.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // MainのStreamBuilder構造を採用
    return StreamBuilder<Recording?>(
      stream: _recordingStream, 
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
          if (recording.remoteId != null)
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
      body: Column(
        children: [
              // 1. プレイヤー / 画像表示エリア (HEADのデザインを採用)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade50),
                child: _isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(recording.filePath),
                          height: 200,
                          fit: BoxFit.contain,
                          errorBuilder: (c, o, s) => const SizedBox(height:100, child: Center(child: Icon(Icons.broken_image))),
                        ),
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                iconSize: 40,
                                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                                color: Colors.blue,
                                onPressed: _togglePlay,
                              ),
                              Expanded(
                                child: Slider(
                                  min: 0,
                                  max: _duration.inMilliseconds.toDouble(),
                                  value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                                  onChanged: (value) {
                                    _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                  },
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(_position)),
                                Text(_formatDuration(_duration)),
                              ],
                            ),
                          ),
                        ],
                    ),
              ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _currentMode = DisplayMode.transcription),
                    style: ElevatedButton.styleFrom(
                          backgroundColor: _currentMode == DisplayMode.transcription ? Colors.blue[100] : null,
                        ),

                    icon: const Icon(Icons.description),
                    label: const Text('文字起こし'),
                  ),
                  const SizedBox(width: 10),
                  
                  ElevatedButton.icon(
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
                    onPressed: (_isLoading || _isUploading) ? null : () => s3Upload(recording.title),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent, // 目立つように色を変更
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.orangeAccent.withOpacity(0.6),
                      disabledForegroundColor: Colors.white,
                    ),
                    icon:  _isUploading
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

                    // 翻訳 (HEADの機能)
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _showTranslationDialog(recording),
                      icon: const Icon(Icons.translate),
                      label: const Text('翻訳'),
                    ),
                    
                    // ローカル処理 (HEADの機能: 必要な場合)
                    if (_isImage)
                       Padding(
                         padding: const EdgeInsets.only(left: 10),
                         child: IconButton(
                           icon: const Icon(Icons.refresh), 
                           tooltip: "再解析",
                           onPressed: () => _runGeminiTask(() => _geminiService.transcribeImage(File(recording.filePath)), recording),
                         ),
                       ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 3. コンテンツ表示エリア (Mainのロジックを採用)
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : _currentMode == DisplayMode.summary
                    ? _buildSummaryView(recording)
                    : _buildTranscriptionList(recording),
              ),
            ],
          ),
        );
      },
    );
  }
}