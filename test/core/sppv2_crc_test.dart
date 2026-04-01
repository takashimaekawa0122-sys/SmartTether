import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/ble/sppv2_packet.dart';

/// Java Integer.reverse() のDart実装（検証用）
int javaIntegerReverse(int value) {
  // Javaは32ビット符号付き整数
  // まず32ビットに切り詰める
  value = value & 0xFFFFFFFF;
  var result = 0;
  for (var i = 0; i < 32; i++) {
    result = (result << 1) | ((value >> i) & 1);
  }
  return result & 0xFFFFFFFF;
}

/// Java calculatePayloadChecksum の忠実な移植（検証用）
///
/// Java原文:
/// ```java
/// private static int calculatePayloadChecksum(final byte[] payload) {
///     int crc = 0;
///     for (final byte b : payload) {
///         for (int j = 0; j < 8; j++) {
///             crc <<= 1;
///             if ((((crc >> 16) & 1) ^ ((b >> j) & 1)) == 1)
///                 crc ^= 0x8005;
///         }
///     }
///     return (Integer.reverse(crc) >>> 16);
/// }
/// ```
///
/// 注意: Java の byte は符号付き(-128~127)。
///       Java の >> は算術シフト（符号拡張あり）。
///       Java の int は 32ビット符号付き。
int javaStyleCrc16(List<int> payload) {
  // Java の int は 32ビット符号付きだが、ここでは & 0xFFFFFFFF で模倣
  var crc = 0;
  for (final rawByte in payload) {
    // Java の byte は符号付き。Dart の int は符号なしで渡されるので、
    // Java の挙動を再現するには符号付きに変換する必要がある。
    // Java: (b >> j) & 1  — b は signed byte
    // 例: b=0xfc → Java では -4 → ((-4) >> 0) & 1 = 0, ((-4) >> 1) & 1 = 0, ...
    // しかし (b >> j) & 1 はビットjを取り出すだけなので、
    // 符号付きでも符号なしでも結果は同じ（j < 8 の場合）。
    // Java の byte 型で b >> j を行うと、b は int に昇格（符号拡張）される。
    // 例: byte b = 0xfc → int b = 0xFFFFFFFC (-4)
    //     (0xFFFFFFFC >> 0) & 1 = 0
    //     (0xFFFFFFFC >> 1) & 1 = 0
    //     (0xFFFFFFFC >> 2) & 1 = 1  (ビット2)
    //     ...ビット2-7は 0xfc = 11111100 なので: 0,0,1,1,1,1,1,1
    //
    // Dart の符号なし byte: 0xfc = 252
    //     (252 >> 0) & 1 = 0
    //     (252 >> 1) & 1 = 0
    //     (252 >> 2) & 1 = 1
    //     ...完全に一致！
    //
    // したがって、j < 8 の範囲では符号の扱いは影響しない。
    final b = rawByte & 0xFF;

    for (var j = 0; j < 8; j++) {
      // Java: crc <<= 1 (32ビットint内でのシフト)
      crc = (crc << 1) & 0xFFFFFFFF;

      // Java: (crc >> 16) & 1 — 算術シフトだが &1 なので符号関係なし
      // Java: (b >> j) & 1
      if ((((crc >> 16) & 1) ^ ((b >> j) & 1)) == 1) {
        crc ^= 0x8005;
      }
    }
  }
  // Java: Integer.reverse(crc) >>> 16
  // >>> はunsigned right shift
  final reversed = javaIntegerReverse(crc);
  return (reversed >> 16) & 0xFFFF; // Dartでは & 0xFFFF で unsigned 効果
}

