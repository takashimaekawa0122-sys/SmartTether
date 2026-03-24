/// Xiaomi Smart Band 9 BLEプロトコル定数
/// 参考: Gadgetbridge (https://github.com/Freeyourgadget/Gadgetbridge)
library;

/// BLEサービスUUID
class BandServiceUUIDs {
  BandServiceUUIDs._();

  /// メインサービス
  static const String main = '0000fee0-0000-1000-8000-00805f9b34fb';

  /// 認証サービス
  static const String auth = '0000fee1-0000-1000-8000-00805f9b34fb';
}

/// BLEキャラクタリスティックUUID
class BandCharacteristicUUIDs {
  BandCharacteristicUUIDs._();

  /// 認証キャラクタリスティック
  static const String auth = '00000009-0000-3512-2118-0009af100700';

  /// 通知キャラクタリスティック
  static const String notification = '00000010-0000-3512-2118-0009af100700';

  /// デバイス情報
  static const String deviceInfo = '00000004-0000-3512-2118-0009af100700';

  /// バッテリー情報
  static const String battery = '00000006-0000-3512-2118-0009af100700';

  /// センサーデータ（加速度・心拍）
  static const String sensor = '00000007-0000-3512-2118-0009af100700';

  /// メディアコントロール（ステルストリガー用）
  static const String mediaControl = '00000011-0000-3512-2118-0009af100700';
}

/// 振動パターン定義
class VibrationPattern {
  final List<int> pattern; // [ON時間ms, OFF時間ms, ...]
  final int repeat;        // 繰り返し回数

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

/// 認証コマンド定義（AES-128 Challenge-Response）
class AuthCommands {
  AuthCommands._();

  static const int requestAuthNumber = 0x02;
  static const int sendEncryptedNumber = 0x04;
  static const int authSuccess = 0x01;
}

/// メディアコントロールボタン定義（ステルストリガー）
class MediaControlButton {
  MediaControlButton._();

  /// ダブルタップ（次の曲）→ ボイスメモ開始/停止
  static const int doubleTab = 0x01;

  /// トリプルタップ（前の曲）→ 緊急アラート送信
  static const int tripleTab = 0x02;

  /// 長押し（再生/停止）→ 「今は安全」手動通知
  static const int longPress = 0x03;
}
