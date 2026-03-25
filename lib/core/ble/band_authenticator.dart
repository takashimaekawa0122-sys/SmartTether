import 'dart:async';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'band_protocol.dart';

/// BLE認証の結果を表すシールドクラス
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  const AuthSuccess();
}

class AuthFailure extends AuthResult {
  final String error;
  const AuthFailure(this.error);
}

/// Xiaomi Smart Band 9 の AES-128-ECB Challenge-Response 認証
///
/// 認証フロー:
///   1. auth キャラクタリスティックを Subscribe
///   2. 0x02（認証番号要求）を Write
///   3. Notification で 16byte Challenge を受信
///   4. AES-128-ECB(authKey, challenge) で暗号化
///   5. 0x04 + 暗号文を Write
///   6. 応答 0x01 (authSuccess) で認証完了
///
/// 参考: Gadgetbridge MiBand2Support.java
class BandAuthenticator {
  final FlutterReactiveBle _ble;

  BandAuthenticator(this._ble);

  /// Band 9 との認証を行う
  ///
  /// [deviceId] : 接続済みデバイスのID（MACアドレス）
  /// [authKey]  : 16バイトのHEX文字列（例: "0123456789abcdef0123456789abcdef"）
  /// タイムアウトは5秒。
  Future<AuthResult> authenticate(String deviceId, String authKey) async {
    try {
      return await _doAuthenticate(deviceId, authKey)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return const AuthFailure('認証タイムアウト（5秒）');
    } catch (e) {
      return AuthFailure('認証エラー: $e');
    }
  }

  Future<AuthResult> _doAuthenticate(
      String deviceId, String authKey) async {
    // Band 9 は fe95/005e を使用する（旧: fee1/0009）
    // TODO: Band 9 V2プロトコル（HMAC-SHA256 + AES-CCM）への移行が必要
    final authCharacteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(BandServiceUUIDs.main),
      characteristicId: Uuid.parse(BandCharacteristicUUIDs.mainChannel),
      deviceId: deviceId,
    );

    // Step 1: Notification を Subscribe してレスポンスを待ち受ける
    final completer = Completer<AuthResult>();
    late StreamSubscription<List<int>> subscription;
    bool challengeReceived = false;

    subscription = _ble
        .subscribeToCharacteristic(authCharacteristic)
        .listen((data) async {
      if (data.isEmpty) return;

      try {
        if (!challengeReceived && data[0] == AuthCommands.requestAuthNumber) {
          // Step 3: Challenge（16バイト）を受信した
          if (data.length < 17) {
            completer.complete(
                const AuthFailure('Challengeデータが短すぎます'));
            return;
          }
          challengeReceived = true;
          final challenge = data.sublist(1, 17);

          // Step 4: AES-128-ECB で暗号化
          final encrypted = _encryptChallenge(authKey, challenge);
          if (encrypted == null) {
            completer.complete(
                const AuthFailure('AES暗号化に失敗しました'));
            return;
          }

          // Step 5: 0x04 + 暗号文を Write
          final payload = [AuthCommands.sendEncryptedNumber, ...encrypted];
          await _ble.writeCharacteristicWithoutResponse(
            authCharacteristic,
            value: payload,
          );
        } else if (data[0] == AuthCommands.authSuccess) {
          // Step 6: 認証成功
          if (!completer.isCompleted) {
            completer.complete(const AuthSuccess());
          }
        } else if (challengeReceived) {
          // 認証失敗レスポンス
          if (!completer.isCompleted) {
            completer.complete(AuthFailure('認証失敗（応答: 0x${data[0].toRadixString(16)}）'));
          }
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.complete(AuthFailure('認証処理エラー: $e'));
        }
      }
    }, onError: (Object e) {
      if (!completer.isCompleted) {
        completer.complete(AuthFailure('BLE受信エラー: $e'));
      }
    });

    try {
      // Step 2: 0x02（認証番号要求）を Write
      await _ble.writeCharacteristicWithoutResponse(
        authCharacteristic,
        value: [AuthCommands.requestAuthNumber],
      );

      return await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  /// AES-128-ECB で challenge を authKey で暗号化する
  ///
  /// [authKeyHex] : 32文字のHEX文字列（16バイト）
  /// [challenge]  : 16バイトのチャレンジデータ
  /// 失敗時は null を返す
  List<int>? _encryptChallenge(String authKeyHex, List<int> challenge) {
    try {
      // HEX文字列をバイト列に変換（スペースや空白を除去）
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
}
