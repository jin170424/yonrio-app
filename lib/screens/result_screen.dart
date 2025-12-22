import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../models/recording.dart'; // モデルをインポート
import 'share_screen.dart';
import 'package:audioplayers/audioplayers.dart';

class ResultScreen extends StatefulWidget {
  // 親(Home)からデータを受け取るための変数
  final Recording recording;

  const ResultScreen({super.key, required this.recording});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final GeminiService _geminiService = GeminiService();

  // 音声再生用フィールド
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  String _displayText = "（文字起こしボタンを押してください）";
  bool _isLoading = false;

  Future<void> _runGeminiTask(Function task) async {
    setState(() => _isLoading = true);
    final result = await task();
    setState(() {
      _displayText = result;
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    // 再生時間・位置の更新を監視
    _player.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });

    // 再生完了時の処理（UI更新）
    try {
      _player.onPlayerComplete.listen((_) {
        setState(() {
          _isPlaying = false;
          _position = _duration;
        });
      });
    } catch (_) {
      // プラットフォームによってはイベントがない場合があるので安全に無視
    }
  }

  Future<void> _startPlayback() async {
    try {
      await _player.play(DeviceFileSource(widget.recording.filePath));
      setState(() => _isPlaying = true);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('再生に失敗しました: $e')),
        );
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final twoDigits = (int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // タイトルを受け取ったデータの日付などにする
        title: Text(widget.recording.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShareScreen(textContent: _displayText),
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
                    onPressed: _isLoading
                        ? null
                        : () => _runGeminiTask(() => _geminiService
                            .transcribeAudio(widget.recording.filePath)),
                    icon: const Icon(Icons.mic),
                    label: const Text('文字起こし'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _runGeminiTask(
                            () => _geminiService.summarizeText(_displayText)),
                    icon: const Icon(Icons.summarize),
                    label: const Text('要約'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _runGeminiTask(
                            () => _geminiService.translateText(_displayText)),
                    icon: const Icon(Icons.translate),
                    label: const Text('英語へ翻訳'),
                  ),
                ],
              ),
            ),
            // ==========================================
            // 4. 音声コントロールパネル
            // ==========================================
            const SizedBox(height: 20),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () async {
                    if (_isPlaying) {
                      await _player.pause();
                      setState(() => _isPlaying = false);
                    } else {
                      // まだソースが読み込まれていない場合は play でファイルを指定して再生
                      try {
                        if (_duration == Duration.zero) {
                          await _player.play(
                              DeviceFileSource(widget.recording.filePath));
                        } else {
                          await _player.resume();
                        }
                        setState(() => _isPlaying = true);
                      } catch (e) {
                        debugPrint('再生に失敗しました: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('再生に失敗しました: $e')),
                        );
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: () async {
                    await _player.stop();
                    setState(() => _isPlaying = false);
                  },
                ),
                Expanded(
                  child: Slider(
                    value: _position.inMilliseconds.toDouble(),
                    min: 0,
                    max: _duration.inMilliseconds > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1,
                    onChanged: (value) async {
                      final newPos = Duration(milliseconds: value.toInt());
                      // Duration がまだ 0 のとき（ソース未ロード）に seek を呼ぶと例外になる可能性がある
                      if (_duration == Duration.zero) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('音声が読み込まれていません')),
                        );
                        return;
                      }
                      try {
                        await _player.seek(newPos);
                      } catch (e) {
                        debugPrint('seek に失敗しました: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('位置移動に失敗しました: $e')),
                        );
                      }
                    },
                  ),
                ),
                Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),

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
                        child: Text(_displayText),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
