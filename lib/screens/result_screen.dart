import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart'; // HEAD由来
import 'package:isar/isar.dart';
import 'dart:io';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// Main由来
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:voice_app/models/transcript_segment.dart';
import 'package:voice_app/repositories/recording_repository.dart';
import 'package:voice_app/services/processing_service.dart';
import 'package:voice_app/services/s3download_service.dart';
import 'package:voice_app/services/user_service.dart';
import 'package:voice_app/utils/network_utils.dart';
import 'package:voice_app/widgets/estimated_progress_bar.dart';
import 'package:voice_app/widgets/transcription_skelton.dart';
import '../services/gemini_service.dart';
import '../models/recording.dart';
import 'share_screen.dart';
import '../services/s3upload_service.dart';
import '../services/get_idtoken_service.dart';
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

  // 再生スクロールのためのコントローラー
  // final ScrollController _scrollController = ScrollController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
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
  final Map<String, String> _supportedLanguages = {
    'ja': '日本語',
    'en': '英語',
    'zh': '中国語(简体)',
    'zh-TW' : '中国語(繁體)',
    'ko': '韓国語',
    'es': 'スペイン語',
    'fr': 'フランス語',
    'de': 'ドイツ語',
  };
  bool _isUploading = false;
  String _uploadStatusText = '保存';

  String _currentDisplayLanguage = 'original';

  int? _editingIndex;
  final TextEditingController _editController = TextEditingController();

  bool _isEditingSummary = false;
  final TextEditingController _summaryController = TextEditingController();

  final Map<int, String> _segmentLanguageOverrides = {};

  bool _isUserScrolling = false;
  Timer? _scrollResumeTimer;
  int _lastAutoScrolledIndex = -1;

  String? _currentUserId;

  String _getLanguageName(String? code) {
    if (code == null || code.isEmpty) return '原文';
    return _supportedLanguages[code] ?? code; // マップになければコードをそのまま表示
  }

  @override
  void initState() {
    super.initState();
    final isar = Isar.getInstance(); // main.dart等で確保されている前提
    if (isar != null) {
      final dio = Dio();
      _repository = RecordingRepository(isar: isar, dio: dio);
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

    // userId取得
    _fetchCurrentUserId();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _editController.dispose();
    _summaryController.dispose();
    // _scrollController.dispose();
    _scrollResumeTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchCurrentUserId() async {
    try {
      final userId = await UserService().getCurrentUserSub(); 
      
      if (mounted) {
        setState(() {
          _currentUserId = userId;
        });
      }
    } catch (e) {
      print("ユーザーID取得エラー: $e");
    }
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

  bool get _isOwner {
    if (widget.recording.remoteId == null) return true;
    return _currentUserId != null && widget.recording.sourceOriginalId == null;
  }

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

  List<TranscriptSegment> _cachedSegments = [];

  void _prepareSegments() {
    if (_cachedSegments.isEmpty) {
      final list = widget.recording.transcripts.toList();
      list.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
      _cachedSegments = list;
    }
  }

  void _setupAudioListeners() {
    _prepareSegments();
    _audioPlayer.positionStream.listen((p) {
        // --- ここから追加したスクロール命令 ---
        if (!mounted) return;
        if (_currentMode != DisplayMode.transcription) return;
        if (!_isUserScrolling){
          final ms = p.inMilliseconds;
          if (_cachedSegments.isEmpty) _prepareSegments();
          // final segments = widget.recording.transcripts.toList();
          // segments.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));

          int activeIndex = _cachedSegments.lastIndexWhere((s) => ms >= s.startTimeMs);

          // if (activeIndex != -1 && _scrollController.hasClients) {
          // if (activeIndex != -1 && activeIndex != _lastAutoScrolledIndex) {
          //   if (_scrollController.hasClients) {
          //     _scrollController.animateTo(
          //       activeIndex * 120.0, 
          //       duration: const Duration(milliseconds: 300),
          //       curve: Curves.easeInOut,
          //     );

          if (ms > 100000 && ms < 105000) {
            print("⏱️ Time: $ms ms | Index: $activeIndex (前回: $_lastAutoScrolledIndex)");
            if (activeIndex != -1) {
              print("   Target: ${_cachedSegments[activeIndex].text}");
            }
          }

            if (activeIndex != -1 && activeIndex != _lastAutoScrolledIndex) {
              
              
              if (_itemScrollController.isAttached) {
                try {
                  _itemScrollController.scrollTo(
                    index: activeIndex,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: 0.1, 
                  );
                  _lastAutoScrolledIndex = activeIndex;
                } catch (e) {
                  print("❌ スクロールエラー: $e");
                }
            } else {
              // デタッチされている場合は、無理に実行せず、ログも出さない（あるいは1回だけ出す）
              // print("⚠️ Controllerがデタッチされています - スキップ");
            }
          }
        }
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
//＝＝＝＝＝＝ いったん追加しました＝＝＝＝＝＝＝＝＝
  Future<void> _playFromTimestamp(int startTimeMs) async {
    try {
      await _audioPlayer.seek(Duration(milliseconds: startTimeMs));
      _audioPlayer.play();
    } catch (e) {
      print("シーク再生エラー: $e");
    }
  }
// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
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

    if (widget.recording.needsCloudUpdate) {
      print("ローカル変更が未送信のため、アップロードを試みます");
      _manualSync();
      return;
    }

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

            // アップロード処理
            // ローカルに変更がある場合のみ実行
            if (recording.needsCloudUpdate) {
              print("ローカルの変更をクラウドへアップロード中...");
              // クラウド更新
              await _repository.updateRecording(recording, token, syncTranscripts: true);
              await isar.writeTxn(() async {
                recording.needsCloudUpdate = false;
                await isar.recordings.put(recording);
              });
              print("アップロード完了");
            }


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
            setState(() => _isProcessing = false);
          }
        }
      }
    );
  }

  Future<void> _startBackgroundUpload() async {
    if (_isUploading) return;
    setState(() {
      _isUploading = true; 
    });

    try {
      final isar = Isar.getInstance();
      if (isar != null) {
        // サービス経由で開始（待機しない）
        ProcessingService().startUploadAndProcessing(
          widget.recording, 
          isar, 
          _repository
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('解析を開始しました。一覧画面に戻っても処理は続きます。')),
        );

        // 即座に一覧に戻る場合
        // Navigator.pop(context); 
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('開始エラー: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false; // ボタンのローディングは解除
        });
      }
    }
  }

