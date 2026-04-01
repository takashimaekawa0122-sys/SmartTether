import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:pointycastle/export.dart' as pc;

import 'band_protocol.dart';
import 'sppv2_packet.dart';

/// BLE認証の結果を表すシールドクラス
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  /// セッション暗号化キー（認証後の通信に使用）
  final SessionKeys keys;
  const AuthSuccess(this.keys);
}

class AuthFailure extends AuthResult {
  final String error;
  const AuthFailure(this.error);
}

/// 認証後のセッション鍵を保持するデータクラス
class SessionKeys {
  /// Band からの受信データ復号に使うキー (16バイト)
  final Uint8List decryptionKey;

  /// Band への送信データ暗号化に使うキー (16バイト)
  final Uint8List encryptionKey;

  /// AES-CCM 復号用ノンス先頭4バイト
  final Uint8List decryptionNonce;

  /// AES-CCM 暗号化用ノンス先頭4バイト
  final Uint8List encryptionNonce;

  const SessionKeys({
    required this.decryptionKey,
    required this.encryptionKey,
    required this.decryptionNonce,
    required this.encryptionNonce,
  });

  /// パケットID を組み込んだ 12バイト暗号化 Nonce を生成する
  ///
  /// 構造: encryptionNonce(4) + 0x00000000(4) + packetId(2) + 0x0000(2)
  Uint8List buildEncryptionNonce(int packetId) {
    final nonce = Uint8List(12);
    nonce.setRange(0, 4, encryptionNonce);
    // bytes 4-7: 0x00000000 (ゼロ埋め済み)
    nonce[8] = packetId & 0xFF;
    nonce[9] = (packetId >> 8) & 0xFF;
    // bytes 10-11: 0x0000 (ゼロ埋め済み)
    return nonce;
  }

  /// パケットID を組み込んだ 12バイト復号 Nonce を生成する
  ///
  /// 構造: decryptionNonce(4) + 0x00000000(4) + packetId(2) + 0x0000(2)
  Uint8List buildDecryptionNonce(int packetId) {
    final nonce = Uint8List(12);
    nonce.setRange(0, 4, decryptionNonce);
    nonce[8] = packetId & 0xFF;
    nonce[9] = (packetId >> 8) & 0xFF;
    return nonce;
  }
}

/// Xiaomi Smart Band 9 の V2認証プロトコル実装（HMAC-SHA256 + AES-CCM）
///
/// 認証フロー:
///   Step 1: phoneNonce(16バイト)を生成し、CMD_NONCE コマンドを送信
///   Step 2: Band から watchNonce(16バイト) + watchHmac(32バイト) を受信
///   Step 3: HMAC-SHA256 + KDF("miwear-auth") でセッション鍵を導出
///   Step 4: watchHmac を検証（decryptionKey で HMAC-SHA256）
///   Step 5: CMD_AUTH コマンドを送信（encryptionKey で HMAC-SHA256）
///
/// 参考: Gadgetbridge MiWear認証実装
class BandAuthenticator {
  final FlutterReactiveBle _ble;
  final _random = Random.secure();

  /// SPPv2 パケットのシーケンス番号（0-255 で循環）
  ///
  /// 認証セッションごとに 0 にリセットし、パケット送信のたびにインクリメントする。
  /// 同一セッション内での重複排除・リオーダー検知に使用される。
  int _sequence = 0;

  BandAuthenticator(this._ble);

  /// Band 9 との V2認証を行い、SessionKeys を含む AuthResult を返す
  ///
  /// [deviceId]  : 接続済みデバイスのID（MACアドレス）
  /// [authKeyHex]: 32文字のHEX文字列（16バイト）
  /// タイムアウトは10秒。
  Future<AuthResult> authenticateV2(String deviceId, String authKeyHex) async {
    try {
      return await _doAuthenticate(deviceId, authKeyHex)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return const AuthFailure(
          '認証タイムアウト（30秒）: SESSION_CONFIGへの応答またはCMD_NONCEへの応答なし');
    } catch (e) {
      return AuthFailure('認証エラー: $e');
    }
  }

