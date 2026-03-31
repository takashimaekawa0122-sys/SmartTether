/// ステルストリガー — Band 9 ボタン入力をアクションに変換する
///
/// Xiaomi Smart Band 9 のメディアコントロールキャラクタリスティック
/// （fe95/005e）を購読し、受信したボタン値を [StealthAction] に変換して
/// Riverpod の StateNotifier 経由でUIへ通知する。
///
/// ボタン値と動作の対応（band_protocol.dart の MediaControlButton と一致）:
/// - 0x04 (doubleTab)  → [StealthAction.voiceMemo]  ボイスメモ開始/停止
/// - 0x03 (tripleTab)  → [StealthAction.emergency]  緊急アラート
/// - 0x01 (longPress)  → [StealthAction.safeSignal] 「今は安全」手動通知
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/band_protocol.dart';
import '../ble/ble_manager.dart';
import 'stealth_command_handler.dart';

// =========================================================
// StealthAction enum
// =========================================================

/// ステルストリガーで起動できるアクション
enum StealthAction {
  /// ダブルタップ: ボイスメモ録音の開始 / 停止
  voiceMemo,

  /// 長押し（2秒）: 「今は安全」手動通知
  safeSignal,

  /// トリプルタップ: 緊急アラート送信
  emergency,
}

// =========================================================
// StealthTriggerNotifier
// =========================================================

/// Band 9 のボタン入力を監視し、検知した [StealthAction] を状態として保持する
///
/// 使い方:
/// ```dart
/// // BLE接続後に監視を開始する
/// ref.read(stealthTriggerProvider.notifier).startListening();
///
/// // アクションが発火したらコマンドを実行する
/// ref.listen(stealthTriggerProvider, (_, action) {
///   if (action != null) {
///     ref.read(stealthCommandHandlerProvider).handleCommand(...);
///   }
/// });
/// ```
class StealthTriggerNotifier extends StateNotifier<StealthAction?> {
  final BleManager _bleManager;
  final StealthCommandHandler _commandHandler;

  StreamSubscription<List<int>>? _subscription;

  StealthTriggerNotifier({
    required BleManager bleManager,
    required StealthCommandHandler commandHandler,
  })  : _bleManager = bleManager,
        _commandHandler = commandHandler,
        super(null);

  // -------------------------------------------------------
  // 公開 API
  // -------------------------------------------------------

  /// メディアコントロールキャラクタリスティックの監視を開始する
  ///
  /// BLE接続完了後（[BleConnectionState.connected]）に呼び出すこと。
  /// すでに監視中の場合は前のサブスクリプションをキャンセルして再開する。
  void startListening() {
    stopListening();

    try {
      final stream = _bleManager.subscribeToCharacteristic(
        serviceUuid: BandServiceUUIDs.main,
        characteristicUuid: BandCharacteristicUUIDs.mainChannel,
      );

      _subscription = stream.listen(
        _onData,
        onError: (Object e) {
          // BLE受信エラーは致命的にしない。次の接続機会に再購読する
          // ignore: avoid_print
          print('[StealthTrigger] 受信エラー: $e');
        },
        cancelOnError: false,
      );

      // ignore: avoid_print
      print('[StealthTrigger] メディアコントロール監視を開始しました');
    } catch (e) {
      // subscribeToCharacteristic 呼び出し自体が失敗した場合
      // ignore: avoid_print
      print('[StealthTrigger] 監視開始エラー: $e');
    }
  }

  /// 監視を停止する
  ///
  /// BLE切断時や dispose 前に呼ぶこと。
  void stopListening() {
    try {
      _subscription?.cancel();
      _subscription = null;
      // ignore: avoid_print
      print('[StealthTrigger] メディアコントロール監視を停止しました');
    } catch (e) {
      // ignore: avoid_print
      print('[StealthTrigger] 監視停止エラー: $e');
    }
  }

  /// 最後に検知されたアクションをクリアする
  ///
  /// アクションを消費した後に呼ぶことで、同一アクションの二重実行を防ぐ。
  void clearAction() {
    state = null;
  }

  // -------------------------------------------------------
  // プライベートメソッド
  // -------------------------------------------------------

