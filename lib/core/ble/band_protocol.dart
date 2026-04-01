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
///       band_authenticator.dart で実装済み。
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

  /// RXチャンネル (fe95 / 005e) — notify（受信専用）
  ///
  /// Band 9 からの通知受信（認証レスポンス・ボタン検知含む）に使用する。
  /// このキャラクタリスティックに subscribe して Band からのデータを受け取る。
  /// コマンドの書き込みには使わないこと。
  static const String rxChannel = '0000005e-0000-1000-8000-00805f9b34fb';

  /// TXチャンネル (fe95 / 005f) — write no response（送信用）
  ///
  /// Band 9 への認証コマンド・振動コマンドの送信に使用する。
  /// コマンドはすべてこのキャラクタリスティックに書き込む。
  static const String txChannel = '0000005f-0000-1000-8000-00805f9b34fb';

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

/// 認証コマンド定義（V2プロトコル: HMAC-SHA256 + AES-CCM）
///
/// Xiaomi Smart Band 9 の SPPv2 認証プロトコル定数。
/// Gadgetbridge MiWear認証実装に基づく。
class AuthCommands {
  AuthCommands._();

  /// CMD_NONCE: phoneNonce を送信し、watchNonce + watchHmac を受信する (subtype=26)
  static const int cmdNonce = 26;

  /// CMD_AUTH: phoneHmac を送信して認証を完了する (subtype=27)
  static const int cmdAuth = 27;

  /// CMD_SEND_USERID: ユーザーIDを送信する (subtype=5)
  static const int cmdSendUserId = 5;

  /// 認証ファミリータイプ (familyType=1)
  static const int authTypeV2 = 1;
}

/// メディアコントロールボタン定義（ステルストリガー）
///
/// Band 9 のメディアコントロール画面からのボタン操作を検知する。
/// rxChannel (005e) の Notify で受信する。
///
/// TODO: Band 9 の実際のボタンコード値は認証後の通信で確認が必要。
///       現在は Gadgetbridge 調査に基づく推定値。
class MediaControlButton {
  MediaControlButton._();

  /// 次の曲（ダブルタップ相当）→ ボイスメモ開始/停止
  static const int doubleTap = 0x04;

  /// 前の曲（トリプルタップ相当）→ 緊急アラート送信
  static const int tripleTap = 0x03;

  /// 再生/停止（長押し相当）→ 「今は安全」手動通知
  static const int longPress = 0x01;
}
