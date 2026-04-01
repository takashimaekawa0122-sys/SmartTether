import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ble/ble_manager.dart';
import 'alert/alert_overlay.dart';
import 'timeline/timeline_page.dart';

/// TimelinePage の上に AlertOverlayController を重ねるルートスタック
///
/// AlertOverlayController は tetherStateStreamProvider を監視して
/// 警告状態になると自動的に全画面オーバーレイを表示する。
///
/// WidgetsBindingObserver を使いアプリのライフサイクルを監視し、
/// フォアグラウンド復帰時に BLE 接続が切れていれば自動再接続する。
class HomeStack extends ConsumerStatefulWidget {
  const HomeStack({super.key});

  @override
  ConsumerState<HomeStack> createState() => _HomeStackState();
}

class _HomeStackState extends ConsumerState<HomeStack>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// アプリがフォアグラウンドに復帰したとき、BLE が切断中なら再接続を試みる
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final bleManager = ref.read(bleManagerProvider);
    final connectionState = ref.read(bleConnectionStateProvider).valueOrNull;

    // 切断中・エラー状態のときのみ再接続する（connecting/authenticating/connected は放置）
    if (connectionState == BleConnectionState.disconnected ||
        connectionState == BleConnectionState.error) {
      // ignore: avoid_print
      print('[HomeStack] アプリ復帰 → BLE 再接続を試みます (state=$connectionState)');
      // build() の外で非同期処理を起動する
      SchedulerBinding.instance.addPostFrameCallback((_) {
        bleManager.connect();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        TimelinePage(),
        AlertOverlayController(),
      ],
    );
  }
}
