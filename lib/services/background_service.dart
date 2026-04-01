import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ble/rssi_smoother.dart';
import '../core/tether/alert_state.dart';
import '../core/timeline/timeline_entry.dart';
import '../core/zone/adaptive_threshold_learner.dart';
import '../core/zone/safe_zone_detector.dart';

// ============================================================
// 層1: サービス初期化関数（main()から呼ぶ）
// ============================================================

/// バックグラウンドサービスをアプリ起動時に設定する
///
/// この関数は main() の冒頭で一度だけ呼ぶこと。
/// autoStart: false のため、実際の開始は [BackgroundServiceNotifier.startMonitoring] で行う。
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    // ---- iOS 設定 ----
    iosConfiguration: IosConfiguration(
      // ユーザーが明示的に監視開始するまでは起動しない
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
    // ---- Android 設定 ----
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      // ユーザーが明示的に監視開始するまでは起動しない
      autoStart: false,
      // Android 8.0以降のバックグラウンドBLEには Foreground Service が必須
      isForegroundMode: true,
      notificationChannelId: 'smart_tether_channel',
      initialNotificationTitle: 'Smart Tether',
      initialNotificationContent: '監視待機中',
      // notification_service.dart の _idPersistent と同じID（1）を使う
      foregroundServiceNotificationId: 1,
    ),
  );
}

// ============================================================
// 層2: バックグラウンドエントリポイント（別Isolate）
// ============================================================

/// バックグラウンドサービスのメインループ
///
/// このメソッドは別Isolateで実行されるため、
/// UI側の Riverpod プロバイダーには直接アクセスできない。
/// イベントは service.invoke() で UI 側へ送る。
///
/// [pragma] アノテーションはツリーシェイキングによる除去を防ぐために必須。
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // バックグラウンドIsolateでFlutterバインディングを確実に初期化する
  DartPluginRegistrant.ensureInitialized();

  // ---- コンポーネントの初期化 ----
  final safeZoneDetector = SafeZoneDetector();
  final thresholdLearner = AdaptiveThresholdLearner();
  final rssiSmoother = RSSISmoother();

  // ---- 段階遷移のための状態変数 ----
  TetherState previousState = TetherState.monitoring;
  // 切断を最初に検知した時刻。接続回復時に null にリセットする。
  DateTime? disconnectDetectedAt;

  try {
    // SharedPreferences から保存済みの設定を読み込む
    await safeZoneDetector.initialize();
    await thresholdLearner.initialize();
  } catch (e) {
    // 初期化失敗時はデフォルト値のまま動作継続する（バックグラウンドクラッシュ防止）
    // ignore: avoid_print
    print('[BackgroundService] 初期化エラー（デフォルト値で続行）: $e');
  }

  // 起動ログをIPC経由でUIへ送信する（バックグラウンドIsolate内では直接書き込まない）
  _invokeTimelineEntry(
    service,
    type: TimelineEventType.monitoringStarted,
    message: 'バックグラウンド監視を開始しました',
  );

  // ---- BleManager からの RSSI 受信リスナー ----
  // メインIsolateの BleManager が invoke('rssiUpdate') した値をここで受け取る
  // 注意: メインIsolate側で既にスムージング済みの値が送られてくるため、
  //       ここでは二重スムージングせず smoothedValue のみ更新する
  StreamSubscription? rssiSub;
  StreamSubscription? stopSub;
  Timer? monitorTimer;

  rssiSub = service.on('rssiUpdate').listen((data) {
    // IPC経由のJSONでは int が来る可能性があるため num 経由で変換する
    final rssi = (data?['rssi'] as num?)?.toDouble();
    if (rssi != null) {
      rssiSmoother.setDirectValue(rssi.round());
    }
  });

  // ---- 停止コマンドのリスナー ----
  // UIから 'stopService' イベントを受け取ったらサービスを停止する
  // monitorTimer は監視ループの参照（停止時にキャンセルするため）

  stopSub = service.on('stopService').listen((_) async {
    monitorTimer?.cancel();
    rssiSub?.cancel();
    stopSub?.cancel();
    _invokeTimelineEntry(
      service,
      type: TimelineEventType.monitoringStopped,
      message: 'バックグラウンド監視を停止しました',
    );
    await service.stopSelf();
  });

  // ---- 監視メインループ（30秒ごと） ----
  //
  // 30秒間隔の理由:
  //   - バッテリー消費を抑える
  //   - 置き忘れ検知の応答性と省電力のバランスが取れている
  //   - Band9到着後、BLE RSSI取得に切り替えても同じ間隔を維持できる
  monitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
    try {
      final result = await _performMonitoringCycle(
        service: service,
        safeZoneDetector: safeZoneDetector,
        thresholdLearner: thresholdLearner,
        rssiSmoother: rssiSmoother,
        previousState: previousState,
        disconnectDetectedAt: disconnectDetectedAt,
      );
      previousState = result.state;
      disconnectDetectedAt = result.disconnectDetectedAt;
    } catch (e) {
      // 監視サイクルの例外はログに記録して次のサイクルへ続行する
      // バックグラウンドサービスのクラッシュは致命的なため、例外を外へ出さない
      // ignore: avoid_print
      print('[BackgroundService] 監視サイクルエラー: $e');
    }
  });
}

