import 'dart:typed_data';

/// SPPv2 パケットのチャンネルID定義
class Sppv2Channel {
  Sppv2Channel._();

  /// 認証チャンネル
  static const int auth = 0x01;

  /// 一般コマンドチャンネル
  static const int command = 0x02;
}

/// SPPv2 パケットのペイロードタイプ定義
class Sppv2PayloadType {
  Sppv2PayloadType._();

  /// 平文ペイロード
  static const int plaintext = 0x01;

  /// 暗号化済みペイロード
  static const int encrypted = 0x02;
}

/// SPPv2 パケットのフレームタイプ定義
class Sppv2FrameType {
  Sppv2FrameType._();

  /// ACKフレーム
  static const int ack = 0x01;

  /// セッション設定フレーム（認証前のハンドシェイクに使用）
  static const int sessionConfig = 0x02;

  /// コマンドフレーム
  static const int command = 0x03;
}

/// SESSION_CONFIG オペコード定義
///
/// Gadgetbridge: XiaomiSppPacketV2.SessionConfigPacket.OPCODE_START_SESSION_REQUEST = 1
class Sppv2SessionOpcode {
  Sppv2SessionOpcode._();

  /// セッション開始リクエスト
  static const int startSessionRequest = 0x01;

  /// セッション開始レスポンス（Bandからの応答）
  static const int startSessionResponse = 0x02;
}

/// SPPv2パケットの組み立て・解析クラス
///
/// パケット構造:
///   [a5][a5]  マジックバイト (2バイト)
///   [TT]      フレームタイプ: 0x01=ACK, 0x03=コマンド (1バイト)
///   [SS]      シーケンス番号 (1バイト)
///   [LL][LL]  ペイロード長 (2バイト, リトルエンディアン)
///   [CC][CC]  ペイロードCRC16 (2バイト, リトルエンディアン)
///   [payload] 実データ
///
/// ペイロード内部構造:
///   [CH]      チャンネルID (1バイト)
///   [TP]      タイプ: 0x01=平文, 0x02=暗号化済み (1バイト)
///   [data]    実際のコマンドデータ
///
/// CRC16アルゴリズム: CCITT/XMODEM (多項式: 0x1021, 初期値: 0x0000)
class Sppv2Packet {
  static const int _magic1 = 0xa5;
  static const int _magic2 = 0xa5;
  static const int _headerLength = 6; // magic(2) + type(1) + seq(1) + len(2)

  /// SESSION_CONFIG パケットを組み立てる
  ///
  /// 認証前に必須のハンドシェイクパケット。
  /// Gadgetbridge: XiaomiSppPacketV2.newSessionConfigPacketBuilder()
  ///
  /// ペイロード構造（22バイト固定）:
  ///   [opcode(1)]
  ///   [type=0x01, VERSION(3): 01 00 00]
  ///   [type=0x02, MAX_PACKET_SIZE(2): fc 00 = 64512]
  ///   [type=0x03, TX_WIN(2): 00 20 = 32]
  ///   [type=0x04, SEND_TIMEOUT(2): 27 10 = 10000ms]
  static Uint8List buildSessionConfig({int sequence = 0}) {
    // ペイロード: opcode(1) + 4つの設定パラメータ
    final payload = Uint8List.fromList([
      Sppv2SessionOpcode.startSessionRequest, // opcode = 0x01
      0x01, 0x01, 0x00, 0x00,                 // VERSION: type=1, value=1.0.0
      0x02, 0xfc, 0x00,                        // MAX_PACKET_SIZE: type=2, value=64512 (LE)
      0x03, 0x00, 0x20,                        // TX_WIN: type=3, value=32 (LE)
      0x04, 0x27, 0x10,                        // SEND_TIMEOUT: type=4, value=10000ms (BE)
    ]);

    return _buildFrame(
      frameType: Sppv2FrameType.sessionConfig,
      sequence: sequence,
      payload: payload,
    );
  }