void main() {
  group('Sppv2ReceiveBuffer テスト', () {
    test('完全なフレームを1回で受信した場合', () {
      final buffer = Sppv2ReceiveBuffer();
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);

      final results = buffer.append(packet);
      expect(results.length, equals(1));
      expect(results[0].frameType, equals(0x02));
    });

    test('フレームが2回の通知に分割された場合', () {
      final buffer = Sppv2ReceiveBuffer();
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);

      // MTU 20 を想定: 最初の 20 バイトと残り 10 バイトに分割
      final part1 = packet.sublist(0, 20);
      final part2 = packet.sublist(20);

      final results1 = buffer.append(part1);
      expect(results1, isEmpty, reason: '最初の20バイトでは不完全');

      final results2 = buffer.append(part2);
      expect(results2.length, equals(1), reason: '残り10バイトで完成');
      expect(results2[0].frameType, equals(0x02));
      expect(results2[0].data.length, equals(22));
    });

    test('1回の通知に2つのフレームが含まれる場合', () {
      final buffer = Sppv2ReceiveBuffer();
      final packet1 = Sppv2Packet.buildSessionConfig(sequence: 0);
      final packet2 = Sppv2Packet.buildSessionConfig(sequence: 1);

      final combined = Uint8List.fromList([...packet1, ...packet2]);
      final results = buffer.append(combined);
      expect(results.length, equals(2));
      expect(results[0].sequence, equals(0));
      expect(results[1].sequence, equals(1));
    });

    test('ヘッダーだけ受信した場合', () {
      final buffer = Sppv2ReceiveBuffer();
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);

      // ヘッダーの8バイトだけ
      final results = buffer.append(packet.sublist(0, 8));
      expect(results, isEmpty);

      // 残りを追加
      final results2 = buffer.append(packet.sublist(8));
      expect(results2.length, equals(1));
    });

    test('ゴミデータの後にフレームがある場合', () {
      final buffer = Sppv2ReceiveBuffer();
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);

      // ゴミ + 正常パケット
      final withGarbage = Uint8List.fromList([0x00, 0x01, 0x02, ...packet]);
      final results = buffer.append(withGarbage);
      expect(results.length, equals(1));
      expect(results[0].frameType, equals(0x02));
    });

    test('reset() でバッファがクリアされる', () {
      final buffer = Sppv2ReceiveBuffer();
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);

      // 途中まで送信
      buffer.append(packet.sublist(0, 15));
      buffer.reset();

      // 残りを送信しても前のデータは消えている
      final results = buffer.append(packet.sublist(15));
      expect(results, isEmpty);
    });
  });

  group('CRC-16 比較テスト', () {
    test('SESSION_CONFIG ペイロードの CRC-16 が Java 実装と一致すること', () {
      // Gadgetbridge の SessionConfigPacket.getPacketPayloadBytes() と同一
      final payload = Uint8List.fromList([
        0x01, // opcode = START_SESSION_REQUEST
        0x01, 0x03, 0x00, 0x01, 0x00, 0x00, // VERSION
        0x02, 0x02, 0x00, 0x00, 0xfc, // MAX_PACKET_SIZE
        0x03, 0x02, 0x00, 0x20, 0x00, // TX_WIN
        0x04, 0x02, 0x00, 0x10, 0x27, // SEND_TIMEOUT
      ]);

      final javaCrc = javaStyleCrc16(payload);
      // ignore: avoid_print
      print('Java CRC-16: 0x${javaCrc.toRadixString(16).padLeft(4, '0')}');

      // SmartTether の CRC をテスト
      // buildSessionConfig が生成するパケットを取得してCRCを抽出
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);
      // ignore: avoid_print
      print('Full packet: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // パケットバイト[6],[7] がCRC（リトルエンディアン）
      final dartCrc = packet[6] | (packet[7] << 8);
      // ignore: avoid_print
      print('Dart CRC-16: 0x${dartCrc.toRadixString(16).padLeft(4, '0')}');

      expect(dartCrc, equals(javaCrc),
          reason: 'CRC-16 が Java 実装と Dart 実装で一致すべき');
    });

    test('空ペイロードの CRC-16', () {
      final payload = Uint8List(0);
      final javaCrc = javaStyleCrc16(payload);
      // ignore: avoid_print
      print('空ペイロード Java CRC-16: 0x${javaCrc.toRadixString(16).padLeft(4, '0')}');
      expect(javaCrc, equals(0), reason: '空ペイロードのCRCは0');
    });

    test('単一バイト 0x01 の CRC-16', () {
      final payload = Uint8List.fromList([0x01]);
      final javaCrc = javaStyleCrc16(payload);
      // ignore: avoid_print
      print('0x01 Java CRC-16: 0x${javaCrc.toRadixString(16).padLeft(4, '0')}');
    });

    test('単一バイト 0xff の CRC-16', () {
      final payload = Uint8List.fromList([0xFF]);
      final javaCrc = javaStyleCrc16(payload);
      // ignore: avoid_print
      print('0xff Java CRC-16: 0x${javaCrc.toRadixString(16).padLeft(4, '0')}');
    });

    test('SESSION_CONFIG パケット全体のバイト列検証', () {
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);

      // 期待されるフレーム構造:
      // [a5][a5] magic
      // [02]     frameType = SESSION_CONFIG (packetType & 0xf)
      // [00]     sequence = 0
      // [16][00] payload length = 22 bytes (0x0016 LE)
      // [CRC_LO][CRC_HI]
      // [payload 22 bytes]

      expect(packet[0], equals(0xa5), reason: 'magic byte 1');
      expect(packet[1], equals(0xa5), reason: 'magic byte 2');
      expect(packet[2], equals(0x02), reason: 'frameType = SESSION_CONFIG');
      expect(packet[3], equals(0x00), reason: 'sequence = 0');
      expect(packet[4], equals(22), reason: 'payload length low byte');
      expect(packet[5], equals(0), reason: 'payload length high byte');
      // packet[6], packet[7] = CRC
      // packet[8..29] = payload

      // ペイロード検証
      final expectedPayload = [
        0x01, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x00, 0x00, 0xfc,
        0x03, 0x02, 0x00, 0x20, 0x00,
        0x04, 0x02, 0x00, 0x10, 0x27,
      ];
      for (var i = 0; i < expectedPayload.length; i++) {
        expect(packet[8 + i], equals(expectedPayload[i]),
            reason: 'payload byte $i');
      }

      // ignore: avoid_print
      print('パケット長: ${packet.length} バイト (8 header + 22 payload = 30)');
      expect(packet.length, equals(30));
    });

    test('パースの往復テスト', () {
      final packet = Sppv2Packet.buildSessionConfig(sequence: 0);
      final parsed = Sppv2Packet.parse(packet);
      expect(parsed, isNotNull, reason: 'CRCが正しければパース成功するはず');
      expect(parsed!.frameType, equals(0x02));
      expect(parsed.sequence, equals(0));
      expect(parsed.data.length, equals(22));
    });
  });
}