/// 監視サイクルの結果（段階遷移の状態を返すため）
class _MonitoringCycleResult {
  final TetherState state;
  // 切断を最初に検知した時刻。接続中・セーフゾーン中は null。
  final DateTime? disconnectDetectedAt;

  const _MonitoringCycleResult({
    required this.state,
    this.disconnectDetectedAt,
  });
}

/// 1回分の監視サイクルを実行する
///
/// セーフゾーン判定 → 状態決定（grace→warning→confirmed段階遷移）→ UI通知の順で処理する。
/// 例外はすべて呼び出し元でキャッチすること。
///
/// フェーズ定義（30秒ループを前提とした現実的な閾値）:
///   grace    : 0〜30秒  — 一時的な切断、バックグラウンド再接続を待つ
///   warning  : 30〜90秒 — バンドを振動させて警告
///   confirmed: 90秒以上 — 置き忘れ確定、全力アラート
Future<_MonitoringCycleResult> _performMonitoringCycle({
  required ServiceInstance service,
  required SafeZoneDetector safeZoneDetector,
  required AdaptiveThresholdLearner thresholdLearner,
  required RSSISmoother rssiSmoother,
  required TetherState previousState,
  required DateTime? disconnectDetectedAt,
}) async {
  // ---- セーフゾーン判定 ----
  final inSafeZone = await safeZoneDetector.isInSafeZone();

  // ---- RSSI 取得（BleManager から rssiUpdate IPC 経由で投入済み） ----
  // rssiSmoother には onStart() の rssiUpdate リスナーが値を投入している
  final smoothedRssi = rssiSmoother.smoothedValue;

  // ---- 状態を決定する（grace → warning → confirmed 段階遷移） ----
  TetherState newState;
  DateTime? newDisconnectDetectedAt = disconnectDetectedAt;

  if (inSafeZone) {
    // セーフゾーン（自宅Wi-Fiなど）にいる場合はスリープ状態
    newState = TetherState.sleeping;
    newDisconnectDetectedAt = null;
  } else if (smoothedRssi <= -999) {
    // RSSI未取得（BLE未接続）→ 監視中として扱う
    newState = TetherState.monitoring;
    newDisconnectDetectedAt = null;
  } else {
    // RSSI と閾値を比較して状態を判定する
    if (rssiSmoother.isReady) {
      thresholdLearner.addConnectedSample(smoothedRssi);
    }

    if (smoothedRssi <= thresholdLearner.threshold) {
      // RSSI が閾値以下 → 切断継続中として段階遷移を進める
      // 切断を最初に検知した時刻を記録する（既に記録済みの場合はそのまま）
      final now = DateTime.now();
      newDisconnectDetectedAt ??= now;

      final elapsed = now.difference(newDisconnectDetectedAt).inSeconds;

      if (elapsed < 30) {
        // 0〜29秒: grace（猶予フェーズ）— 一時的切断、バックグラウンド再接続を待つ
        newState = TetherState.grace;
      } else if (elapsed < 90) {
        // 30〜89秒: warning（警告フェーズ）— バンドを振動させる
        newState = TetherState.warning;
      } else {
        // 90秒以上: confirmed（確定フェーズ）— 全力アラート
        newState = TetherState.confirmed;
      }
    } else {
      // RSSI が閾値以上に回復 → 監視状態に戻し、切断検知タイムスタンプをリセットする
      newState = TetherState.monitoring;
      newDisconnectDetectedAt = null;
    }
  }

  // ---- UI側（メインIsolate）へ状態変化を通知する ----
  service.invoke('stateUpdate', {
    'state': newState.name,
    'timestamp': DateTime.now().toIso8601String(),
    'rssi': smoothedRssi,
    'inSafeZone': inSafeZone,
  });

  return _MonitoringCycleResult(
    state: newState,
    disconnectDetectedAt: newDisconnectDetectedAt,
  );
}