  /// BLE通知データを受信したときの処理
  ///
  /// データ形式: 先頭バイトがボタン値（0x01 / 0x02 / 0x03）
  void _onData(List<int> data) {
    if (!mounted || data.isEmpty) return;

    final buttonValue = data[0];
    final action = _buttonValueToAction(buttonValue);

    if (action == null) {
      // 未知のボタン値は無視する
      // ignore: avoid_print
      print('[StealthTrigger] 未知のボタン値を無視しました: '
          '0x${buttonValue.toRadixString(16)}');
      return;
    }

    // ignore: avoid_print
    print('[StealthTrigger] アクション検知: $action '
        '(ボタン値: 0x${buttonValue.toRadixString(16)})');

    // StateNotifier の状態を更新してUIに通知する
    state = action;

    // コマンドを即時実行する（CommandHandler に委譲）
    _executeAction(action, buttonValue);
  }

  /// ボタン値を [StealthAction] に変換する
  ///
  /// [MediaControlButton] 定数と対応している。
  /// 未知の値の場合は null を返す。
  StealthAction? _buttonValueToAction(int buttonValue) {
    switch (buttonValue) {
      case MediaControlButton.doubleTab:
        // ダブルタップ → ボイスメモ
        return StealthAction.voiceMemo;
      case MediaControlButton.tripleTab:
        // トリプルタップ → 緊急アラート
        return StealthAction.emergency;
      case MediaControlButton.longPress:
        // 長押し → 安全確認
        return StealthAction.safeSignal;
      default:
        return null;
    }
  }

  /// [StealthAction] に対応する処理を [StealthCommandHandler] に委譲する
  ///
  /// safeSignal は Band 9 への振動フィードバックのみ行い、
  /// 上位層（UI/サービス）がリスナー経由で受け取る。
  void _executeAction(StealthAction action, int buttonValue) {
    switch (action) {
      case StealthAction.voiceMemo:
        // ダブルタップ → ボイスメモ（CommandHandler に既存の処理がある）
        _commandHandler.handleCommand(buttonValue).catchError((Object e) {
          // ignore: avoid_print
          print('[StealthTrigger] voiceMemo 実行エラー: $e');
        });

      case StealthAction.emergency:
        // トリプルタップ → 緊急アラート（CommandHandler に既存の処理がある）
        _commandHandler.handleCommand(buttonValue).catchError((Object e) {
          // ignore: avoid_print
          print('[StealthTrigger] emergency 実行エラー: $e');
        });

      case StealthAction.safeSignal:
        // 長押し → 「今は安全」手動通知
        // CommandHandler の長押しコマンドを呼ぶ（エスケープタイマー起動）
        _commandHandler
            .startEscapeTimer(
          seconds: 30,
          onComplete: () {
            // ignore: avoid_print
            print('[StealthTrigger] エスケープタイマー完了');
          },
        )
            .catchError((Object e) {
          // ignore: avoid_print
          print('[StealthTrigger] safeSignal 実行エラー: $e');
        });
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

// =========================================================
// Riverpod プロバイダー
// =========================================================

/// ステルストリガーの状態プロバイダー
///
/// 最後に検知された [StealthAction] を保持する。
/// アクションを消費したら [StealthTriggerNotifier.clearAction] を呼ぶこと。
///
/// 使い方:
/// ```dart
/// // BLE接続完了時に監視を開始する
/// ref.read(stealthTriggerProvider.notifier).startListening();
///
/// // アクション変化を監視する（例: UIウィジェット内）
/// ref.listen<StealthAction?>(stealthTriggerProvider, (_, action) {
///   if (action == StealthAction.emergency) {
///     showEmergencyDialog(context);
///     ref.read(stealthTriggerProvider.notifier).clearAction();
///   }
/// });
/// ```
final stealthTriggerProvider =
    StateNotifierProvider<StealthTriggerNotifier, StealthAction?>((ref) {
  final notifier = StealthTriggerNotifier(
    bleManager: ref.read(bleManagerProvider),
    commandHandler: ref.read(stealthCommandHandlerProvider),
  );

  // TODO: V2プロトコル認証成功後に有効化
  // BLE接続状態を監視して、接続完了時に自動で監視を開始する。
  // V2プロトコル未実装のため、subscribeすると認証なしでエラーになる。
  // 認証実装後に以下のコメントを解除すること。
  //
  // ref.listen<AsyncValue<BleConnectionState>>(
  //   bleConnectionStateProvider,
  //   (_, next) {
  //     // dispose後にコールバックが来た場合は無視する
  //     if (!notifier.mounted) return;
  //     next.whenData((connectionState) {
  //       if (connectionState == BleConnectionState.connected) {
  //         notifier.startListening();
  //       } else if (connectionState == BleConnectionState.disconnected ||
  //           connectionState == BleConnectionState.error) {
  //         notifier.stopListening();
  //       }
  //     });
  //   },
  // );

  ref.onDispose(notifier.dispose);
  return notifier;
});
