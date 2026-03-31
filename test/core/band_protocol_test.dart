import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/ble/band_protocol.dart';

void main() {
  // ---------------------------------------------------------------------------
  // BandServiceUUIDs
  // ---------------------------------------------------------------------------

  group('BandServiceUUIDs', () {
    test('main UUID が Band 9 の正しい値を持つ', () {
      expect(
        BandServiceUUIDs.main,
        equals('0000fe95-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('pairing UUID が正しい値を持つ', () {
      expect(
        BandServiceUUIDs.pairing,
        equals('0000fdab-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('battery UUID が標準BLE値を持つ', () {
      expect(
        BandServiceUUIDs.battery,
        equals('0000180f-0000-1000-8000-00805f9b34fb'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // BandCharacteristicUUIDs
  // ---------------------------------------------------------------------------

  group('BandCharacteristicUUIDs', () {
    test('mainChannel UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.mainChannel,
        equals('0000005e-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('subChannel UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.subChannel,
        equals('0000005f-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('batteryLevel UUID が標準BLE値を持つ', () {
      expect(
        BandCharacteristicUUIDs.batteryLevel,
        equals('00002a19-0000-1000-8000-00805f9b34fb'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // VibrationPattern
  // ---------------------------------------------------------------------------

  group('VibrationPattern', () {
    test('warning パターンが正しい', () {
      expect(VibrationPattern.warning.pattern, equals([200, 100, 200, 100, 200]));
      expect(VibrationPattern.warning.repeat, equals(1));
    });

    test('theft パターンが正しい', () {
      expect(VibrationPattern.theft.pattern, equals([800, 200, 800]));
      expect(VibrationPattern.theft.repeat, equals(1));
    });

    test('batteryLow パターンが正しい', () {
      expect(VibrationPattern.batteryLow.pattern, equals([150, 100, 600]));
      expect(VibrationPattern.batteryLow.repeat, equals(1));
    });

    test('forgotten パターンが正しい', () {
      expect(VibrationPattern.forgotten.pattern, equals([150, 100, 150, 100, 500]));
      expect(VibrationPattern.forgotten.repeat, equals(1));
    });

    test('shutdown パターンが正しい', () {
      expect(VibrationPattern.shutdown.pattern, equals([1000, 200, 1000, 200, 1000]));
      expect(VibrationPattern.shutdown.repeat, equals(1));
    });

    test('カスタムパターンをコンストラクタで生成できる', () {
      const custom = VibrationPattern(
        pattern: [300, 150, 300],
        repeat: 3,
      );
      expect(custom.pattern, equals([300, 150, 300]));
      expect(custom.repeat, equals(3));
    });

    test('repeatのデフォルト値は1', () {
      const custom = VibrationPattern(pattern: [500]);
      expect(custom.repeat, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // AuthCommands
  // ---------------------------------------------------------------------------

  // V2プロトコルへの移行に伴い、AuthCommands の定数を更新
  group('AuthCommands (V2プロトコル)', () {
    test('cmdNonce が 26', () {
      expect(AuthCommands.cmdNonce, equals(26));
    });

    test('cmdAuth が 27', () {
      expect(AuthCommands.cmdAuth, equals(27));
    });

    test('cmdSendUserId が 5', () {
      expect(AuthCommands.cmdSendUserId, equals(5));
    });

    test('authTypeV2 が 1', () {
      expect(AuthCommands.authTypeV2, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // MediaControlButton
  // ---------------------------------------------------------------------------

  group('MediaControlButton', () {
    test('doubleTab が 0x04（Band 9: 次の曲）', () {
      expect(MediaControlButton.doubleTab, equals(0x04));
    });

    test('tripleTab が 0x03（Band 9: 前の曲）', () {
      expect(MediaControlButton.tripleTab, equals(0x03));
    });

    test('longPress が 0x01（Band 9: 再生/停止）', () {
      expect(MediaControlButton.longPress, equals(0x01));
    });
  });
}