/// バックグラウンドIsolateからUIへタイムラインエントリをIPC送信する
///
/// バックグラウンドIsolateと UIのIsolateはメモリ空間が分離されているため、
/// [TimelineLogger] を直接 new しても UIの [_TimelineEntriesNotifier] には届かない。
/// この関数を通じて invoke('timelineEntry') でエントリデータを送り、
/// UIのリスナーで受け取って [TimelineLogger.addEntry] を呼ぶことで正しく反映される。
void _invokeTimelineEntry(
  ServiceInstance service, {
  required TimelineEventType type,
  required String message,
  String? transcription,
  String? audioFilePath,
  int? audioDurationMs,
}) {
  try {
    service.invoke('timelineEntry', {
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'timestamp': DateTime.now().toIso8601String(),
      'type': type.name,
      'message': message,
      if (transcription != null) 'transcription': transcription,
      if (audioFilePath != null) 'audioFilePath': audioFilePath,
      if (audioDurationMs != null) 'audioDurationMs': audioDurationMs,
    });
  } catch (e) {
    // invoke の失敗はサービス全体をクラッシュさせない
    // ignore: avoid_print
    print('[BackgroundService] timelineEntry invoke エラー: $e');
  }
}

/// iOS バックグラウンドエントリポイント
///
/// iOSでアプリがバックグラウンドに移行したときに呼ばれる。
/// trueを返すことでバックグラウンド処理の継続を許可する。
///
/// [pragma] アノテーションはツリーシェイキングによる除去を防ぐために必須。
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // iOSバックグラウンドIsolateではFlutterバインディングの明示的な初期化が必要
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // trueを返すことでiOSにバックグラウンド実行継続を要求する
  return true;
}

// ============================================================
// 層3: UIとの橋渡し（Riverpod）
// ============================================================

/// バックグラウンドサービスの起動・停止を管理する Notifier
///
/// 状態値（bool）は現在のサービス動作状態を表す:
///   - true  = 監視中
///   - false = 停止中
class BackgroundServiceNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// バックグラウンド監視を開始する
  ///
  /// すでに起動中の場合は何もしない。
  Future<void> startMonitoring() async {
    final service = FlutterBackgroundService();

    try {
      final isRunning = await service.isRunning();
      if (isRunning) {
        // すでに稼働中のため二重起動しない
        state = true;
        return;
      }

      await service.startService();
      state = true;
    } catch (e) {
      // 起動失敗時はstate = falseのまま（UIでエラー表示できる）
      // ignore: avoid_print
      print('[BackgroundServiceNotifier] 起動エラー: $e');
    }
  }

  /// バックグラウンド監視を停止する
  ///
  /// サービス側に 'stopService' イベントを送って安全に終了させる。
  Future<void> stopMonitoring() async {
    final service = FlutterBackgroundService();

    try {
      final isRunning = await service.isRunning();
      if (!isRunning) {
        state = false;
        return;
      }

      // サービス側の stopSelf() を呼ばせるためにイベントを送信する
      service.invoke('stopService');

      // サービスが停止するまで少し待ってから状態を更新する
      await Future<void>.delayed(const Duration(milliseconds: 500));
      state = false;
    } catch (e) {
      // 停止失敗時も state = false にして UI の不整合を防ぐ
      state = false;
      // ignore: avoid_print
      print('[BackgroundServiceNotifier] 停止エラー: $e');
    }
  }
}

/// バックグラウンドサービスの起動状態を管理するプロバイダー
///
/// 使い方:
/// ```dart
/// // 監視開始
/// ref.read(backgroundServiceProvider.notifier).startMonitoring();
///
/// // 監視停止
/// ref.read(backgroundServiceProvider.notifier).stopMonitoring();
///
/// // 現在の動作状態
/// final isRunning = ref.watch(backgroundServiceProvider);
/// ```
final backgroundServiceProvider =
    NotifierProvider<BackgroundServiceNotifier, bool>(
  BackgroundServiceNotifier.new,
);

/// バックグラウンドサービスからの TetherState 変化を受け取る Stream プロバイダー
///
/// バックグラウンドIsolateが30秒ごとに invoke('stateUpdate') した値を
/// メインIsolateでリアルタイムに受け取る。
///
/// 受信できない/データ不正な場合は TetherState.sleeping にフォールバックする。
final tetherStateStreamProvider = StreamProvider<TetherState>((ref) {
  return FlutterBackgroundService()
      .on('stateUpdate')
      .map((data) {
        // データがnullまたは 'state' キーが取得できない場合のフォールバック
        final stateName = data?['state'] as String? ?? TetherState.sleeping.name;

        return TetherState.values.firstWhere(
          (s) => s.name == stateName,
          // 不明な状態名が来た場合は安全側（sleeping）にフォールバックする
          orElse: () => TetherState.sleeping,
        );
      });
});

