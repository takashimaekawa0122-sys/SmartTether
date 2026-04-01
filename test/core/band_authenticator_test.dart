import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/ble/band_protocol.dart';

/// BandProtocol 定数・MediaControlButton のテスト
///
/// BandAuthenticator 本体は FlutterReactiveBle（実機依存）を必要とするため
/// ユニットテストでは BLE プロトコル定数の正確性を検証する。

void main() {
  group('AuthCommands', () {
    test('cmdNonce は 26', () {
      expect(AuthCommands.cmdNonce, equals(26));
    });

    test('cmdAuth は 27', () {
      expect(AuthCommands.cmdAuth, equals(27));
    });

    test('authTypeV2 は 1', () {
      expect(AuthCommands.authTypeV2, equals(1));
    });
  });

  group('BandServiceUUIDs', () {
    test('メインサービス UUID が正しい形式', () {
      const uuidPattern =
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
      final regex = RegExp(uuidPattern, caseSensitive: false);
      expect(regex.hasMatch(BandServiceUUIDs.main), isTrue);
    });
  });

  group('BandCharacteristicUUIDs', () {
    test('rxChannel と txChannel が正しい UUID 形式', () {
      const uuidPattern =
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
      final regex = RegExp(uuidPattern, caseSensitive: false);
      expect(regex.hasMatch(BandCharacteristicUUIDs.rxChannel), isTrue);
      expect(regex.hasMatch(BandCharacteristicUUIDs.txChannel), isTrue);
    });
  });

  group('VibrationPattern', () {
    test('warning パターンは 5要素のバイト列を持つ', () {
      expect(VibrationPattern.warning.pattern.length, equals(5));
    });

    test('theft パターンは 3要素のバイト列を持つ', () {
      expect(VibrationPattern.theft.pattern.length, equals(3));
    });

    test('各パターンの repeat は 1', () {
      expect(VibrationPattern.warning.repeat, equals(1));
      expect(VibrationPattern.theft.repeat, equals(1));
      expect(VibrationPattern.batteryLow.repeat, equals(1));
      expect(VibrationPattern.forgotten.repeat, equals(1));
      expect(VibrationPattern.shutdown.repeat, equals(1));
    });
  });

  group('MediaControlButton', () {
    test('doubleTap は 0x04（Band 9: 次の曲）', () {
      expect(MediaControlButton.doubleTap, equals(0x04));
    });

    test('tripleTap は 0x03（Band 9: 前の曲）', () {
      expect(MediaControlButton.tripleTap, equals(0x03));
    });

    test('longPress は 0x01（Band 9: 再生/停止）', () {
      expect(MediaControlButton.longPress, equals(0x01));
    });
  });
}
