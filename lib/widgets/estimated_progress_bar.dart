import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class EstimatedProgressBar extends StatefulWidget {
  final String status; // 'uploading' または 'processing'

  const EstimatedProgressBar({super.key, required this.status});

  @override
  State<EstimatedProgressBar> createState() => _EstimatedProgressBarState();
}

class _EstimatedProgressBarState extends State<EstimatedProgressBar> {
  double _progress = 0.0;
  Timer? _timer;
  String _message = "準備中...";

  @override
  void initState() {
    super.initState();
    _startFakeProgress();
  }

  @override
  void didUpdateWidget(covariant EstimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) {
      _startFakeProgress();
    }
  }

  void _startFakeProgress() {
    _timer?.cancel();
    
    if (widget.status == 'uploading') {
      _progress = 0.0;
      _message = "クラウドにアップロード中...";
      // アップロードは早めに進める
      _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) return;
        setState(() {
          if (_progress < 0.8) {
            _progress += 0.03;
          }
        });
      });
    } else {
      // processing (解析中)
      _progress = 0.0;
      if (_progress < 0.3) _progress = 0.3; // 最低でも30%からスタート
      _message = "文字起こし中...";
      
      // じわじわ進めて95%で止める
      _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (!mounted) return;
        setState(() {
          if (_progress < 0.95) {
            _progress += 0.005; 
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String lottieFile = widget.status == 'uploading'
        ? 'assets/animations/cloud_upload.json' // アップロード用素材
        : 'assets/animations/ai_processing.json'; // AI解析用素材
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
              SizedBox(
              height: 120,
              child: Lottie.asset(
                lottieFile,
                fit: BoxFit.contain,
                // ファイルがない時のエラー回避（開発中用）
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.psychology, size: 80, color: Colors.blueAccent);
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 10),
            Text(
              "${(_progress * 100).toInt()}%",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}