/// エスケープ用カウントダウンタイマー
///
/// ステルス操作のキャンセル猶予時間を管理する。
/// UIはStreamでリアルタイムに残り秒数を受け取れる。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// カウントダウンタイマー（エスケープ用）
///
/// 使い方:
/// ```dart
/// final timer = ref.read(escapeTimerProvider);
///
/// // タイマー開始（10秒後にonCompleteが呼ばれる）
/// timer.start(
///   seconds: 10,
///   onComplete: () => print('時間切れ'),
/// );
///
/// // UIでStreamをリッスン
/// StreamBuilder<int>(
///   stream: timer.remainingStream,
///   builder: (context, snapshot) => Text('残り${snapshot.data}秒'),
/// );
///
/// // キャンセル
/// timer.cancel();
/// ```
class EscapeTimer {
  /// 残り秒数をUIに流すStreamController（broadcast = 複数リスナー対応）
  final StreamController<int> _streamController =
      StreamController<int>.broadcast();

  /// 内部で動かしているタイマー（キャンセル用に保持）
  Timer? _timer;

  /// 現在の残り秒数
  int _remainingSeconds = 0;

  /// タイマーが動作中かどうか
  bool _isRunning = false;

  /// 残り秒数のStream（UIバインド用）
  ///
  /// StreamBuilderで購読することで残り秒数をリアルタイム表示できる。
  Stream<int> get remainingStream => _streamController.stream;

  /// 現在の残り秒数（即時取得用）
  int get remainingSeconds => _remainingSeconds;

  /// タイマーが動作中かどうか
  bool get isRunning => _isRunning;

  /// カウントダウンを開始する
  ///
  /// [seconds] : カウントダウンの秒数
  /// [onComplete] : カウントダウン終了時に呼ばれるコールバック
  ///
  /// すでに動作中の場合は前のタイマーをキャンセルして新しく開始する。
  void start({required int seconds, required VoidCallback onComplete}) {
    // 前のタイマーが残っていればキャンセル
    cancel();

    _remainingSeconds = seconds;
    _isRunning = true;

    // 開始時点の秒数を即座にStreamに流す
    if (!_streamController.isClosed) {
      _streamController.add(_remainingSeconds);
    }

    // 1秒ごとにカウントダウン
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingSeconds--;

      // 残り秒数をStreamに流す
      if (!_streamController.isClosed) {
        _streamController.add(_remainingSeconds);
      }

      // カウントダウン終了
      if (_remainingSeconds <= 0) {
        _timer?.cancel();
        _timer = null;
        _isRunning = false;
        onComplete();
      }
    });
  }

  /// カウントダウンをキャンセルする
  ///
  /// Streamには何も流れない。onCompleteも呼ばれない。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _remainingSeconds = 0;
  }

  /// リソースを解放する
  ///
  /// Riverpodの ref.onDispose から呼び出される。
  /// StreamControllerとTimerを両方クローズする。
  void dispose() {
    cancel();
    if (!_streamController.isClosed) {
      _streamController.close();
    }
  }
}

/// EscapeTimer の Riverpodプロバイダー
///
/// アプリ全体でシングルトンとして使用する。
/// アプリ終了時に ref.onDispose で StreamController が自動クローズされる。
final escapeTimerProvider = Provider<EscapeTimer>((ref) {
  final t = EscapeTimer();
  ref.onDispose(t.dispose);
  return t;
});