// Future<void> s3Upload(String title) async {
//   setState(() {
//     _isUploading = true;
//     _uploadStatusText = '保存中...';
//   });
//   // ファイルパスの取得（TODO: 念のため空チェックいれる）
//   final file = File(widget.recording.filePath);

//   // トークンの取得処理
//   try {
//     final tokenService = GetIdtokenService();
//     final token = await tokenService.getIdtoken();

//           // トークンがない場合（未ログインなど）はここで終了
//           if (token == null) {
//             print("トークンが取得できませんでした（未ログイン）");
            
//             if (!mounted) return;
//             ScaffoldMessenger.of(context).showSnackBar(
//               const SnackBar(content: Text('ログインが必要です')),
//             );
//             return;
//           }

//           print("トークン取得成功: ${token.substring(0, 10)}...");

//           // アップロード処理
//           final uploadService = S3UploadService();

//           String? existingId = widget.recording.remoteId;
          
//           // アップロード実行
//           final result = await uploadService.uploadAudioFile(
//             file, 
//             title,
//             idToken: token,
//             recordingId: existingId,
//           );

//           // 成功時の処理
//           final recordingId = result['recording_id'];
//           final s3Key = result['s3_key'];
          
//           print("保存完了！ ID: $recordingId");

//           await isar.writeTxn(() async {
//             if (widget.recording.remoteId == null){
//               widget.recording.remoteId = recordingId;
//             }
            
