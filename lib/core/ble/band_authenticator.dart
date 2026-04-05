import 'dart:async';
import 'dart:io' show Platform;
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

  /// SPPv2 送信パケットのシーケンス番号カウンター
  ///
  /// Gadgetbridge: XiaomiSppProtocolV2.packetSequenceCounter
  /// 各送信パケットごとにインクリメントし、認証セッション開始時にリセットする。
  int _sendSequence = 0;

  BandAuthenticator(this._ble);

  /// 認証中に蓄積された診断ログ（BLE切断競合時のデバッグ用）
  List<String> lastDiagLog = [];

  /// Band 9 との V2認証を行い、SessionKeys を含む AuthResult を返す
  ///
  /// [deviceId]  : 接続済みデバイスのID（MACアドレス）
  /// [authKeyHex]: 32文字のHEX文字列（16バイト）
  /// タイムアウトは30秒。
  Future<AuthResult> authenticateV2(String deviceId, String authKeyHex) async {
    final diagLog = <String>[];
    lastDiagLog = diagLog; // BLE切断時でもdiagLogを参照できるよう保存
    final startTime = DateTime.now();

    String diagTimestamp() {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      return '+${elapsed}ms';
    }

    try {
      return await _doAuthenticate(deviceId, authKeyHex, diagLog, diagTimestamp)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      diagLog.add('${diagTimestamp()} [TIMEOUT] 30秒タイムアウト発生');
      final diagText = diagLog.join('\n');
      return AuthFailure(
        '認証タイムアウト（30秒）\n\n'
        '── 診断ログ ──\n$diagText',
      );
    } catch (e) {
      diagLog.add('${diagTimestamp()} [ERROR] 例外: $e');
      final diagText = diagLog.join('\n');
      return AuthFailure('認証エラー: $e\n\n── 診断ログ ──\n$diagText');
    }
  }

  /// 認証フローの本体
  ///
  /// 重要: QualifiedCharacteristic ではなく、getDiscoveredServices() から取得した
  /// 実際の Characteristic オブジェクトを直接使用する。
  /// これにより、flutter_reactive_ble の内部UUID解決やinstanceIDマッチングの
  /// 問題を回避し、iOS CoreBluetoothとの確実な通信を保証する。
  ///
  /// Gadgetbridge の XiaomiBleProtocolV2 に準拠したフロー:
  ///   Step 0: 005e に Notify をサブスクライブ
  ///   Step 1: SESSION_CONFIG リクエストを送信
  ///   Step 2: Band から SESSION_CONFIG レスポンスを受信
  ///   Step 3: CMD_NONCE を送信（phoneNonce 16バイト）
  ///   Step 4: Band から watchNonce(16) + watchHmac(32) を受信
  ///   Step 5: HMAC-SHA256 + KDF でセッション鍵を導出し watchHmac を検証
  ///   Step 6: CMD_AUTH を送信（phoneHmac 32バイト）
  ///   Step 7: Band から認証完了レスポンスを受信
  Future<AuthResult> _doAuthenticate(
    String deviceId,
    String authKeyHex,
    List<String> diagLog,
    String Function() ts,
  ) async {
    final authKey = _hexToBytes(authKeyHex);
    if (authKey == null) {
      return const AuthFailure('Auth Keyの形式が不正です（32文字HEX文字列が必要）');
    }

    // シーケンス番号をリセット（新しい認証セッション）
    _sendSequence = 0;

    diagLog.add('${ts()} [START] 認証開始 device=$deviceId');

    // --- getDiscoveredServices から実際の Characteristic オブジェクトを取得 ---
    // QualifiedCharacteristic（ハードコードUUID）の代わりに、
    // iOSが実際に発見したCharacteristicオブジェクトを直接使用する。
    // これにより instanceID のマッチング問題やサイレント失敗を回避する。
    Characteristic? rxCharObj;
    Characteristic? txCharObj;
    try {
      final services = await _ble.getDiscoveredServices(deviceId)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('getDiscoveredServices タイムアウト（10秒）'),
          );
      // 全サービスUUIDを診断ログに記録（fe95が見つからない場合のデバッグ用）
      final serviceIdList = services.map((s) => s.id.toString()).join(', ');
      diagLog.add('${ts()} [DISC] サービス数=${services.length}: $serviceIdList');
      // ignore: avoid_print
      print('[Auth] サービスディスカバリ: ${services.length}サービス検出: $serviceIdList');

      // UUID比較: iOSはUUIDを大文字・短縮形・フルUUIDなど様々な形式で返す。
      // expanded や文字列の完全一致は環境依存で失敗することがあるため、
      // UUID文字列からダッシュを除いた16進数に 'fe95'/'005e'/'005f' が
      // 含まれるかどうかで判定する（大文字小文字・フォーマット非依存）。
      bool uuidContains(Uuid id, String shortHex) {
        final normalized = id.toString().replaceAll('-', '').toLowerCase();
        return normalized.contains(shortHex.toLowerCase());
      }

      for (final service in services) {
        // ignore: avoid_print
        print('[Auth] サービス: ${service.id}');
        if (uuidContains(service.id, 'fe95')) {
          diagLog.add('${ts()} [DISC] fe95サービス発見 (char数=${service.characteristics.length})');
          // ignore: avoid_print
          print('[Auth] fe95サービス発見 (${service.characteristics.length}個のchar)');
          for (final char in service.characteristics) {
            // ignore: avoid_print
            print('[Auth]   char: ${char.id} '
                'notify=${char.isNotifiable} '
                'writeNoResp=${char.isWritableWithoutResponse} '
                'writeResp=${char.isWritableWithResponse}');
            if (uuidContains(char.id, '005e')) rxCharObj = char;
            if (uuidContains(char.id, '005f')) txCharObj = char;
          }
          diagLog.add('${ts()} [DISC] char検索結果: rx=${rxCharObj != null} tx=${txCharObj != null}');
          break;
        }
      }
    } catch (e) {
      diagLog.add('${ts()} [ERROR] サービスディスカバリ失敗: $e');
      return AuthFailure('サービスディスカバリ失敗: $e\n\n── 診断ログ ──\n${diagLog.join('\n')}');
    }

    if (rxCharObj == null || txCharObj == null) {
      diagLog.add('${ts()} [ERROR] char未検出 rx=${rxCharObj != null} tx=${txCharObj != null}');
      // [UUID失効] マーカーを付与することで、ble_manager.dart が
      // 「別デバイスに接続した」と判断して自動再スキャンをトリガーできる。
      return AuthFailure(
        '[UUID失効] 別のBLEデバイスに接続されました。'
        'fe95サービスが見つかりません '
        '(rx=${rxCharObj != null}, tx=${txCharObj != null})\n\n'
        '── 診断ログ ──\n${diagLog.join('\n')}',
      );
    }

    diagLog.add('${ts()} [DISC] 005e notify=${rxCharObj.isNotifiable} / '
        '005f writeNoResp=${txCharObj.isWritableWithoutResponse}');
    // ignore: avoid_print
    print('[Auth] 005e(RX): isNotifiable=${rxCharObj.isNotifiable}');
    // ignore: avoid_print
    print('[Auth] 005f(TX): writeNoResp=${txCharObj.isWritableWithoutResponse} '
        'writeResp=${txCharObj.isWritableWithResponse}');

    if (!rxCharObj.isNotifiable) {
      return const AuthFailure('005e キャラクタリスティックが notify 非対応です');
    }

    // phoneNonce (16バイト) を先に生成しておく
    final phoneNonce = _generateNonce(16);
    final completer = Completer<AuthResult>();
    late StreamSubscription<List<int>> subscription;

    // ステートマシンフラグ
    bool sessionConfigDone = false;
    SessionKeys? pendingKeys;
    Uint8List? savedWatchNonce; // CMD_NONCE再送時のCMD_AUTH再試行用

    // Step 0: Characteristic.subscribe() で直接 Notify をサブスクライブ
    // QualifiedCharacteristic 経由ではなく、実際のオブジェクトを使う
    diagLog.add('${ts()} [SUB] 005e subscribe開始...');
    // ignore: avoid_print
    print('[Auth] 005e (RX) にsubscribe開始（Characteristicオブジェクト直接使用）...');
    subscription = rxCharObj
        .subscribe()
        .listen(
          (data) async {
            final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
            diagLog.add('${ts()} [RECV] ${data.length}B');
            // ignore: avoid_print
            print('[Auth] BLE受信 ${data.length}バイト raw=$hex');
            if (data.isEmpty || completer.isCompleted) return;

            try {
              final packet = Sppv2Packet.parse(data);
              if (packet == null) {
                // ignore: avoid_print
                print('[Auth] SPPv2パース失敗（rawデータは上記参照）');
                return;
              }

              // ignore: avoid_print
              print('[Auth] 受信 frameType=0x${packet.frameType.toRadixString(16)} '
                  'channel=0x${packet.channelId.toRadixString(16)} '
                  'data len=${packet.data.length}');

              // --- SESSION_CONFIG レスポンス処理 ---
              if (packet.frameType == Sppv2FrameType.sessionConfig &&
                  !sessionConfigDone) {
                sessionConfigDone = true;
                diagLog.add('${ts()} [OK] SESSION_CONFIG応答受信 → CMD_NONCE送信');
                // ignore: avoid_print
                print('[Auth] SESSION_CONFIG 受信 → CMD_NONCE を送信');
                await _sendNonceCommand(txChar: txCharObj!, phoneNonce: phoneNonce);
                diagLog.add('${ts()} [OK] CMD_NONCE送信完了 → watchNonce応答待ち');
                return;
              }

              // --- DATAパケットに対してACKを返す ---
              // Gadgetbridge: XiaomiSppProtocolV2.processPacket() の sendAck() に相当。
              // ACKを返さないと Band は前のパケットが届いていないと判断し、
              // CMD_NONCE を繰り返し再送する。
              if (packet.frameType == Sppv2FrameType.command) {
                final ackPacket = Sppv2Packet.buildAck(sequence: packet.sequence);
                diagLog.add('${ts()} [ACK] seq=${packet.sequence} に ACK送信');
                // ignore: avoid_print
                print('[Auth] ACK送信 seq=${packet.sequence}');
                try {
                  await txCharObj!.write(ackPacket.toList(), withResponse: false);
                } catch (e) {
                  diagLog.add('${ts()} [WARN] ACK送信失敗: $e');
                  // ignore: avoid_print
                  print('[Auth] ACK送信失敗: $e');
                }
              }

              // --- 認証チャンネルのレスポンス処理 ---
              if (packet.channelId != Sppv2Channel.auth) {
                diagLog.add('${ts()} [SKIP] authチャンネル以外: channel=0x${packet.channelId.toRadixString(16)}');
                return;
              }

              final rawData = packet.data;
              if (rawData.isEmpty) return;

              final parsed = _parseProtoCommand(rawData);
              if (parsed == null) {
                diagLog.add('${ts()} [WARN] Protobufデコード失敗');
                // ignore: avoid_print
                print('[Auth] Protobufデコード失敗 raw=${rawData.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
                return;
              }

              final type = parsed['type'] as int?;
              final subType = parsed['subtype'] as int?;
              diagLog.add('${ts()} [CMD] type=$type subtype=$subType');
              // ignore: avoid_print
              print('[Auth] CMD受信 type=$type subtype=$subType');

              if (type != AuthCommands.authTypeV2) return;

              if (subType == AuthCommands.cmdNonce) {
                if (pendingKeys == null) {
                  // 初回: watchNonce+watchHmac を受信し、鍵を導出してCMD_AUTHを送信
                  final watchNonce = parsed['watchNonce'] as Uint8List?;
                  final watchHmac = parsed['watchHmac'] as Uint8List?;

                  if (watchNonce == null || watchHmac == null) {
                    diagLog.add('${ts()} [ERROR] CMD_NONCE応答にnonce/hmacなし');
                    completer.complete(
                      AuthFailure('CMD_NONCE応答: watchNonce/watchHmacが取得できません\n\n── 診断ログ ──\n${diagLog.join('\n')}'),
                    );
                    return;
                  }
                  if (watchNonce.length != 16 || watchHmac.length != 32) {
                    diagLog.add('${ts()} [ERROR] データ長不正 nonce=${watchNonce.length} hmac=${watchHmac.length}');
                    completer.complete(
                      AuthFailure('CMD_NONCE応答のデータ長不正: nonce=${watchNonce.length} hmac=${watchHmac.length}\n\n── 診断ログ ──\n${diagLog.join('\n')}'),
                    );
                    return;
                  }

                  diagLog.add('${ts()} [OK] watchNonce(${watchNonce.length}B)+watchHmac(${watchHmac.length}B)受信 → 鍵導出...');
                  final keys = _deriveSessionKeys(
                    authKey: authKey,
                    phoneNonce: phoneNonce,
                    watchNonce: watchNonce,
                  );
                  pendingKeys = keys;
                  savedWatchNonce = watchNonce; // 再送時のために保存

                  final expected = _hmacSha256(
                    key: keys.decryptionKey,
                    message: Uint8List.fromList([...watchNonce, ...phoneNonce]),
                  );

                  if (!_constantTimeEqual(expected, watchHmac)) {
                    diagLog.add('${ts()} [ERROR] watchHmac検証失敗（Auth Key不正の可能性）');
                    completer.complete(const AuthFailure(
                      'watchHmac 検証失敗（Auth Keyが間違っている可能性があります）',
                    ));
                    return;
                  }

                  diagLog.add('${ts()} [OK] watchHmac検証成功 → CMD_AUTH送信...');
                  await _sendAuthCommand(
                    txChar: txCharObj!,
                    encryptionKey: keys.encryptionKey,
                    phoneNonce: phoneNonce,
                    watchNonce: watchNonce,
                    keys: keys,
                    diagLog: diagLog,
                  );
                  diagLog.add('${ts()} [OK] CMD_AUTH送信完了 → 認証結果待ち');
                } else {
                  // Band が CMD_NONCE を再送してきた = CMD_AUTH が届いていない
                  // write-without-response はパケットロストがあるため再送する
                  diagLog.add('${ts()} [RETRY] CMD_NONCE再送受信 → CMD_AUTH再送...');
                  // ignore: avoid_print
                  print('[Auth] CMD_NONCE再送受信 → CMD_AUTH再送');
                  await _sendAuthCommand(
                    txChar: txCharObj!,
                    encryptionKey: pendingKeys!.encryptionKey,
                    phoneNonce: phoneNonce,
                    watchNonce: savedWatchNonce!,
                    keys: pendingKeys!,
                    diagLog: diagLog,
                  );
                  diagLog.add('${ts()} [RETRY] CMD_AUTH再送完了 → 認証結果待ち');
                }
              } else if (subType == AuthCommands.cmdAuth &&
                  pendingKeys != null) {
                diagLog.add('[DBG] AUTH resp raw=${rawData.map((b) => b.toRadixString(16).padLeft(2, "0")).join()}');
                final status = parsed['status'] as int? ?? -1;
                diagLog.add('[DBG] AUTH status=$status');
                if (status == 0) {
                  diagLog.add('${ts()} [SUCCESS] 認証成功 (status=0)');
                  completer.complete(AuthSuccess(pendingKeys!));
                } else {
                  diagLog.add('${ts()} [ERROR] CMD_AUTH失敗 status=$status');
                  completer.complete(
                    AuthFailure('CMD_AUTH 認証失敗（status: $status）\n\n── 診断ログ ──\n${diagLog.join('\n')}'),
                  );
                }
              }
            } catch (e) {
              diagLog.add('${ts()} [ERROR] 受信処理例外: $e');
              if (!completer.isCompleted) {
                completer.complete(AuthFailure('認証レスポンス処理エラー: $e\n\n── 診断ログ ──\n${diagLog.join('\n')}'));
              }
            }
          },
          onError: (Object e) {
            diagLog.add('${ts()} [ERROR] BLE onError: $e');
            // ignore: avoid_print
            print('[Auth] BLE subscribe onError: $e');
            if (!completer.isCompleted) {
              completer.complete(AuthFailure('BLE受信エラー: $e\n\n── 診断ログ ──\n${diagLog.join('\n')}'));
            }
          },
        );

    diagLog.add('${ts()} [SUB] subscribe登録完了 → 3秒待機（CCCD書き込み完了待ち）...');
    // ignore: avoid_print
    print('[Auth] 005e subscribe完了 → 3秒待機後にSESSION_CONFIG送信');

    try {
      // Step 1: SESSION_CONFIG リクエストを送信する
      // subscribe後にCCCD書き込み（setNotifyValue）が完了するまで十分待機する。
      // iOSではbondingデバイスのCCCD書き込みに暗号化ネゴシエーションが加わるため、
      // 3秒待機する（1秒では不足することがある）。
      await Future<void>.delayed(const Duration(seconds: 3));
      diagLog.add('${ts()} [SEND] SESSION_CONFIG送信開始...');
      await _sendSessionConfigRequest(txChar: txCharObj);
      diagLog.add('${ts()} [SEND] SESSION_CONFIG送信完了 → Band応答待ち...');
      // ignore: avoid_print
      print('[Auth] SESSION_CONFIG 送信完了 → Bandの応答を待機中...');

      // SESSION_CONFIG無応答フォールバック:
      // 10秒待っても応答がなければ認証失敗として completer を完了させる。
      // （CMD_NONCEを直接送っても Band 9 が無視するため、切断→再接続に任せる）
      Future<void>.delayed(const Duration(seconds: 10), () {
        if (!completer.isCompleted && !sessionConfigDone) {
          diagLog.add('${ts()} [TIMEOUT] SESSION_CONFIG無応答（10秒）');
          // ignore: avoid_print
          print('[Auth] SESSION_CONFIG応答なし（10秒経過）→ 認証失敗として終了し再接続へ');
          completer.complete(
            AuthFailure(
              'SESSION_CONFIG無応答（10秒）: Band 9が応答しません\n\n'
              '考えられる原因:\n'
              '・Mi Fitnessアプリが干渉している（Bluetoothをオフに）\n'
              '・Band 9のBluetooth設定をリセット（「デバイスを削除」）\n'
              '・Auth Keyが正しくない\n\n'
              '── 診断ログ ──\n${diagLog.join('\n')}',
            ),
          );
        }
      });

      return await completer.future;
    } catch (e) {
      diagLog.add('${ts()} [ERROR] SESSION_CONFIG送信例外: $e');
      return AuthFailure('SESSION_CONFIG 送信エラー: $e\n\n── 診断ログ ──\n${diagLog.join('\n')}');
    } finally {
      await subscription.cancel();
    }
  }

  // ----------------------------------------------------------------
  // Step 1: SESSION_CONFIG リクエスト送信（認証前ハンドシェイク）
  // ----------------------------------------------------------------

  /// SESSION_CONFIG リクエストを送信する（Characteristic オブジェクト版）
  ///
  /// Gadgetbridge の initializeSession() が行う最初のパケット送信。
  /// SESSION_CONFIG はシーケンス番号0で送信する（Gadgetbridge準拠）。
  Future<void> _sendSessionConfigRequest({
    required Characteristic txChar,
  }) async {
    final packet = Sppv2Packet.buildSessionConfig(sequence: 0);
    // 005fはwrite without responseのみ対応（withResponse: falseが必須）
    // ignore: avoid_print
    print('[Auth] SESSION_CONFIG write送信中 (${packet.length}バイト)...');
    await txChar.write(packet.toList(), withResponse: false);
    // ignore: avoid_print
    print('[Auth] SESSION_CONFIG write完了');
  }

  // ----------------------------------------------------------------
  // Step 3: CMD_NONCE コマンド送信
  // ----------------------------------------------------------------

  /// CMD_NONCE コマンドを送信する（Characteristic オブジェクト版）
  ///
  /// Gadgetbridge: XiaomiAuthService.startEncryptedHandshake() -> sendCommand("auth step 1")
  /// シーケンス番号は packetSequenceCounter からインクリメント取得する。
  Future<void> _sendNonceCommand({
    required Characteristic txChar,
    required Uint8List phoneNonce,
  }) async {
    final phoneNonceMsg = _protoBytes(field: 1, value: phoneNonce);
    final authMsg = _protoMessage(field: 30, value: phoneNonceMsg);
    final commandData = <int>[
      ..._protoVarint(field: 1, value: 1),
      ..._protoVarint(field: 2, value: AuthCommands.cmdNonce),
      ..._protoMessage(field: 3, value: authMsg),
    ];

    final seq = _sendSequence++;
    final packet = Sppv2Packet.buildCommand(
      channelId: Sppv2Channel.auth,
      payloadType: Sppv2PayloadType.plaintext,
      data: commandData,
      sequence: seq,
    );

    // ignore: avoid_print
    print('[Auth] CMD_NONCE送信 seq=$seq');
    await txChar.write(packet.toList(), withResponse: false);
  }

  // ----------------------------------------------------------------
  // Step 5: CMD_AUTH コマンド送信
  // ----------------------------------------------------------------

  /// CMD_AUTH コマンドを送信する（Characteristic オブジェクト版）
  ///
  /// Gadgetbridge: XiaomiAuthService.handleWatchNonce() -> sendCommand("auth step 2")
  ///
  /// AuthStep3 Protobuf 構造 (Gadgetbridge XiaomiProto.AuthStep3):
  ///   field 1: encryptedNonces = HMAC-SHA256(key=encryptionKey, msg=phoneNonce+watchNonce)
  ///   field 2: encryptedDeviceInfo = AES-CCM暗号化されたデバイス情報
  ///
  /// AuthDeviceInfo Protobuf 構造:
  ///   field 1: unknown1 = 0
  ///   field 2: phoneApiLevel (int)
  ///   field 3: phoneName (string)
  ///   field 4: unknown3 = 224
  ///   field 5: region (string, e.g. "JP")
  Future<void> _sendAuthCommand({
    required Characteristic txChar,
    required Uint8List encryptionKey,
    required Uint8List phoneNonce,
    required Uint8List watchNonce,
    required SessionKeys keys,
    required List<String> diagLog,
  }) async {
    // encryptedNonces = HMAC-SHA256(key=encryptionKey, msg=phoneNonce||watchNonce)
    // Gadgetbridge準拠: encryptionKey = keyMaterial[16:32]
    final encryptedNonces = _hmacSha256(
      key: keys.encryptionKey,
      message: Uint8List.fromList([...phoneNonce, ...watchNonce]),
    );

    // AuthDeviceInfo Protobuf を組み立てる
    // Gadgetbridge: XiaomiProto.AuthDeviceInfo
    final deviceName = Platform.isIOS ? 'iPhone' : 'Android';
    final apiLevel = Platform.isIOS ? 17 : 33; // iOS 17 / Android 13 相当
    const region = 'JP';
    final authDeviceInfo = <int>[
      ..._protoVarint(field: 1, value: 0),            // unknown1 = 0
      ..._protoFloat(field: 2, value: apiLevel),      // phoneApiLevel (float型: wire type 5)
      ..._protoString(field: 3, value: deviceName),   // phoneName
      ..._protoVarint(field: 4, value: 224),          // unknown3 = 224
      ..._protoString(field: 5, value: region),       // region
    ];

    // AES-CCM でデバイス情報を暗号化する
    // Gadgetbridge準拠: encryptionKey + encryptionNonce
    final encNonce = Uint8List(12);
    encNonce.setRange(0, 4, keys.encryptionNonce);
    // bytes 4-11: all zeros (packetId=0)

    final encryptedDeviceInfo = encryptAesCcm(
      key: keys.encryptionKey,
      nonce: encNonce,
      plaintext: Uint8List.fromList(authDeviceInfo),
    );

    // デバッグ: 送信データの詳細ログ
    diagLog.add('[DBG] encNonces=${encryptedNonces.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    diagLog.add('[DBG] devInfoPt=${authDeviceInfo.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    diagLog.add('[DBG] CCM: nonce=${encNonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join()} devInfo=${encryptedDeviceInfo == null ? "null!" : "${encryptedDeviceInfo.length}B"}');

    // AuthStep3: encryptedNonces(field 1) + encryptedDeviceInfo(field 2)
    final authStep3Msg = <int>[
      ..._protoBytes(field: 1, value: encryptedNonces),
      if (encryptedDeviceInfo != null)
        ..._protoBytes(field: 2, value: encryptedDeviceInfo),
    ];
    final authMsg = _protoMessage(field: 32, value: authStep3Msg);
    final commandData = <int>[
      ..._protoVarint(field: 1, value: 1),
      ..._protoVarint(field: 2, value: AuthCommands.cmdAuth),
      ..._protoMessage(field: 3, value: authMsg),
    ];

    final seq = _sendSequence++;
    final packet = Sppv2Packet.buildCommand(
      channelId: Sppv2Channel.auth,
      payloadType: Sppv2PayloadType.plaintext,
      data: commandData,
      sequence: seq,
    );

    diagLog.add('[DBG] AUTH pkt ${packet.length}B: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    await txChar.write(packet.toList(), withResponse: false);
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
        } else if (wireType == 1) {
          pos += 8; // 64-bit: スキップ
        } else if (wireType == 5) {
          pos += 4; // 32-bit: スキップ
        } else {
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
  /// CMD_AUTH応答: { step(1), userId(2), status(3) }
  /// CMD_NONCE応答: { step(1), watchNonce(31) { nonce(1), hmac(2) } }
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
        // Auth.statusはfield 3(失敗レスポンス)またはfield 8(成功レスポンス)に存在する可能性
        if (fieldNumber == 3 || fieldNumber == 8) {
          result['status'] ??= val; // 最初に見つかった値を使用
        }
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
        } else if (fieldNumber == 33) {
          // CMD_AUTH応答のネストされたメッセージ（status等を含む可能性）
          _parseProtoAuth(bytes, result);
        }
      } else if (wireType == 1) {
        // 64-bit fixed: スキップ
        pos += 8;
      } else if (wireType == 5) {
        // 32-bit fixed: スキップ
        pos += 4;
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

  /// Protobuf string フィールドをエンコードする
  ///
  /// wire type 2: length-delimited（stringもbytesと同じwire type）
  List<int> _protoString({required int field, required String value}) {
    final bytes = Uint8List.fromList(value.codeUnits);
    return _protoBytes(field: field, value: bytes);
  }

  /// Protobuf float フィールドをエンコードする
  ///
  /// wire type 5: 32-bit（float/fixed32/sfixed32）
  /// IEEE 754 single precision, little-endian
  List<int> _protoFloat({required int field, required int value}) {
    final tag = (field << 3) | 5; // wire type 5 = 32-bit
    final result = <int>[];
    result.addAll(_encodeVarint(tag));
    final bd = ByteData(4);
    bd.setFloat32(0, value.toDouble(), Endian.little);
    result.addAll(bd.buffer.asUint8List());
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
  List<int> _encodeVarint(int value) {
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
      // ignore: avoid_print
      print('[Auth] encryptAesCcm 例外: $e');
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
