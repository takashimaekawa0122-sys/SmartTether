/// Xiaomi Smart Band 9 BLEプロトコル定数
///
/// Band 9 は旧世代（Band 5以前の fee0/fee1）と異なる新世代プロトコルを使用する。
/// 実機スキャンで確認されたサービス/キャラクタリスティックのUUIDを定義する。
///
/// 実機スキャン結果（2026-03-25）:
///   - fe95: メイン通信サービス（005e: wN, 005f: wN）
///   - fdab: ペアリングサービス（0002: wN, 0003: wN）
///   - 180f: Battery Service（標準BLE）
///   - 180a: Device Information Service（標準BLE）
///
/// 注意: Band 9 の認証プロトコルは HMAC-SHA256 + AES-CCM（V2プロトコル）。
///       現在は未実装のため認証なしでRSSI監視のみ動作する。
library;

/// BLEサービスUUID
class BandServiceUUIDs {
  BandServiceUUIDs._();

  /// Band 9 メイン通信サービス（旧: fee0/fee1）
  static const String main = '0000fe95-0000-1000-8000-00805f9b34fb';

  /// Band 9 ペアリング/認証サービス（初回ペアリング時のみ使用）
  static const String pairing = '0000fdab-0000-1000-8000-00805f9b34fb';

  /// 標準 Battery Service
  static const String battery = '0000180f-0000-1000-8000-00805f9b34fb';

  /// 標準 Device Information Service
  static const String deviceInfo = '0000180a-0000-1000-8000-00805f9b34fb';
}

/// BLEキャラクタリスティックUUID
class BandCharacteristicUUIDs {
  BandCharacteristicUUIDs._();

  /// メイン送受信チャンネル (fe95 / 005e) — write no response + notify
  ///
  /// Band 9 への認証コマンド・振動コマンドの送信と
  /// デバイスからの通知受信（ボタン検知含む）に使用する。
  static const String mainChannel = '0000005e-0000-1000-8000-00805f9b34fb';

  /// サブ送受信チャンネル (fe95 / 005f) — write no response + notify
  ///
  /// mainChannel と同等のプロパティ。用途は調査中。
  static const String subChannel = '0000005f-0000-1000-8000-00805f9b34fb';

  /// バッテリーレベル (180f / 2a19) — 標準 BLE Battery Level Characteristic
  static const String batteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';
}

/// 振動パターン定義
class VibrationPattern {
  final List<int> pattern; // [ON時間ms, OFF時間ms, ...]
  final int repeat; // 繰り返し回数

  const VibrationPattern({
    required this.pattern,
    this.repeat = 1,
  });

  /// 置き忘れ警告（短・短・短）
  static const warning = VibrationPattern(
    pattern: [200, 100, 200, 100, 200],
    repeat: 1,
  );

  /// 盗難検知（長・長）
  static const theft = VibrationPattern(
    pattern: [800, 200, 800],
    repeat: 1,
  );

  /// バッテリー低下（短・長）
  static const batteryLow = VibrationPattern(
    pattern: [150, 100, 600],
    repeat: 1,
  );

  /// つけ忘れ通知（短・短・長）
  static const forgotten = VibrationPattern(
    pattern: [150, 100, 150, 100, 500],
    repeat: 1,
  );

  /// システムシャットダウン（長めの専用振動）
  static const shutdown = VibrationPattern(
    pattern: [1000, 200, 1000, 200, 1000],
    repeat: 1,
  );
}

/// 認証コマンド定義
///
/// TODO: Band 9 は HMAC-SHA256 + AES-CCM (V2プロトコル) を使用する。
///       以下の定数は旧世代プロトコル用であり、Band 9 では動作しない。
///       V2プロトコル実装後にこのクラスを更新すること。
class AuthCommands {
  AuthCommands._();

  static const int requestAuthNumber = 0x02;
  static const int sendEncryptedNumber = 0x04;
  static const int authSuccess = 0x01;
}

/// メディアコントロールボタン定義（ステルストリガー）
///
/// Band 9 のメディアコントロール画面からのボタン操作を検知する。
/// mainChannel (005e) の Notify で受信する。
///
/// TODO: Band 9 の実際のボタンコード値は認証後の通信で確認が必要。
///       現在は Gadgetbridge 調査に基づく推定値。
class MediaControlButton {
  MediaControlButton._();

  /// 次の曲（ダブルタップ相当）→ ボイスメモ開始/停止
  static const int doubleTab = 0x04;

  /// 前の曲（トリプルタップ相当）→ 緊急アラート送信
  static const int tripleTab = 0x03;

  /// 再生/停止（長押し相当）→ 「今は安全」手動通知
  static const int longPress = 0x01;
}
