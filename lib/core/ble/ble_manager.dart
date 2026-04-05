import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/app_secrets.dart';
import 'band_authenticator.dart';
import 'band_protocol.dart';
import 'rssi_smoother.dart';
import 'sppv2_packet.dart';

/// BLE接続状態
enum BleConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  error,
}

/// BLE操作の結果を表すシールドクラス
sealed class BleResult<T> {
  const BleResult();
}

class BleSuccess<T> extends BleResult<T> {
  final T value;
  const BleSuccess(this.value);
}

class BleFailure<T> extends BleResult<T> {
  final String error;
  const BleFailure(this.error);
}

/// Xiaomi Smart Band 9 との BLE 接続ライフサイクルを管理するクラス
///
/// 責務:
///   - MACアドレスによる接続・認証
///   - RSSI の定期取得と平滑化
///   - 切断時の指数バックオフ再接続
///   - バックグラウンドIsolateへの RSSI 中継（IPC）
///
/// 注意: flutter_reactive_ble はメインIsolateで動作すること。
class BleManager {
  /// テスト用: [FlutterReactiveBle] を外部から注入できる。
  /// 省略時は実機向けインスタンスを生成する。
  BleManager({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  late final BandAuthenticator _authenticator = BandAuthenticator(_ble);
  final _rssiSmoother = RSSISmoother();

  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  final _rssiController = StreamController<double>.broadcast();

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  Timer? _rssiTimer;
  Timer? _retryTimer;

  int _retryCount = 0;
  bool _disposed = false;
  String? _currentDeviceId;

  /// 接続状態のストリーム
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// 平滑化された RSSI 値のストリーム
  Stream<double> get rssiStream => _rssiController.stream;

  // ----------------------------------------------------------------
  // 公開 API
  // ----------------------------------------------------------------

  /// Band 9 をスキャンして見つかったデバイスのStreamを返す
  ///
  /// iOS では MACアドレスでは接続できないため、
  /// BLEスキャンで Band 9 を見つけてプラットフォーム固有のIDを取得する。
  /// サービスUUIDフィルターなしでスキャンし、すべてのBLEデバイスを返す。
  ///
  /// 注意: Stream.timeout() はイベント間隔のタイムアウトであるため使用しない。
  /// 呼び出し側で firstWhere().timeout() を使って合計時間を制限すること。
  Stream<DiscoveredDevice> scanForBand9() {
    return _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    );
  }

  /// MACアドレスまたはデバイスIDを取得して Band 9 に接続する
  ///
  /// MACアドレス・Auth Key は AppSecrets から読み取る。
  /// 接続失敗時は [_connectWithRetry] で自動リトライする。
  Future<BleResult<void>> connect() async {
    try {
      return await _connectInternal().timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          _updateState(BleConnectionState.error);
          return const BleFailure('接続タイムアウト（2分）: BLE接続が確立できませんでした\n→ 設定画面でBand 9を再スキャンしてください');
        },
      );
    } catch (e) {
      _updateState(BleConnectionState.error);
      return BleFailure('接続エラー: $e');
    }
  }

  Future<BleResult<void>> _connectInternal() async {
    final macAddress = await AppSecrets.getBandMacAddress();
    final authKey = await AppSecrets.getBandAuthKey();

    if (macAddress == null || authKey == null) {
      return const BleFailure('MACアドレスまたはAuth Keyが未設定です');
    }

    // 有効な値でなければ接続しない
    if (!AppSecrets.isValidMacAddress(macAddress) ||
        !AppSecrets.isValidAuthKey(authKey)) {
      return const BleFailure(
          'Band 9 未設定（Auth Key・MACアドレスを設定してください）');
    }

    _currentDeviceId = macAddress;
    _retryCount = 0;
    _disposed = false; // disconnect()後の再接続を可能にする

    // まず保存済みIDで接続を試みる
    final firstResult = await _doConnect(macAddress, authKey);

    // 接続が即切断（STEP1未到達）の場合、iOSのUUIDが古い可能性があるため
    // スキャンして最新のデバイスIDを取得し直して再試行する
    if (firstResult is BleFailure &&
        firstResult.error.startsWith('接続が切断されました') &&
        !firstResult.error.contains('STEP1')) {
      // ignore: avoid_print
      print('[BleManager] 即切断を検出。スキャンして最新IDで再試行します...');
      try {
        // Stream.timeout はイベント間隔のタイムアウトのため、
        // 近くに多数のBLEデバイスがある場合にリセットされ続けてハングする。
        // firstWhere の結果（Future）に直接 timeout をかけることで確実に打ち切る。
        final freshDevice = await scanForBand9()
            .firstWhere(
              (d) => d.name.toLowerCase().contains('band') ||
                  d.name.toLowerCase().contains('mi'),
              orElse: () => throw Exception('Band 9が見つかりません'),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw Exception('Band 9スキャンタイムアウト（10秒）'),
            );
        if (_disposed) return firstResult;
        final freshId = freshDevice.id;
        // ignore: avoid_print
        print('[BleManager] 新しいdeviceId=$freshId で再接続します');
        _currentDeviceId = freshId;
        await AppSecrets.saveBandMacAddress(freshId); // 最新IDを保存
        return _doConnect(freshId, authKey);
      } catch (e) {
        // ignore: avoid_print
        print('[BleManager] スキャン再試行失敗: $e');
        return BleFailure(
          '${firstResult.error}\n\n'
          '【自動再スキャンも失敗】$e\n'
          '→ 設定画面でBand 9を再スキャンしてください',
        );
      }
    }

    return firstResult;
  }

  /// 切断する
  Future<void> disconnect() async {
    _disposed = true;
    _retryTimer?.cancel();
    _rssiTimer?.cancel();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _rssiSmoother.reset();
    _updateState(BleConnectionState.disconnected);
  }

  /// 振動コマンドを送信する
  Future<BleResult<void>> sendVibration(VibrationPattern pattern) async {
    if (_currentDeviceId == null) {
      return const BleFailure('未接続です');
    }

    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(BandServiceUUIDs.main),
        characteristicId: Uuid.parse(BandCharacteristicUUIDs.txChannel),
        deviceId: _currentDeviceId!,
      );

      // 振動パターンをバイト列に変換
      // フォーマット: [0x08, repeatCount, ...pattern(2byte each: ON_ms/100, OFF_ms/100)]
      final commandData = <int>[0x08, pattern.repeat];
      for (var i = 0; i < pattern.pattern.length; i++) {
        commandData.add((pattern.pattern[i] / 100).round().clamp(1, 255));
      }

      // SPPv2パケットでラップして送信（Band 9は生バイト列を無視する）
      final packet = Sppv2Packet.buildCommand(
        channelId: Sppv2Channel.command,
        payloadType: Sppv2PayloadType.plaintext,
        data: commandData,
      );

      await _ble.writeCharacteristicWithoutResponse(
        characteristic,
        value: packet,
      );
      return const BleSuccess(null);
    } catch (e) {
      return BleFailure('振動送信エラー: $e');
    }
  }

  /// 指定されたキャラクタリスティックの通知を購読するStreamを返す
  ///
  /// 呼び出し側は返却された StreamSubscription を保持し、
  /// 不要になったら cancel() を呼ぶこと。
  /// BLE操作のため try-catch は呼び出し側で行うこと。
  Stream<List<int>> subscribeToCharacteristic({
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    if (_currentDeviceId == null) {
      // ignore: avoid_print
      print('[BleManager] subscribeToCharacteristic: 未接続のため空Streamを返します');
      return const Stream.empty();
    }
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
      deviceId: _currentDeviceId!,
    );
    return _ble.subscribeToCharacteristic(characteristic);
  }

  /// リソースを解放する
  ///
  /// [M-2] Riverpod の ref.onDispose は同期コールバックのため、
  /// このメソッドは void のままにしている。
  /// cancel() は非同期だが、その Future を scheduleMicrotask に渡すことで
  /// 「cancel の完了を待ってから close する」順序を保証する。
  /// unawaited() を使わず明示的に then() で close を連鎖させることで、
  /// cancel のコールバック内で closed stream にアクセスするエラーを防ぐ。
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _rssiTimer?.cancel();
    // cancel() の完了後に close する。cancel() が null の場合は即 close。
    final cancelFuture = _connectionSubscription?.cancel();
    _connectionSubscription = null;
    if (cancelFuture != null) {
      // cancel 完了を待ってから Stream を閉じる（非同期順序保証）
      cancelFuture.whenComplete(() {
        _connectionStateController.close();
        _rssiController.close();
      });
    } else {
      _connectionStateController.close();
      _rssiController.close();
    }
  }

  // ----------------------------------------------------------------
  // 内部実装
  // ----------------------------------------------------------------

  Future<BleResult<void>> _doConnect(
      String deviceId, String authKey) async {
    _updateState(BleConnectionState.connecting);

    // 接続フロー診断ログ（MTU・Bonding・認証の各ステップを記録）
    final connectLog = <String>[];
    void clog(String msg) {
      connectLog.add(msg);
      // ignore: avoid_print
      print('[BleManager] $msg');
    }

    clog('deviceId=$deviceId');

    try {
      // cancel() 自体がiOSのBLEスタック詰まりでハングする場合があるため
      // 5秒のタイムアウトを設ける（タイムアウト後は強制的に null 化して続行）
      final cancelFuture = _connectionSubscription?.cancel();
      if (cancelFuture != null) {
        await cancelFuture.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }
      _connectionSubscription = null;
      // iOSのBLEスタックが前の接続をクリーンアップする時間を確保
      // （cancel直後に再接続するとconnectedを経由せずdisconnectedになる問題を防ぐ）
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // [H-3] completer を null 化することで、disconnected と onError が
      // 同時に来た場合の二重 complete を防ぐ。
      // null チェック後に即 null にセットし、残方が何も呼べない状態にする。
      Completer<BleResult<void>>? completer = Completer<BleResult<void>>();

      /// completer を1度だけ complete して即 null 化するヘルパー。
      /// 二重 complete を構造的に防ぐ。
      void safeComplete(BleResult<void> result) {
        final c = completer;
        if (c != null && !c.isCompleted) {
          completer = null;
          c.complete(result);
        }
      }

      _connectionSubscription = _ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: const Duration(seconds: 15),
          )
          .listen(
            (update) async {
              if (_disposed) return;

              switch (update.connectionState) {
                case DeviceConnectionState.connected:
                  _updateState(BleConnectionState.authenticating);
                  clog('STEP1: BLE接続確立');

                  // MTU 512 をリクエストする（Gadgetbridge: requestMtu(512) と同一）
                  // デフォルトMTU(23)のままだとSPPv2パケットが断片化して認証失敗になる。
                  try {
                    final negotiatedMtu = await _ble.requestMtu(
                      deviceId: deviceId,
                      mtu: 512,
                    );
                    clog('STEP2: MTU=$negotiatedMtu');
                  } catch (e) {
                    // MTU失敗は致命的ではない（デフォルトMTUで継続）
                    clog('STEP2: MTU失敗（続行）: $e');
                  }

                  // BLE Bondingをトリガーする（Gadgetbridge: createBond() 相当）
                  clog('STEP3: Bonding開始');
                  await _triggerBonding(deviceId);
                  clog('STEP4: Bonding完了');

                  // V2プロトコル（HMAC-SHA256 + AES-CCM）で認証を実行する
                  clog('STEP5: authenticateV2開始');
                  final authResult =
                      await _authenticator.authenticateV2(deviceId, authKey);

                  if (authResult is AuthFailure) {
                    clog('STEP6: 認証失敗');
                    _updateState(BleConnectionState.error);
                    safeComplete(BleFailure('認証失敗: ${authResult.error}'));
                    return;
                  }

                  clog('STEP6: 認証成功');
                  _retryCount = 0;
                  _updateState(BleConnectionState.connected);
                  _startRssiPolling(deviceId);
                  safeComplete(const BleSuccess(null));

                case DeviceConnectionState.disconnected:
                  _rssiTimer?.cancel();
                  _rssiSmoother.reset();
                  if (completer != null) {
                    // completer がまだ生きている = 初回接続が完了していない
                    final authLog = _authenticator.lastDiagLog;
                    final allLog = [...connectLog, ...authLog];
                    final diagText = allLog.isNotEmpty
                        ? '\n\n── 診断ログ ──\n${allLog.join('\n')}'
                        : '';
                    safeComplete(BleFailure('接続が切断されました$diagText'));
                  } else {
                    // 接続済み状態での切断 → 再接続
                    _updateState(BleConnectionState.disconnected);
                    _scheduleRetry(deviceId, authKey);
                  }

                case DeviceConnectionState.connecting:
                case DeviceConnectionState.disconnecting:
                  break;
              }
            },
            onError: (Object e) {
              // [H-3] _disposed チェックを追加。
              // _connectionSubscription?.cancel() が onError を発火させた場合に
              // dispose 後の処理を防ぐ。
              if (_disposed) return;
              _updateState(BleConnectionState.error);
              final authLog = _authenticator.lastDiagLog;
              final allLog = [...connectLog, ...authLog];
              final diagText = allLog.isNotEmpty
                  ? '\n\n── 診断ログ ──\n${allLog.join('\n')}'
                  : '';
              safeComplete(BleFailure('BLE接続エラー: $e$diagText'));
            },
          );

      // flutter_reactive_ble iOS既知バグ対策: connectToDeviceがconnected/disconnectedを
      // 発火させずにconnecting状態で詰まることがある（Issue #582）。
      // 60秒の保険タイムアウトで必ず処理を完了させる。
      return await completer!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          clog('TIMEOUT: 60秒タイムアウト（iOS BLEスタック詰まり）');
          _updateState(BleConnectionState.error);
          final diagText = connectLog.isNotEmpty
              ? '\n\n── 診断ログ ──\n${connectLog.join('\n')}'
              : '';
          return BleFailure('接続タイムアウト（60秒）$diagText');
        },
      );
    } catch (e) {
      _updateState(BleConnectionState.error);
      return BleFailure('接続開始エラー: $e');
    }
  }

  /// BLE Bondingをトリガーする
  ///
  /// Gadgetbridgeでは `BluetoothDevice.createBond()` で明示的にbondingを行うが、
  /// iOSにはその直接的なAPIがない。代わりに、暗号化が要求される
  /// キャラクタリスティック（fdabサービスの0002）をreadすることで、
  /// iOSが自動的にペアリングダイアログを表示してbondingを完了する。
  ///
  /// Bond済みの場合は何も起きずに正常に完了する。
  /// fdabサービスが見つからない場合もエラーとせず続行する。
  Future<void> _triggerBonding(String deviceId) async {
    try {
      final pairingChar = QualifiedCharacteristic(
        serviceId: Uuid.parse(BandServiceUUIDs.pairing),
        characteristicId: Uuid.parse(BandCharacteristicUUIDs.pairingAuth),
        deviceId: deviceId,
      );

      // ignore: avoid_print
      print('[BleManager] Bondingトリガー: fdab/0002 をread中...');
      // 3秒でタイムアウト: Band 9がfdab/0002に応答しない場合に無限待機を防ぐ
      await _ble.readCharacteristic(pairingChar)
          .timeout(const Duration(seconds: 3));
      // ignore: avoid_print
      print('[BleManager] Bondingトリガー完了（bond済みまたはペアリング成功）');

      // bonding完了後、BLEスタックが安定するまで少し待つ
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      // fdabサービスが暗号化を要求しない場合や、
      // サービスが見つからない場合はエラーになるが、
      // fe95での認証に影響しない可能性もあるため続行する
      // ignore: avoid_print
      print('[BleManager] Bondingトリガー: $e（続行します）');
    }
  }

  /// 指数バックオフで再接続をスケジュールする
  ///
  /// 待機時間: 1 → 2 → 4 → 8 → 16 → 30秒（上限）
  void _scheduleRetry(String deviceId, String authKey) {
    if (_disposed) return;

    _retryCount++;
    final seconds = (_retryCount <= 4)
        ? (1 << (_retryCount - 1)) // 1, 2, 4, 8, 16
        : 30; // 上限

    // ignore: avoid_print
    print('[BleManager] $seconds秒後に再接続（試行$_retryCount回目）');

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), () async {
      if (_disposed) return;
      await _doConnect(deviceId, authKey);
    });
  }

  /// 5秒ごとに RSSI を取得してスムージングし、バックグラウンドIsolateへ送る
  void _startRssiPolling(String deviceId) {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_disposed) return;
      try {
        final rssi = await _ble.readRssi(deviceId);
        // awaitの間にdisposeが走った場合を防ぐ
        if (_disposed) return;
        _rssiSmoother.addValue(rssi);
        final smoothed = _rssiSmoother.smoothedValue;

        // UI側へ通知
        if (!_rssiController.isClosed) _rssiController.add(smoothed);

        // バックグラウンドIsolateへ IPC 送信
        FlutterBackgroundService().invoke('rssiUpdate', {'rssi': smoothed});
      } catch (e) {
        // RSSI取得失敗は無視して次のサイクルへ
        // ignore: avoid_print
        print('[BleManager] RSSI取得エラー: $e');
      }
    });
  }

  void _updateState(BleConnectionState state) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }
}

/// BleManager の Riverpod プロバイダー
///
/// メインIsolateで動作する。バックグラウンドIsolateからは直接参照不可。
final bleManagerProvider = Provider<BleManager>((ref) {
  final manager = BleManager();
  ref.onDispose(manager.dispose);
  return manager;
});

/// BLE接続状態のストリームプロバイダー
final bleConnectionStateProvider = StreamProvider<BleConnectionState>((ref) {
  return ref.watch(bleManagerProvider).connectionStateStream;
});

/// 平滑化RSSI値のストリームプロバイダー
final bleRssiProvider = StreamProvider<double>((ref) {
  return ref.watch(bleManagerProvider).rssiStream;
});