  /// コマンドパケットを組み立てる
  ///
  /// [channelId]   チャンネルID (例: Sppv2Channel.auth)
  /// [payloadType] ペイロードタイプ (例: Sppv2PayloadType.plaintext)
  /// [data]        コマンドデータ
  /// [sequence]    シーケンス番号 (0-255)
  static Uint8List buildCommand({
    required int channelId,
    required int payloadType,
    required List<int> data,
    int sequence = 0,
  }) {
    // ペイロード = [channelId, payloadType, ...data]
    final payload = Uint8List(2 + data.length);
    payload[0] = channelId;
    payload[1] = payloadType;
    for (var i = 0; i < data.length; i++) {
      payload[2 + i] = data[i];
    }

    return _buildFrame(
      frameType: Sppv2FrameType.command,
      sequence: sequence,
      payload: payload,
    );
  }

  /// フレームを組み立てる（内部共通処理）
  static Uint8List _buildFrame({
    required int frameType,
    required int sequence,
    required Uint8List payload,
  }) {
    final payloadLength = payload.length;
    final crc = _calculateCrc16(payload);

    // ヘッダー(6バイト) + CRC(2バイト) + ペイロード
    final frame = Uint8List(_headerLength + 2 + payloadLength);
    var offset = 0;

    frame[offset++] = _magic1;
    frame[offset++] = _magic2;
    frame[offset++] = frameType;
    frame[offset++] = sequence & 0xFF;
    // ペイロード長: リトルエンディアン
    frame[offset++] = payloadLength & 0xFF;
    frame[offset++] = (payloadLength >> 8) & 0xFF;
    // CRC16: リトルエンディアン
    frame[offset++] = crc & 0xFF;
    frame[offset++] = (crc >> 8) & 0xFF;
    // ペイロード本体
    frame.setRange(offset, offset + payloadLength, payload);

    return frame;
  }

  /// 受信したフレームを解析する
  ///
  /// 解析に失敗した場合は null を返す。
  static Sppv2ParsedPacket? parse(List<int> bytes) {
    if (bytes.length < _headerLength + 2) return null;

    // マジックバイト確認
    if (bytes[0] != _magic1 || bytes[1] != _magic2) return null;

    final frameType = bytes[2];
    final sequence = bytes[3];
    final payloadLength = bytes[4] | (bytes[5] << 8);
    final crcReceived = bytes[6] | (bytes[7] << 8);

    final totalExpected = _headerLength + 2 + payloadLength;
    if (bytes.length < totalExpected) return null;

    final payload = Uint8List.fromList(
      bytes.sublist(_headerLength + 2, _headerLength + 2 + payloadLength),
    );

    // CRC検証
    final crcCalculated = _calculateCrc16(payload);
    if (crcCalculated != crcReceived) return null;

    if (payload.length < 2) return null;

    final channelId = payload[0];
    final payloadType = payload[1];
    final data = payload.sublist(2);

    return Sppv2ParsedPacket(
      frameType: frameType,
      sequence: sequence,
      channelId: channelId,
      payloadType: payloadType,
      data: data,
    );
  }

  /// CRC16 CCITT/XMODEM アルゴリズム
  ///
  /// 多項式: 0x1021
  /// 初期値: 0x0000
  /// 入力反転: なし
  /// 出力反転: なし
  static int _calculateCrc16(Uint8List data) {
    var crc = 0x0000;
    for (final byte in data) {
      crc ^= (byte & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }
}

/// 解析済みSPPv2パケットを表すデータクラス
class Sppv2ParsedPacket {
  final int frameType;
  final int sequence;
  final int channelId;
  final int payloadType;
  final Uint8List data;

  const Sppv2ParsedPacket({
    required this.frameType,
    required this.sequence,
    required this.channelId,
    required this.payloadType,
    required this.data,
  });

  @override
  String toString() {
    return 'Sppv2ParsedPacket('
        'frameType: 0x${frameType.toRadixString(16)}, '
        'seq: $sequence, '
        'channel: 0x${channelId.toRadixString(16)}, '
        'payloadType: 0x${payloadType.toRadixString(16)}, '
        'data: [${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}])';
  }
}