//             // s3AudioPath に s3Key (パス) を保存
//             widget.recording.s3AudioUrl = s3Key;

//             await isar.recordings.put(widget.recording);
//           });

//           if (!mounted) return;
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(content: Text('アップロード完了 (ID: $recordingId)')),
//             );

//           print("アップロード完了。AI処理待ち開始");

//           await _pollForUpdates(recordingId);

//         } catch (e) {
//           // エラーハンドリング
//           // print("アップロード失敗: $e");
//           if (!mounted) return;
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(content: Text('エラーが発生しました: $e')),
//           );
//         } finally {
//           if (mounted) {
//             setState(() {
//               // _isLoading = false;
//               _isUploading = false;
//               _uploadStatusText = 'アップロード';
//             });
//           }
//         }
//   }

//   Future<void> _pollForUpdates(String recordingId) async {
//     setState(() {
//       _uploadStatusText = '処理中...';
//     });

//     const int maxAttempts = 30;
//     const Duration interval = Duration(seconds: 5);

//     for (int i = 0; i < maxAttempts; i++){
//       try {
//         print("ポーリング試行: ${i + 1}/$maxAttempts");

//         final tokenService = GetIdtokenService();
//         final token = await tokenService.getIdtoken();

//         // isarから最新を取得
//         final latestRecording = await isar.recordings.get(widget.recording.id);

//         if (token != null && latestRecording != null) {
//           await _repository.syncTranscriptionAndSummary(latestRecording, token);

//           // データが入ったかチェック
//           final checkRecording = await isar.recordings.get(widget.recording.id);

//           if (checkRecording != null && checkRecording.transcripts.isNotEmpty) {
//             print("文字起こしデータ受信完了");
//             if (!mounted) return;

//             ScaffoldMessenger.of(context).showSnackBar(
//               const SnackBar(content: Text('文字起こしが完了しました！')),
//             );

//             setState(() {
//               _currentMode = DisplayMode.transcription;
//             });

//             return;
//           }
//         }
//       } catch (e) {
//         print('ポーリング中のエラー(続行): $e');
//       }
//       await Future.delayed(interval);
//     }
//     // 回数切れ
//     if (mounted){
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('処理に時間がかかっています。後ほど「最新情報を確認」ボタンを押してください。')),
//       );
//     }

