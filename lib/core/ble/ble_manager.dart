import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/app_secrets.dart';
// TODO: V2プロトコル実装後に認証を有効化
// import 'band_authenticator.dart';
import 'band_protocol.dart';
import 'rssi_smoother.dart';

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
  // TODO: V2プロトコル実装後に認証を有効化
  // late final BandAuthenticator _authenticator = BandAuthenticator(_ble);
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
  Stream<DiscoveredDevice> scanForBand9({Duration timeout = const Duration(seconds: 15)}) {
    return _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).timeout(timeout, onTimeout: (sink) => sink.close());
  }

  /// MACアドレスまたはデバイスIDを取得して Band 9 に接続する
  ///
  /// MACアドレス・Auth Key は AppSecrets から読み取る。
  /// 接続失敗時は [_connectWithRetry] で自動リトライする。
  Future<BleResult<void>> connect() async {
    final macAddress = await AppSecrets.getBandMacAddress();
    final authKey = await AppSecrets.getBandAuthKey();

    if (macAddress == null || authKey == null) {
      return const BleFailure('MACアドレスまたはAuth Keyが未設定です');
    }

    // プレースホルダーのまま接続しない
    if (macAddress == 'XX:XX:XX:XX:XX:XX' || authKey == 'X') {
      return const BleFailure(
          'Band 9 未設定（到着後に Auth Key・MACアドレスを設定してください）');
    }

    _currentDeviceId = macAddress;
    _retryCount = 0;
    _disposed = false; // disconnect()後の再接続を可能にする
    return _doConnect(macAddress, authKey);
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
        characteristicId: Uuid.parse(BandCharacteristicUUIDs.mainChannel),
        deviceId: _currentDeviceId!,
      );

      // 振動パターンをバイト列に変換
      // フォーマット: [0x08, repeatCount, ...pattern(2byte each: ON_ms/100, OFF_ms/100)]
      final payload = <int>[0x08, pattern.repeat];
      for (var i = 0; i < pattern.pattern.length; i++) {
        payload.add((pattern.pattern[i] / 100).round().clamp(1, 255));
      }

      await _ble.writeCharacteristicWithoutResponse(
        characteristic,
        value: payload,
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
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _rssiTimer?.cancel();
    _connectionSubscription?.cancel();
    _connectionStateController.close();
    _rssiController.close();
  }

  // ----------------------------------------------------------------
  // 内部実装
  // ----------------------------------------------------------------

  Future<BleResult<void>> _doConnect(
      String deviceId, String authKey) async {
    _updateState(BleConnectionState.connecting);

    try {
      await _connectionSubscription?.cancel();

      final completer = Completer<BleResult<void>>();

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
                  // TODO: V2プロトコル実装後に認証を有効化
                  // Band 9 V2プロトコル（HMAC-SHA256 + AES-CCM）は未実装のため
                  // 認証フェーズをスキップし、接続直後にRSSI監視を開始する。
                  // 認証なしでもRSSI監視は動作する。
                  // 振動コマンド・ボタン検知は V2プロトコル実装後に有効になる。

                  _retryCount = 0;
                  _updateState(BleConnectionState.connected);
                  _startRssiPolling(deviceId);

                  // ignore: avoid_print
                  print('[BleManager] 接続完了（認証スキップ・RSSI監視のみ動作）');

                  if (!completer.isCompleted) completer.complete(const BleSuccess(null));

                case DeviceConnectionState.disconnected:
                  _rssiTimer?.cancel();
                  _rssiSmoother.reset();
                  if (!completer.isCompleted) {
                    completer.complete(
                        const BleFailure('接続が切断されました'));
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
              _updateState(BleConnectionState.error);
              if (!completer.isCompleted) {
                completer.complete(BleFailure('BLE接続エラー: $e'));
              }
            },
          );

      return await completer.future;
    } catch (e) {
      _updateState(BleConnectionState.error);
      return BleFailure('接続開始エラー: $e');
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