  /// 認証フローの本体
  ///
  /// Gadgetbridge の XiaomiBleProtocolV2 に準拠した正しいフロー:
  ///   Step 0: 005e に Notify をサブスクライブ
  ///   Step 1: SESSION_CONFIG リクエストを送信（frameType=0x02, opcode=0x01）
  ///   Step 2: Band から SESSION_CONFIG レスポンスを受信（frameType=0x02, opcode=0x02）
  ///   Step 3: CMD_NONCE を送信（phoneNonce 16バイト）
  ///   Step 4: Band から watchNonce(16) + watchHmac(32) を受信
  ///   Step 5: HMAC-SHA256 + KDF でセッション鍵を導出し watchHmac を検証
  ///   Step 6: CMD_AUTH を送信（phoneHmac 32バイト）
  ///   Step 7: Band から認証完了レスポンスを受信
  ///
  /// 注意: SESSION_CONFIG ハンドシェイクなしに CMD_NONCE を送っても Band は無視する。
  Future<AuthResult> _doAuthenticate(
      String deviceId, String authKeyHex) async {
    _sequence = 0; // 認証セッション開始時にシーケンス番号をリセット
    final authKey = _hexToBytes(authKeyHex);
    if (authKey == null) {
      return const AuthFailure('Auth Keyの形式が不正です（32文字HEX文字列が必要）');
    }
    if (authKey.length != 16) {
      return AuthFailure(
        'Auth Keyのバイト長が不正です（16バイト必要、実際: ${authKey.length}バイト）',
      );
    }

    // 005e = RX（受信：subscribe用）、005f = TX（送信：write用）
    final rxChar = QualifiedCharacteristic(
      serviceId: Uuid.parse(BandServiceUUIDs.main),
      characteristicId: Uuid.parse(BandCharacteristicUUIDs.rxChannel),
      deviceId: deviceId,
    );
    final txChar = QualifiedCharacteristic(
      serviceId: Uuid.parse(BandServiceUUIDs.main),
      characteristicId: Uuid.parse(BandCharacteristicUUIDs.txChannel),
      deviceId: deviceId,
    );

    // phoneNonce (16バイト) を先に生成しておく
    final phoneNonce = _generateNonce(16);
    final completer = Completer<AuthResult>();
    late StreamSubscription<List<int>> subscription;

    // ステートマシンフラグ
    bool sessionConfigDone = false;
    SessionKeys? pendingKeys;

    // Step 0: 005e (RX) に Notify をサブスクライブしてから送信する
    subscription = _ble
        .subscribeToCharacteristic(rxChar)
        .listen(
          (data) async {
            if (data.isEmpty || completer.isCompleted) return;

            try {
              final packet = Sppv2Packet.parse(data);
              if (packet == null) {
                // ignore: avoid_print
                print('[Auth] パース失敗 raw=${data.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
                return;
              }

              // ignore: avoid_print
              print('[Auth] 受信 frameType=0x${packet.frameType.toRadixString(16)} '
                  'channel=0x${packet.channelId.toRadixString(16)} '
                  'data len=${packet.data.length}');

              // --- SESSION_CONFIG レスポンス処理 ---
              if (packet.frameType == Sppv2FrameType.sessionConfig &&
                  !sessionConfigDone) {
                // Bandからのセッション設定完了通知を受信
                sessionConfigDone = true;
                // ignore: avoid_print
                print('[Auth] SESSION_CONFIG 受信 → CMD_NONCE を送信');

                // Step 3: CMD_NONCE を送信
                await _sendNonceCommand(
                  txChar: txChar,
                  phoneNonce: phoneNonce,
                );
                return;
              }

              // --- 認証チャンネルのレスポンス処理 ---
              if (packet.channelId != Sppv2Channel.auth) return;

              final rawData = packet.data;
              if (rawData.isEmpty) return;

              // Protobuf デコード: Command { type(1), subtype(2), auth(3) }
              final parsed = _parseProtoCommand(rawData);
              if (parsed == null) {
                // ignore: avoid_print
                print('[Auth] Protobufデコード失敗 raw=${rawData.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
                return;
              }

              final type = parsed['type'] as int?;
              final subType = parsed['subtype'] as int?;

              // ignore: avoid_print
              print('[Auth] CMD受信 type=$type subtype=$subType');

              if (type != AuthCommands.authTypeV2) return;

              if (subType == AuthCommands.cmdNonce && pendingKeys == null) {
                // Step 4: watchNonce(16) + watchHmac(32) を受信
                // Protobuf: Auth.watchNonce { nonce(1): bytes, hmac(2): bytes }
                final watchNonce = parsed['watchNonce'] as Uint8List?;
                final watchHmac = parsed['watchHmac'] as Uint8List?;

                if (watchNonce == null || watchHmac == null) {
                  completer.complete(
                    const AuthFailure('CMD_NONCE応答: watchNonce/watchHmacが取得できません'),
                  );
                  return;
                }
                if (watchNonce.length != 16 || watchHmac.length != 32) {
                  completer.complete(
                    AuthFailure('CMD_NONCE応答のデータ長不正: nonce=${watchNonce.length} hmac=${watchHmac.length}'),
                  );
                  return;
                }

                // Step 5: セッション鍵を導出
                final keys = _deriveSessionKeys(
                  authKey: authKey,
                  phoneNonce: phoneNonce,
                  watchNonce: watchNonce,
                );
                pendingKeys = keys;

                // watchHmac を検証
                // expected = HMAC-SHA256(key=decryptionKey, msg=watchNonce+phoneNonce)
                final expected = _hmacSha256(
                  key: keys.decryptionKey,
                  message: Uint8List.fromList([...watchNonce, ...phoneNonce]),
                );

                if (!_constantTimeEqual(expected, watchHmac)) {
                  completer.complete(const AuthFailure(
                    'watchHmac 検証失敗（Auth Keyが間違っている可能性があります）',
                  ));
                  return;
                }

                // Step 6: CMD_AUTH コマンドを送信
                await _sendAuthCommand(
                  txChar: txChar,
                  encryptionKey: keys.encryptionKey,
                  phoneNonce: phoneNonce,
                  watchNonce: watchNonce,
                );
              } else if (subType == AuthCommands.cmdAuth &&
                  pendingKeys != null) {
                // Step 7: CMD_AUTH 応答 — 認証完了確認
                // Gadgetbridge準拠: status == 0（成功）または status == 1（成功）の両方を受け入れる
                // ファームウェアバージョンによって返す値が異なる可能性があるため。
                final status = parsed['status'] as int? ?? -1;
                if (status == 0 || status == 1) {
                  // ignore: avoid_print
                  print('[Auth] CMD_AUTH 成功 (status=$status)');
                  completer.complete(AuthSuccess(pendingKeys!));
                } else {
                  completer.complete(
                    AuthFailure('CMD_AUTH 認証失敗（status: $status）'),
                  );
                }
              }
            } catch (e) {
              if (!completer.isCompleted) {
                completer.complete(AuthFailure('認証レスポンス処理エラー: $e'));
              }
            }
          },
          onError: (Object e) {
            if (!completer.isCompleted) {
              completer.complete(AuthFailure('BLE受信エラー: $e'));
            }
          },
        );

    try {
      // Step 1: SESSION_CONFIG リクエストを送信する
      // subscribe完了後に送信するため、わずかに待機してBLE通知登録を確実にする
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await _sendSessionConfigRequest(txChar: txChar);
      // ignore: avoid_print
      print('[Auth] SESSION_CONFIG 送信完了 → Bandの応答を待機中...');

      // Band 9 のファームウェアによっては SESSION_CONFIG レスポンスを返さない場合がある。
      // 5秒待っても sessionConfigDone にならなければ CMD_NONCE を直接送信して認証を試みる。
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!completer.isCompleted && !sessionConfigDone) {
        // ignore: avoid_print
        print('[Auth] SESSION_CONFIG 応答なし → CMD_NONCE を直接送信（フォールバック）');
        sessionConfigDone = true;
        await _sendNonceCommand(txChar: txChar, phoneNonce: phoneNonce);
      }

      return await completer.future;
    } catch (e) {
      return AuthFailure('SESSION_CONFIG 送信エラー: $e');
    } finally {
      await subscription.cancel();
    }
  }

  // ----------------------------------------------------------------
  // Step 1: SESSION_CONFIG リクエスト送信（認証前ハンドシェイク）
  // ----------------------------------------------------------------

  /// SESSION_CONFIG リクエストを送信する
  ///
  /// Gadgetbridge の initializeDevice() が行う最初のパケット送信。
  /// このパケットへの応答を受信して初めて CMD_NONCE を送ることができる。
  Future<void> _sendSessionConfigRequest({
    required QualifiedCharacteristic txChar,
  }) async {
    final packet = Sppv2Packet.buildSessionConfig(sequence: _sequence++ & 0xFF);
    await _ble.writeCharacteristicWithoutResponse(
      txChar,
      value: packet.toList(),
    );
  }

  // ----------------------------------------------------------------
  // Step 3: CMD_NONCE コマンド送信
  // ----------------------------------------------------------------

  /// CMD_NONCE コマンドを送信する
  ///
  /// Xiaomi Protobuf（xiaomi.proto）に従ったコマンド構造:
  ///   Command {
  ///     type: 1         (field 1, varint)
  ///     subtype: 26     (field 2, varint = CMD_NONCE)
  ///     auth {          (field 3, length-delimited)
  ///       phoneNonce {  (field 30, length-delimited)
  ///         nonce: [16バイト]  (field 1, bytes)
  ///       }
  ///     }
  ///   }
  Future<void> _sendNonceCommand({
    required QualifiedCharacteristic txChar,
    required Uint8List phoneNonce,
  }) async {
    // Protobuf手動エンコード
    // PhoneNonce { nonce(field=1, bytes): phoneNonce }
    final phoneNonceMsg = _protoBytes(field: 1, value: phoneNonce);

    // Auth { phoneNonce(field=30, message): phoneNonceMsg }
    final authMsg = _protoMessage(field: 30, value: phoneNonceMsg);

    // Command { type(field=1)=1, subtype(field=2)=26, auth(field=3): authMsg }
    final commandData = <int>[
      ..._protoVarint(field: 1, value: 1),                  // type = 1
      ..._protoVarint(field: 2, value: AuthCommands.cmdNonce), // subtype = 26
      ..._protoMessage(field: 3, value: authMsg),            // auth
    ];

    final packet = Sppv2Packet.buildCommand(
      channelId: Sppv2Channel.auth,
      payloadType: Sppv2PayloadType.plaintext,
      data: commandData,
      sequence: _sequence++ & 0xFF,
    );

    await _ble.writeCharacteristicWithoutResponse(
      txChar,
      value: packet.toList(),
    );
  }

  // ----------------------------------------------------------------
  // Step 5: CMD_AUTH コマンド送信
  // ----------------------------------------------------------------

  /// CMD_AUTH コマンドを送信する
  ///
  /// Xiaomi Protobuf（xiaomi.proto）に従ったコマンド構造:
  ///   Command {
  ///     type: 1         (field 1, varint)
  ///     subtype: 27     (field 2, varint = CMD_AUTH)
  ///     auth {          (field 3, length-delimited)
  ///       authStep3 {   (field 32, length-delimited)
  ///         encryptedNonces: phoneHmac(32バイト)  (field 1, bytes)
  ///         encryptedDeviceInfo: [空]              (field 2, bytes)
  ///       }
  ///     }
  ///   }
  ///
  /// phoneHmac = HMAC-SHA256(key=encryptionKey, msg=phoneNonce+watchNonce)
  Future<void> _sendAuthCommand({
    required QualifiedCharacteristic txChar,
    required Uint8List encryptionKey,
    required Uint8List phoneNonce,
    required Uint8List watchNonce,
  }) async {
    final phoneHmac = _hmacSha256(
      key: encryptionKey,
      message: Uint8List.fromList([...phoneNonce, ...watchNonce]),
    );

    // AuthStep3 { encryptedNonces(field=1): phoneHmac, encryptedDeviceInfo(field=2): [] }
    final authStep3Msg = <int>[
      ..._protoBytes(field: 1, value: phoneHmac),
      ..._protoBytes(field: 2, value: Uint8List(0)),
    ];

    // Auth { authStep3(field=32, message): authStep3Msg }
    final authMsg = _protoMessage(field: 32, value: authStep3Msg);

    // Command { type(field=1)=1, subtype(field=2)=27, auth(field=3): authMsg }
    final commandData = <int>[
      ..._protoVarint(field: 1, value: 1),                  // type = 1
      ..._protoVarint(field: 2, value: AuthCommands.cmdAuth), // subtype = 27
      ..._protoMessage(field: 3, value: authMsg),            // auth
    ];

    final packet = Sppv2Packet.buildCommand(
      channelId: Sppv2Channel.auth,
      payloadType: Sppv2PayloadType.plaintext,
      data: commandData,
      sequence: _sequence++ & 0xFF,
    );

    await _ble.writeCharacteristicWithoutResponse(
      txChar,
      value: packet.toList(),
    );
  }

  // ----------------------------------------------------------------
  // Protobuf 手動エンコードユーティリティ
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // Protobuf 手動デコードユーティリティ
  // ----------------------------------------------------------------

  /// 受信したProtobufバイト列をデコードして認証情報を取り出す
  ///
  /// Command { type(1), subtype(2), auth(3) } を解析する。
  /// auth フィールドからは watchNonce, watchHmac, status を取り出す。
  ///
  /// 戻り値マップのキー:
  ///   'type'       : int  — Command.type
  ///   'subtype'    : int  — Command.subtype
  ///   'status'     : int  — Auth.status
  ///   'watchNonce' : Uint8List — Auth.watchNonce.nonce
  ///   'watchHmac'  : Uint8List — Auth.watchNonce.hmac
  ///
  /// デコード失敗時は null を返す。
  Map<String, dynamic>? _parseProtoCommand(Uint8List data) {
    try {
      final result = <String, dynamic>{};
      var pos = 0;

      while (pos < data.length) {
        final tagResult = _decodeVarint(data, pos);
        if (tagResult == null) break;
        final tag = tagResult.$1;
        pos = tagResult.$2;

        final fieldNumber = tag >> 3;
        final wireType = tag & 0x7;

        if (wireType == 0) {
          // varint
          final valResult = _decodeVarint(data, pos);
          if (valResult == null) break;
          final val = valResult.$1;
          pos = valResult.$2;
          if (fieldNumber == 1) result['type'] = val;
          if (fieldNumber == 2) result['subtype'] = val;
        } else if (wireType == 2) {
          // length-delimited
          final lenResult = _decodeVarint(data, pos);
          if (lenResult == null) break;
          final len = lenResult.$1;
          pos = lenResult.$2;
          if (pos + len > data.length) break;
          final bytes = Uint8List.fromList(data.sublist(pos, pos + len));
          pos += len;

          if (fieldNumber == 3) {
            // Auth メッセージをネストデコード
            _parseProtoAuth(bytes, result);
          }
        } else {
          // 未対応のwireTypeはスキップできないので終了
          break;
        }
      }

      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }

  /// Auth Protobufメッセージを解析してresultに格納する
  ///
  /// Auth { userId(7), status(8), watchNonce(31) { nonce(1), hmac(2) } }
  void _parseProtoAuth(Uint8List data, Map<String, dynamic> result) {
    var pos = 0;
    while (pos < data.length) {
      final tagResult = _decodeVarint(data, pos);
      if (tagResult == null) break;
      final tag = tagResult.$1;
      pos = tagResult.$2;

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;

      if (wireType == 0) {
        final valResult = _decodeVarint(data, pos);
        if (valResult == null) break;
        final val = valResult.$1;
        pos = valResult.$2;
        if (fieldNumber == 8) result['status'] = val; // Auth.status
      } else if (wireType == 2) {
        final lenResult = _decodeVarint(data, pos);
        if (lenResult == null) break;
        final len = lenResult.$1;
        pos = lenResult.$2;
        if (pos + len > data.length) break;
        final bytes = Uint8List.fromList(data.sublist(pos, pos + len));
        pos += len;

        if (fieldNumber == 31) {
          // WatchNonce { nonce(1): bytes, hmac(2): bytes }
          _parseProtoWatchNonce(bytes, result);
        }
      } else {
        break;
      }
    }
  }

  /// WatchNonce Protobufメッセージを解析してresultに格納する
  void _parseProtoWatchNonce(Uint8List data, Map<String, dynamic> result) {
    var pos = 0;
    while (pos < data.length) {
      final tagResult = _decodeVarint(data, pos);
      if (tagResult == null) break;
      final tag = tagResult.$1;
      pos = tagResult.$2;

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;

      if (wireType == 2) {
        final lenResult = _decodeVarint(data, pos);
        if (lenResult == null) break;
        final len = lenResult.$1;
        pos = lenResult.$2;
        if (pos + len > data.length) break;
        final bytes = Uint8List.fromList(data.sublist(pos, pos + len));
        pos += len;

        if (fieldNumber == 1) result['watchNonce'] = bytes;
        if (fieldNumber == 2) result['watchHmac'] = bytes;
      } else if (wireType == 0) {
        final valResult = _decodeVarint(data, pos);
        if (valResult == null) break;
        pos = valResult.$2;
      } else {
        break;
      }
    }
  }

  /// Protobuf varint を指定オフセットからデコードする
  ///
  /// 戻り値: (デコード値, 次のオフセット) または null（デコード失敗）
  (int, int)? _decodeVarint(Uint8List data, int offset) {
    var value = 0;
    var shift = 0;
    var pos = offset;
    while (pos < data.length) {
      final b = data[pos++];
      value |= (b & 0x7F) << shift;
      shift += 7;
      if ((b & 0x80) == 0) return (value, pos);
      if (shift >= 63) return null; // オーバーフロー防止
    }
    return null;
  }

  /// Protobuf varint フィールドをエンコードする
  ///
  /// wire type 0: varint
  /// tag = (field_number << 3) | 0
  List<int> _protoVarint({required int field, required int value}) {
    final tag = (field << 3) | 0; // wire type 0 = varint
    final result = <int>[];
    // タグをvarintエンコード
    result.addAll(_encodeVarint(tag));
    // 値をvarintエンコード
    result.addAll(_encodeVarint(value));
    return result;
  }

  /// Protobuf bytes フィールドをエンコードする
  ///
  /// wire type 2: length-delimited
  List<int> _protoBytes({required int field, required Uint8List value}) {
    final tag = (field << 3) | 2; // wire type 2 = length-delimited
    final result = <int>[];
    result.addAll(_encodeVarint(tag));
    result.addAll(_encodeVarint(value.length));
    result.addAll(value);
    return result;
  }

  /// Protobuf embedded message フィールドをエンコードする
  ///
  /// wire type 2: length-delimited（メッセージもbytesと同じwire type）
  List<int> _protoMessage({required int field, required List<int> value}) {
    final tag = (field << 3) | 2; // wire type 2 = length-delimited
    final result = <int>[];
    result.addAll(_encodeVarint(tag));
    result.addAll(_encodeVarint(value.length));
    result.addAll(value);
    return result;
  }

  /// 整数をProtobuf varint形式にエンコードする
  ///
  /// [value] は 0 以上の整数でなければならない。
  /// Protobuf の field number やバイト長は常に非負値なので、負の値は不正な入力。
  List<int> _encodeVarint(int value) {
    assert(value >= 0, '_encodeVarint: 負の値は非サポート (value=$value)');
    if (value < 0) return [0]; // assertが無効なreleaseビルドでも安全に終了する
    final result = <int>[];
    while (value > 0x7F) {
      result.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    result.add(value & 0x7F);
    return result;
  }

  // ----------------------------------------------------------------
  // セッション鍵導出 (HMAC-SHA256 + KDF)
  // ----------------------------------------------------------------

  /// セッション鍵を導出する
  ///
  /// Step 1: 中間鍵を計算
  ///   intermediate = HMAC-SHA256(key: authKey, msg: phoneNonce + watchNonce)
  ///
  /// Step 2: KDF("miwear-auth") で64バイトの鍵材料を生成
  ///   block1 = HMAC-SHA256(key: intermediate, msg: "miwear-auth" + 0x01)
  ///   block2 = HMAC-SHA256(key: intermediate, msg: block1 + "miwear-auth" + 0x02)
  ///   keyMaterial = block1(32バイト) + block2(32バイト)
  ///
  /// Step 3: 鍵材料を各キーに割り当て
  ///   decryptionKey   = keyMaterial[0..15]
  ///   encryptionKey   = keyMaterial[16..31]
  ///   decryptionNonce = keyMaterial[32..35]
  ///   encryptionNonce = keyMaterial[36..39]
  SessionKeys _deriveSessionKeys({
    required Uint8List authKey,
    required Uint8List phoneNonce,
    required Uint8List watchNonce,
  }) {
    // 中間鍵: HMAC(key=phoneNonce||watchNonce, msg=authKey)
    // ※Gadgetbridge準拠: keyはnonce連結、messageがauthKey
    final intermediate = _hmacSha256(
      key: Uint8List.fromList([...phoneNonce, ...watchNonce]),
      message: authKey,
    );

    // KDF: "miwear-auth" ラベルを使った HKDF 風の鍵展開
    const label = 'miwear-auth';
    final labelBytes = label.codeUnits;

    // block1 = HMAC-SHA256(key: intermediate, msg: "miwear-auth" + 0x01)
    final block1 = _hmacSha256(
      key: intermediate,
      message: Uint8List.fromList([...labelBytes, 0x01]),
    );

    // block2 = HMAC-SHA256(key: intermediate, msg: block1 + "miwear-auth" + 0x02)
    final block2 = _hmacSha256(
      key: intermediate,
      message: Uint8List.fromList([...block1, ...labelBytes, 0x02]),
    );

    // keyMaterial = block1(32) + block2(32) = 64バイト
    final keyMaterial = Uint8List(64)
      ..setRange(0, 32, block1)
      ..setRange(32, 64, block2);

    return SessionKeys(
      decryptionKey: Uint8List.fromList(keyMaterial.sublist(0, 16)),
      encryptionKey: Uint8List.fromList(keyMaterial.sublist(16, 32)),
      decryptionNonce: Uint8List.fromList(keyMaterial.sublist(32, 36)),
      encryptionNonce: Uint8List.fromList(keyMaterial.sublist(36, 40)),
    );
  }

  // ----------------------------------------------------------------
  // AES-CCM 暗号化/復号 (認証後の通信に使用)
  // ----------------------------------------------------------------

  /// AES-CCM でデータを暗号化する
  ///
  /// [key]       : 暗号化キー (16バイト)
  /// [nonce]     : ノンス (12バイト) — SessionKeys.buildEncryptionNonce() で生成
  /// [plaintext] : 暗号化するデータ
  /// [tagLength] : MACタグ長（バイト）。デフォルト: 4
  ///
  /// 暗号化テキスト（末尾にMACタグを含む）を返す。
  /// 失敗時は null を返す。
  static Uint8List? encryptAesCcm({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    int tagLength = 4,
  }) {
    try {
      final params = pc.AEADParameters(
        pc.KeyParameter(key),
        tagLength * 8, // タグ長はビット単位
        nonce,
        Uint8List(0), // 追加認証データなし
      );

      final cipher = pc.CCMBlockCipher(pc.AESEngine());
      cipher.init(true, params); // true = 暗号化
      return cipher.process(plaintext);
    } catch (e) {
      return null;
    }
  }

  /// AES-CCM でデータを復号する
  ///
  /// [key]        : 復号キー (16バイト)
  /// [nonce]      : ノンス (12バイト) — SessionKeys.buildDecryptionNonce() で生成
  /// [ciphertext] : 復号するデータ（末尾にMACタグを含む）
  /// [tagLength]  : MACタグ長（バイト）。デフォルト: 4
  ///
  /// 平文を返す。MACタグ検証失敗または復号失敗時は null を返す。
  static Uint8List? decryptAesCcm({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    int tagLength = 4,
  }) {
    try {
      final params = pc.AEADParameters(
        pc.KeyParameter(key),
        tagLength * 8,
        nonce,
        Uint8List(0),
      );

      final cipher = pc.CCMBlockCipher(pc.AESEngine());
      cipher.init(false, params); // false = 復号
      return cipher.process(ciphertext);
    } catch (e) {
      return null;
    }
  }

  // ----------------------------------------------------------------
  // ユーティリティ
  // ----------------------------------------------------------------

  /// HMAC-SHA256 を計算する
  Uint8List _hmacSha256({
    required Uint8List key,
    required Uint8List message,
  }) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(message);
    return Uint8List.fromList(digest.bytes);
  }

  /// 定数時間比較（タイミング攻撃対策）
  bool _constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// 安全なランダムバイト列を生成する
  Uint8List _generateNonce(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// HEX文字列をバイト列に変換する
  ///
  /// スペース・改行を除去してから変換する。
  /// 長さが偶数でない、または無効な文字を含む場合は null を返す。
  static Uint8List? _hexToBytes(String hex) {
    try {
      final clean = hex.replaceAll(RegExp(r'\s+'), '');
      if (clean.length % 2 != 0) return null;

      final bytes = Uint8List(clean.length ~/ 2);
      for (var i = 0; i < clean.length; i += 2) {
        bytes[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
      }
      return bytes;
    } catch (e) {
      return null;
    }
  }
}
