/// テザー監視の状態定義
enum TetherState {
  /// 安全圏（自宅Wi-Fi接続中）- 監視スリープ
  sleeping,

  /// 危険圏・正常監視中
  monitoring,

  /// 切断後0〜3秒（猶予フェーズ）- バックグラウンド再接続中
  grace,

  /// 切断後4〜9秒（警告フェーズ）- バンドを振動させる
  warning,

  /// 切断後10秒以上（確定フェーズ）- 全力アラート
  confirmed,

  /// お留守番モード（安全圏でバンドが切断）
  standby,
}

/// 状態に対応するラベル
extension TetherStateLabel on TetherState {
  String get label {
    switch (this) {
      case TetherState.sleeping:
        return '安全圏・監視スリープ中';
      case TetherState.monitoring:
        return '危険圏・監視中';
      case TetherState.grace:
        return '再接続を試行中...';
      case TetherState.warning:
        return '警告：バンドが離れています';
      case TetherState.confirmed:
        return '⚠️ 置き忘れを検知しました';
      case TetherState.standby:
        return 'お留守番モード';
    }
  }

  bool get isAlerting =>
      this == TetherState.warning || this == TetherState.confirmed;
}
