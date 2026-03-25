import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/ble/band_protocol.dart';

void main() {
  // ---------------------------------------------------------------------------
  // BandServiceUUIDs
  // ---------------------------------------------------------------------------

  group('BandServiceUUIDs', () {
    test('main UUID が正しい値を持つ', () {
      expect(
        BandServiceUUIDs.main,
        equals('0000fee0-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('auth UUID が正しい値を持つ', () {
      expect(
        BandServiceUUIDs.auth,
        equals('0000fee1-0000-1000-8000-00805f9b34fb'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // BandCharacteristicUUIDs
  // ---------------------------------------------------------------------------

  group('BandCharacteristicUUIDs', () {
    test('auth UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.auth,
        equals('00000009-0000-3512-2118-0009af100700'),
      );
    });

    test('notification UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.notification,
        equals('00000010-0000-3512-2118-0009af100700'),
      );
    });

    test('deviceInfo UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.deviceInfo,
        equals('00000004-0000-3512-2118-0009af100700'),
      );
    });

    test('battery UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.battery,
        equals('00000006-0000-3512-2118-0009af100700'),
      );
    });

    test('sensor UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.sensor,
        equals('00000007-0000-3512-2118-0009af100700'),
      );
    });

    test('mediaControl UUID が正しい値を持つ', () {
      expect(
        BandCharacteristicUUIDs.mediaControl,
        equals('00000011-0000-3512-2118-0009af100700'),
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

  group('AuthCommands', () {
    test('requestAuthNumber が 0x02', () {
      expect(AuthCommands.requestAuthNumber, equals(0x02));
    });

    test('sendEncryptedNumber が 0x04', () {
      expect(AuthCommands.sendEncryptedNumber, equals(0x04));
    });

    test('authSuccess が 0x01', () {
      expect(AuthCommands.authSuccess, equals(0x01));
    });
  });

  // ---------------------------------------------------------------------------
  // MediaControlButton
  // ---------------------------------------------------------------------------

  group('MediaControlButton', () {
    test('doubleTab が 0x01', () {
      expect(MediaControlButton.doubleTab, equals(0x01));
    });

    test('tripleTab が 0x02', () {
      expect(MediaControlButton.tripleTab, equals(0x02));
    });

    test('longPress が 0x03', () {
      expect(MediaControlButton.longPress, equals(0x03));
    });
  });
}
