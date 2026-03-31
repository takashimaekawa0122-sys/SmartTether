import 'dart:collection';

/// RSSI値を平滑化して誤検知を防ぐクラス
///
/// 生のRSSI値は±10dBm程度ブレるため、
/// 移動平均＋外れ値除去を行う。
class RSSISmoother {
  final int windowSize;
  final Queue<int> _window = Queue<int>();

  RSSISmoother({this.windowSize = 7});

  /// 新しいRSSI値を追加する
  void addValue(int rssi) {
    _window.addLast(rssi);
    if (_window.length > windowSize) {
      _window.removeFirst();
    }
  }

  /// 平滑化されたRSSI値（外れ値除去済み移動平均）
  ///
  /// データが不十分な場合は生の平均を返す。
  /// データが0件の場合は-999（未接続扱い）を返す。
  double get smoothedValue {
    if (_window.isEmpty) return -999;
    if (_window.length <= 2) {
      return _window.reduce((a, b) => a + b) / _window.length;
    }

    // 最大・最小を1つずつ除外した平均（外れ値に強い）
    final sorted = _window.toList()..sort();
    final trimmed = sorted.sublist(1, sorted.length - 1);
    return trimmed.reduce((a, b) => a + b) / trimmed.length;
  }

  /// ウィンドウが満杯かどうか（信頼性の目安）
  bool get isReady => _window.length >= windowSize;

  /// スムージング済みの値を直接設定する（IPC受信用）
  ///
  /// メインIsolateで既にスムージング済みの値を受け取る場合に使用する。
  /// ウィンドウをクリアして単一値のみ保持する（二重スムージング防止）。
  void setDirectValue(int rssi) {
    _window.clear();
    _window.addLast(rssi);
  }

  /// データをリセット（再接続時などに使用）
  void reset() {
    _window.clear();
  }

  /// 現在のサンプル数
  int get sampleCount => _window.length;
}
