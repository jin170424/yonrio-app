import 'dart:async';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class NetworkService {
  // どこから読んでも同じインスタンスを使用する
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final _connectionChecker = InternetConnection();
  StreamSubscription<InternetStatus>? _subscription;

  // 接続状況を通知するハンドラー
  final StreamController<InternetStatus> _statusController = StreamController<InternetStatus>.broadcast();

  // 外部から現在の状態をlistenするstream
  Stream<InternetStatus> get onStatusChange => _statusController.stream;

  // 監視
  void initialize() {
    _subscription = _connectionChecker.onStatusChange.listen((status) {
      _statusController.add(status);
    });
  }

  // 監視終了(アプリ終了時など)
  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}