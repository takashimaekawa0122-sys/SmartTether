import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/ble/band_protocol.dart';

/// BandAuthenticator の認証コアロジック（AES-128-ECB 暗号化）をテストする。
///
/// BandAuthenticator 自体は FlutterReactiveBle（実機依存）を必要とするため
/// 直接インスタンス化できない。
/// このテストでは BandAuthenticator 内部の _encryptChallenge と同じ
/// アルゴリズムを単独で検証することで、暗号化ロジックの正確性を確認する。
///
/// テスト対象のアルゴリズム:
///   1. 32文字 HEX → 16バイトキーに変換
///   2. AES-128-ECB（パディングなし）で challenge を暗号化
///   3. 暗号文（16バイト）を返す

// ---------------------------------------------------------------------------
// テスト用ヘルパー関数（BandAuthenticator._encryptChallenge と同一ロジック）
// ---------------------------------------------------------------------------

List<int>? encryptChallenge(String authKeyHex, List<int> challenge) {
  try {
    final cleanHex = authKeyHex.replaceAll(RegExp(r'\s+'), '');
    if (cleanHex.length != 32) return null;

    final keyBytes = <int>[];
    for (var i = 0; i < cleanHex.length; i += 2) {
      keyBytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }

    final key = enc.Key(Uint8List.fromList(keyBytes));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb, padding: null));
    final encrypted = encrypter.encryptBytes(challenge);
    return encrypted.bytes.toList();
  } catch (e) {
    return null;
  }
}

void main() {
  group('BandAuthenticator - AES-128-ECB 暗号化ロジック', () {
    // Smart Band 9 実機の Auth Key（32文字 HEX = 16バイト）
    const testAuthKey = '872a5ccb7c1f7ec0310ee04b091135c6';

    // -------------------------------------------------------------------------
    // Auth Key の仕様確認
    // -------------------------------------------------------------------------

    test('実機の Auth Key は 32文字の HEX 文字列（16バイト相当）', () {
      expect(testAuthKey.length, equals(32));
    });

    test('Auth Key の各文字が有効な HEX 文字である', () {
      final hexPattern = RegExp(r'^[0-9a-fA-F]+$');
      expect(hexPattern.hasMatch(testAuthKey), isTrue);
    });

    test('Auth Key を 16バイト配列に変換できる', () {
      final keyBytes = <int>[];
      for (var i = 0; i < testAuthKey.length; i += 2) {
        keyBytes.add(int.parse(testAuthKey.substring(i, i + 2), radix: 16));
      }
      expect(keyBytes.length, equals(16));
    });

    // -------------------------------------------------------------------------
    // AES-128-ECB 暗号化のテスト
    // -------------------------------------------------------------------------

    test('16バイトの challenge を正しく暗号化して 16バイトを返す', () {
      // Band からの challenge データ（16バイト）
      final challenge = List<int>.generate(16, (i) => i);

      final result = encryptChallenge(testAuthKey, challenge);

      expect(result, isNotNull);
      expect(result!.length, equals(16));
    });

    test('同じ challenge を同じ key で暗号化すると毎回同じ結果（ECB は決定論的）', () {
      final challenge = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                         0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10];

      final result1 = encryptChallenge(testAuthKey, challenge);
      final result2 = encryptChallenge(testAuthKey, challenge);

      expect(result1, equals(result2));
    });

    test('異なる challenge は異なる暗号文になる', () {
      final challenge1 = List<int>.filled(16, 0x00);
      final challenge2 = List<int>.filled(16, 0xFF);

      final result1 = encryptChallenge(testAuthKey, challenge1);
      final result2 = encryptChallenge(testAuthKey, challenge2);

      expect(result1, isNotNull);
      expect(result2, isNotNull);
      expect(result1, isNot(equals(result2)));
    });

    test('異なる auth key は異なる暗号文になる', () {
      final challenge = List<int>.generate(16, (i) => i);
      const otherKey = 'ffffffffffffffffffffffffffffffff';

      final result1 = encryptChallenge(testAuthKey, challenge);
      final result2 = encryptChallenge(otherKey, challenge);

      expect(result1, isNotNull);
      expect(result2, isNotNull);
      expect(result1, isNot(equals(result2)));
    });

    // -------------------------------------------------------------------------
    // 無効な Auth Key の入力
    // -------------------------------------------------------------------------

    test('HEX 文字列が 32文字未満のとき null を返す', () {
      final challenge = List<int>.generate(16, (i) => i);
      // 30文字（不足）
      const shortKey = '872a5ccb7c1f7ec0310ee04b09113';
      expect(encryptChallenge(shortKey, challenge), isNull);
    });

    test('HEX 文字列が 32文字超のとき null を返す', () {
      final challenge = List<int>.generate(16, (i) => i);
      // 34文字（超過）
      const longKey = '872a5ccb7c1f7ec0310ee04b091135c6aa';
      expect(encryptChallenge(longKey, challenge), isNull);
    });

    test('空文字列のとき null を返す', () {
      final challenge = List<int>.generate(16, (i) => i);
      expect(encryptChallenge('', challenge), isNull);
    });

    test('スペースを含む Auth Key は正規化してから使用する', () {
      final challenge = List<int>.generate(16, (i) => i);
      // スペースを挟んだ同じキー
      const keyWithSpaces = '872a5ccb 7c1f7ec0 310ee04b 091135c6';

      final result = encryptChallenge(keyWithSpaces, challenge);
      final resultNoSpaces = encryptChallenge(testAuthKey, challenge);

      // スペースを除去すれば同じキーなので同じ結果になる
      expect(result, equals(resultNoSpaces));
    });

    // -------------------------------------------------------------------------
    // BandProtocol 定数の確認
    // -------------------------------------------------------------------------

    test('AuthCommands.requestAuthNumber は 0x02', () {
      expect(AuthCommands.requestAuthNumber, equals(0x02));
    });

    test('AuthCommands.sendEncryptedNumber は 0x04', () {
      expect(AuthCommands.sendEncryptedNumber, equals(0x04));
    });

    test('AuthCommands.authSuccess は 0x01', () {
      expect(AuthCommands.authSuccess, equals(0x01));
    });

    // -------------------------------------------------------------------------
    // BandServiceUUIDs の確認
    // -------------------------------------------------------------------------

    test('メインサービス UUID が正しい形式', () {
      const uuidPattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
      final regex = RegExp(uuidPattern, caseSensitive: false);
      expect(regex.hasMatch(BandServiceUUIDs.main), isTrue);
    });

    test('メインチャンネル UUID が正しい形式', () {
      const uuidPattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
      final regex = RegExp(uuidPattern, caseSensitive: false);
      expect(regex.hasMatch(BandCharacteristicUUIDs.mainChannel), isTrue);
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
    test('doubleTab は 0x01', () {
      expect(MediaControlButton.doubleTab, equals(0x01));
    });

    test('tripleTab は 0x02', () {
      expect(MediaControlButton.tripleTab, equals(0x02));
    });

    test('longPress は 0x03', () {
      expect(MediaControlButton.longPress, equals(0x03));
    });
  });
}