//   }

  Future<void> _handleTranslation(String targetLang) async {
    final tokenService = GetIdtokenService();
    final token = await tokenService.getIdtoken();
    if (token == null) return;

    try {
      await _repository.requestTranslation(widget.recording.remoteId!, targetLang, token);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('翻訳を開始しました')),
      );

      await _pollForTranslation(targetLang);
    } catch (e) {
      print('翻訳エラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('翻訳エラー: $e')),
      );
    }
  }

  Future<void> _pollForTranslation(String targetLang, {bool updateGlobalUI = true}) async {
    setState(() {
      // _isTranslating = true;
    });

    const int maxAttempts = 30; 
    const Duration interval = Duration(seconds: 5);

    for (int i = 0; i < maxAttempts; i++) {
      try {
        print("翻訳ポーリング試行: ${i + 1}/$maxAttempts");

        final tokenService = GetIdtokenService();
        final token = await tokenService.getIdtoken();
        
        // 最新データを取得 (ここでIsarのデータがローカルメモリに乗る)
        final latestRecording = await isar.recordings.get(widget.recording.id);

        if (token != null && latestRecording != null) {
          // 同期処理を実行 (S3から最新JSONをダウンロードしてIsarへ)
          await _repository.syncTranscriptionAndSummary(latestRecording, token);

          // 判定ロジック: 対象言語が含まれているかチェック
          // syncTranscriptionAndSummary内でIsar更新済みなので、再度getする必要は本来ないが、
          // 念のためIsarLinkをロードするか、最新の状態を確認
          await latestRecording.transcripts.load();
          
          final hasTranslation = latestRecording.transcripts.any(
            (s) => s.translations?.any((tr) => tr.langCode == targetLang) ?? false
          );
          
          if (hasTranslation) {
            print("翻訳データ受信完了: $targetLang");
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('翻訳が完了しました！')),
            );
            if (updateGlobalUI) {
              setState(() {
                _currentDisplayLanguage = targetLang; // 自動で切り替え
                _currentMode = DisplayMode.transcription;
              });
            }
            
            return; // 終了
          }
        }
      } catch (e) {
        print('翻訳ポーリング中のエラー(続行): $e');
      }
      
      await Future.delayed(interval);
    }

    // タイムアウト
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('翻訳処理に時間がかかっています。しばらくしてから再度確認してください。')),
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
    // final currentText = recording.transcription ?? "";
    // if (currentText.isEmpty) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text('翻訳するテキストがありません')),
    //   );
    //   return;
    // }
    final String originName = _getLanguageName(recording.originalLanguage);

    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('翻訳先の言語を選択'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                _handleTranslationRequest('original', '原文');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('原文 ($originName)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const Divider(),
            ..._supportedLanguages.entries.map((entry) {
              if (entry.key == recording.originalLanguage) {
                return const SizedBox.shrink(); 
              }
              return SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context);
                  _handleTranslationRequest(entry.key, entry.value);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(entry.value, style: const TextStyle(fontSize: 16)),
                )
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _showSegmentTranslationDialog(int index, Recording recording) async {
    final String originName = _getLanguageName(recording.originalLanguage);
    showDialog(
      context: context,
      builder:(context) {
        return SimpleDialog(
          title: const Text('言語を選択'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                _updateSegmentLanguage(index, 'original');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('原文を表示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
              ),
            ),
            const Divider(),
            ..._supportedLanguages.entries.map((entry) {
              if (entry.key == recording.originalLanguage) {
                return const SizedBox.shrink(); 
              }
              return SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context);
                  _updateSegmentLanguage(index, entry.key, langName: entry.value);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(entry.value, style: const TextStyle(fontSize:16)),
                )
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _updateSegmentLanguage(int index, String langCode, {String? langName}) async {
    if (langCode == 'original') {
      setState(() {
        _segmentLanguageOverrides.remove(index);
      });
      return;
    }

    // データがあるかチェック
    await widget.recording.transcripts.load();
    final hasCache = widget.recording.transcripts.any(
      (s) => s.translations?.any((t) => t.langCode == langCode) ?? false
    );

    if (hasCache) {
      setState(() {
        _segmentLanguageOverrides[index] = langCode;
      });
    } else {
      try {
        final token = await GetIdtokenService().getIdtoken();
        if (token == null) return;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${langName ?? langCode} のデータを取得中...')));
        }

        await _repository.requestTranslation(widget.recording.remoteId!, langCode, token);
        await _pollForTranslation(langCode, updateGlobalUI: false);
        if (mounted) {
          setState(() {
            _segmentLanguageOverrides[index] = langCode;
          });
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    }
  }

  Future<void> _handleTranslationRequest(String langCode, String langName) async {
    if (langCode == 'original') {
      setState(() => _currentDisplayLanguage = 'original');
      return;
    }
    
    // すでに翻訳データがあるかチェック
    await widget.recording.transcripts.load();
    final hasCache = widget.recording.transcripts.any(
      (s) => s.translations?.any((t) => t.langCode == langCode) ?? false
    );

    if (hasCache) {
      // すでにある場合は切り替えだけ
      setState(() {
        _currentDisplayLanguage = langCode;
        _currentMode = DisplayMode.transcription;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$langName に切り替えました')));
      return;
    }

    // なければサーバーにリクエスト
    try {
      final token = await GetIdtokenService().getIdtoken();
      if (token == null) return;
      if (widget.recording.remoteId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先にクラウドへ保存してください')));
        return;
      }

      await _repository.requestTranslation(widget.recording.remoteId!, langCode, token);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$langName への翻訳を開始しました...')));
      }

      await _pollForTranslation(langCode);

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('翻訳リクエストエラー: $e')));
    }
  }

  Future<void> _saveTranscriptSegment(int index, TranscriptSegment segment, Recording recording) async {
    final newText = _editController.text;

    // 変更がない場合は終了
    if (newText == segment.text) {
      setState(() {
        _editingIndex = null;
      });
      return;
    }

    setState(() => _isProcessing = true);

    final isar = Isar.getInstance();
    if (isar == null) return;

    // ローカルisarの更新
    await isar.writeTxn(() async {
      segment.text = newText;
      await isar.transcriptSegments.put(segment);
      // 全文も更新
      await recording.transcripts.load();
      final sorted = recording.transcripts.toList()
        ..sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
      recording.transcription = sorted.map((e) => e.text).join("");
      recording.needsCloudUpdate = true;
      await isar.recordings.put(recording);
    });

    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();
      if (token == null) throw Exception('ログインが必要です');
      
      if (token != null && await InternetConnection().hasInternetAccess){
        // クラウド同期
        await _repository.updateRecording(recording, token, syncTranscripts: true);

        await isar.writeTxn(() async {
          recording.needsCloudUpdate = false;
          await isar.recordings.put(recording);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('修正を保存しました')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同期に失敗しました（データは本体に保存済み）')));
        }
      }
    } catch (e) {
      print("保存エラー: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存エラー: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _editingIndex = null;
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _saveSummary(Recording recording) async {
    final newText = _summaryController.text;

    // 変更なしなら閉じる
    if(newText == recording.summary) {
      setState(() {
        _isEditingSummary = false;
      });
      return;
    }

    setState(() => _isProcessing = true);

    final isar = Isar.getInstance();
    if (isar == null) return;

    await isar.writeTxn(() async {
      recording.summary = newText;
      recording.needsCloudUpdate = true;
      await isar.recordings.put(recording);
    });

    try {
      final tokenService = GetIdtokenService();
      final token = await tokenService.getIdtoken();

      if (token == null) throw Exception("ログインが必要です");

      if (token != null && await InternetConnection().hasInternetAccess){

      await _repository.updateRecording(recording, token, syncTranscripts: true);

      await isar.writeTxn(() async {
        recording.needsCloudUpdate = false;
        await isar.recordings.put(recording);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('要約を保存しました')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("オフラインのため、次回起動時にクラウドに同期されます。")));
      }
    }
    } catch (e) {
      print("同期失敗: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同期失敗（ローカルには保存済み）')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEditingSummary = false;
          _isProcessing = false;
        });
      }
    }
  }

  // --- View Builders (Main由来) ---
  Widget _buildTranscriptionList(Recording recording) {
    final segments = recording.transcripts.toList();
    segments.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    if (segments.isEmpty) {
      final status = recording.status;
      // if (recording.remoteId != null) {
        if (status == 'uploading' || status == 'processing'){
          return EstimatedProgressBar(status: status!);
        }
        if (status == 'completed' || status == 'processing'){
          return const TranscriptionSkeleton();
        }

        if (status == 'pending' || status == null || status.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 20),
              Text(
                "文字起こしデータはまだありません",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                "「保存」ボタンを押して\n解析を開始してください",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        );
      }

      if (status == 'failed') {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              SizedBox(height: 16),
              Text("解析に失敗しました", style: TextStyle(color: Colors.red)),
            ],
          ),
        );
      }

      // その他のエラー (デバッグ用にstatusを表示)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("データが表示できません"),
            Text("Status: $status", style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _manualSync,
              icon: const Icon(Icons.refresh),
              label: const Text("再読み込み"),
            ),
          ],
        ),
      );
    }

    final bool isTranslateMode = _currentDisplayLanguage != 'original';

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        // ユーザーが操作開始したとき
        if (notification.direction != ScrollDirection.idle){
          _scrollResumeTimer?.cancel(); // タイマーリセット
          if (!_isUserScrolling) {
            _isUserScrolling = true; // フラグ(自動スクロール停止)
          }
        }
        // ユーザーの操作終了、スクロールが止まった時
        else {
          _scrollResumeTimer?.cancel();
          // 5秒後にフラグオフ、自動スクロール開始
          _scrollResumeTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) {
              // setState(() {
                _isUserScrolling = false;
                _lastAutoScrolledIndex = -1;
              // });
            }
          });
        }
        return false;
      },
      child: ScrollablePositionedList.builder(
        // key: const PageStorageKey('transcription_list'),
        itemScrollController: _itemScrollController, // コントローラーセット
        itemPositionsListener: _itemPositionsListener, // リスナーセット
        itemCount: segments.length,
        padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        itemBuilder: (context, index) {
          final segment = segments[index];
          final isEditing = _editingIndex == index;
          final String effectiveLang = _segmentLanguageOverrides[index] ?? _currentDisplayLanguage;
          final bool isTranslateMode = effectiveLang != 'original';
          String displayText = segment.text;
          bool isCurrentTranslationAvailable = false;
          if (isTranslateMode){
            final translation = segment.translations?.firstWhere(
              (t) => t.langCode == effectiveLang,
              orElse: () => TranslationData(),
            );
            if (translation?.text != null){
              displayText = translation!.text!;
              isCurrentTranslationAvailable = true;
            }
          }
        return Padding(
          key: ValueKey(segment.id),
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 0),
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
                    IconButton(
                      icon: const Icon(
                        Icons.play_arrow_outlined,
                        size: 20,
                        color: Colors.blue,
                      ),
                      // ＝＝＝トップのIconButtonと下部の追加＝＝＝
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      onPressed: () => _playFromTimestamp(segment.startTimeMs),
                    ),
                    // ================================

                    const SizedBox(width: 2),

                    IconButton(
                      icon: Icon(
                        Icons.translate, 
                        size: 18, 
                        // 個別設定が効いている時は色を変えて分かりやすくする
                        color: _segmentLanguageOverrides.containsKey(index) ? Colors.indigo : Colors.grey.shade400
                      ),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      tooltip: "この行を翻訳",
                      onPressed: () => _showSegmentTranslationDialog(index, recording),
                    ),

                    const Spacer(),

                    if(!isEditing && !_isProcessing && !isTranslateMode && _isOwner) 
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _editingIndex = index;
                            _editController.text = segment.text; // 現在のテキストをセット
                          });
                        },
                        child : const Row(
                          children : [
                            Icon(Icons.edit, size: 18, color: Colors.grey),
                            SizedBox(width: 4),
                            Text("編集", style: TextStyle(fontSize: 12, color:Colors.grey)),
                          ],
                        ),
                      ),
                  ],
                  
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isEditing ? Colors.blue : Colors.grey.shade300,
                    width: isEditing ? 2.0 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: isEditing
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TextField(
                        controller: _editController,
                        maxLines: null,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                      const SizedBox(height:8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _editingIndex = null;
                              });
                            }, 
                            child: const Text("キャンセル", style: TextStyle(color: Colors.grey)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _saveTranscriptSegment(index, segment, recording),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical:8),
                            ),
                            child: const Text("保存"),
                          ),
                        ],
                      )
                    ],
                  )
                : Text(
                  displayText,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  Widget _buildSummaryView(Recording recording) {
    final hasSummary = recording.summary != null && recording.summary!.isNotEmpty;
    final displayText = hasSummary ? recording.summary! : "要約はまだありません（同期中または生成待ち）";
    
    final String currentLang = _currentDisplayLanguage;
    final bool isTranslateMode = currentLang != 'original';

    String contentText = "";

    if (isTranslateMode) {
      // 翻訳データを探す
      final translation = recording.summaryTranslations?.firstWhere(
        (t) => t.langCode == currentLang,
        orElse: () => TranslationData(), // 見つからない場合
      );

      if (translation != null && translation.text != null && translation.text!.isNotEmpty) {
        contentText = translation.text!;
      } else {
        // 翻訳データがまだ無い場合（原文フォールバック + 注釈）
        contentText = "${recording.summary ?? '要約なし'}\n\n(※この言語の要約翻訳はまだありません)";
      }
    } else {
      // 原文
      contentText = recording.summary ?? "要約はまだありません（同期中または生成待ち）";
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 編集ボタン（表示モードかつデータがある場合）
          if (_isOwner && !_isEditingSummary && !_isProcessing)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 16),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditingSummary = true;
                    _summaryController.text = recording.summary ?? "";
                  });
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text("要約を編集"),
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(left: 16, right: 16, bottom:16, top:8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isEditingSummary ? Colors.white : Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isEditingSummary ? Colors.blue : Colors.orange.withOpacity(0.2),
                    width: _isEditingSummary ? 2.0 : 1.0,
                  ),
                  boxShadow: _isEditingSummary
                    ? [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
              ),
              child: _isEditingSummary
                ? Column(
                  children: [
                    TextField(
                      controller: _summaryController,
                      maxLines: null,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "要約を入力してください",
                      ),
                      style: const TextStyle(fontSize: 16, height:1.5),
                    ),
                    const SizedBox(height:16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isEditingSummary = false;
                            });
                          }, 
                          child: const Text("キャンセル", style: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _saveSummary(recording),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("保存"),
                        )
                      ],
                    )
                  ],
                )
              : Text(
                contentText,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
        ],
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

        // 追加
        final sortedSegments = recording.transcripts.toList()
          ..sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
        _cachedSegments = sortedSegments;

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
              // テキストが存在するかチェック（リストが空でないか）
              final bool hasText = recording.transcripts.isNotEmpty;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShareScreen(
                    textContent: shareContent,
                    recordingId: recording.remoteId, // null許容のまま渡す
                    filePath: recording.filePath,    // 追加: ファイルパスを渡す
                    hasTranscript: hasText,          // 追加: テキスト有無フラグ
                    isOwner: _isOwner,
                  ),
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
                                // child: Slider(
                                //   min: 0,
                                //   max: _duration.inMilliseconds.toDouble(),
                                //   value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                                //   onChanged: (value) {
                                //     _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                //   },
                                // ),
                                // 自動スクロールがずれるので以下に修正
                                child: StreamBuilder<Duration>(
                                stream: _audioPlayer.positionStream,
                                builder: (context, snapshot) {
                                  final position = snapshot.data ?? Duration.zero;
                                  final currentPos = position.inMilliseconds.toDouble();
                                  final maxDuration = _duration.inMilliseconds.toDouble();
                                  
                                  // スライダーの値がDurationを超えないように安全策
                                  final sliderValue = currentPos.clamp(0.0, maxDuration > 0 ? maxDuration : 0.0);

                                  return Slider(
                                    min: 0,
                                    max: maxDuration > 0 ? maxDuration : 1.0, // 0除算回避
                                    value: sliderValue,
                                    onChanged: (value) {
                                      _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                    },
                                  );
                                }
                              ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Text(_formatDuration(_position)),
                                StreamBuilder<Duration>(
                                  stream: _audioPlayer.positionStream,
                                  builder: (context, snapshot) => Text(_formatDuration(snapshot.data ?? Duration.zero)),
                                ),
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
                    onPressed: (_isLoading || _isUploading) ? null : _startBackgroundUpload,
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
                      label: Text(_currentDisplayLanguage == 'original' ? '翻訳' :'翻訳中'),
                      style: _currentDisplayLanguage != 'original' 
                      ? ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade100) 
                      : null,
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