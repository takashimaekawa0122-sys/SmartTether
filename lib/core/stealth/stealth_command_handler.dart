/// BLEメディアコントロールボタン入力をステルス操作に変換するクラス
///
/// Xiaomi Smart Band 9 のボタン操作（ダブルタップ・トリプルタップ・長押し）を
/// 受け取り、対応するステルス機能（フラッシュ・ボイスメモ・エスケープタイマー）
/// を実行する。
///
/// このクラスはコマンドの振り分けのみを担当し、実際の処理は各コントローラーに委譲する。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/band_protocol.dart';
import '../timeline/timeline_entry.dart';
import '../timeline/timeline_logger.dart';
import 'escape_timer.dart';
import 'flash_controller.dart';
import 'voice_memo_recorder.dart';

/// BLEコマンドをステルス操作にマッピングして実行するクラス
///
/// 使い方:
/// ```dart
/// final handler = ref.read(stealthCommandHandlerProvider);
///
/// // BLEイベント受信時
/// await handler.handleCommand(StealthCommandHandler.cmdDoubleTap);
///
/// // エスケープタイマー起動
/// await handler.startEscapeTimer(
///   seconds: 30,
///   onComplete: () => print('タイムアップ'),
/// );
/// ```
class StealthCommandHandler {
  // =========================================================
  // コマンド定数
  // =========================================================

  /// ダブルタップ → ボイスメモ（録音開始 or 停止・文字起こし）
  static const int cmdDoubleTap = MediaControlButton.doubleTap;

  /// トリプルタップ → フラッシュSOSパターン（band_protocol.dart の値を使用）
  static const int cmdTripleTap = MediaControlButton.tripleTap;

  /// 長押し → エスケープタイマー起動
  static const int cmdLongPress = MediaControlButton.longPress;

  // =========================================================
  // 依存オブジェクト
  // =========================================================

  /// フラッシュ制御クラス
  final FlashController _flash;

  /// ボイスメモ録音・文字起こしクラス
  final VoiceMemoRecorder _recorder;

  /// エスケープタイマークラス
  final EscapeTimer _escapeTimer;

  /// タイムライン記録クラス
  final TimelineLogger _logger;

  StealthCommandHandler({
    required FlashController flash,
    required VoiceMemoRecorder recorder,
    required EscapeTimer escapeTimer,
    required TimelineLogger logger,
  })  : _flash = flash,
        _recorder = recorder,
        _escapeTimer = escapeTimer,
        _logger = logger;

  // =========================================================
  // 公開メソッド
  // =========================================================

  /// BLEコマンドを受け取り、対応するステルス操作を実行する
  ///
  /// [command] : BLEメディアコントロールボタンから受信したコマンド値
  ///
  /// コマンドと動作の対応:
  /// - [cmdDoubleTap] (0x04) : 録音中なら停止・文字起こし、停止中なら録音開始
  /// - [cmdTripleTap] (0x03) : フラッシュSOSパターン点滅
  /// - 不明なコマンド : 無視する
  ///
  /// 注: [cmdLongPress] (0x01) はエスケープタイマーとして使用するが、
  /// このメソッドでは処理しない。呼び出し側が [startEscapeTimer] を直接呼ぶこと。
  Future<void> handleCommand(int command) async {
    switch (command) {
      case cmdDoubleTap:
        await _handleVoiceMemo();
      case cmdTripleTap:
        await _handleFlash();
      default:
        // 未知のコマンドは無視する（将来の拡張に備えてログのみ出力）
        // ignore: avoid_print
        print('[StealthCommandHandler] 未知のコマンドを無視しました: 0x${command.toRadixString(16)}');
    }
  }

  /// エスケープタイマーを起動する
  ///
  /// [seconds] : カウントダウンの秒数（デフォルト 30 秒）
  /// [onComplete] : タイムアップ時に呼ばれるコールバック
  ///
  /// タイムラインに「エスケープタイマー起動」イベントを記録する。
  /// すでに動作中のタイマーは自動的にキャンセルされてから再起動する。
  Future<void> startEscapeTimer({
    int seconds = 30,
    required VoidCallback onComplete,
  }) async {
    try {
      // タイマー起動前にタイムラインへ記録する
      await _logger.log(
        TimelineEventType.escapeTimerStarted,
        'エスケープタイマーを起動しました（$seconds秒）',
      );

      // カウントダウン開始
      _escapeTimer.start(seconds: seconds, onComplete: onComplete);

      // ignore: avoid_print
      print('[StealthCommandHandler] エスケープタイマー起動: $seconds秒');
    } catch (e) {
      // タイマー起動に失敗しても、アプリのクラッシュを防ぐ
      // ignore: avoid_print
      print('[StealthCommandHandler] エスケープタイマー起動エラー: $e');
    }
  }

  /// エスケープタイマーをキャンセルする
  ///
  /// タイマーが動作していない場合は何もしない。
  /// タイムラインへの記録は行わない（ユーザーが手動キャンセルしたのみ）。
  void cancelEscapeTimer() {
    try {
      _escapeTimer.cancel();
      // ignore: avoid_print
      print('[StealthCommandHandler] エスケープタイマーをキャンセルしました');
    } catch (e) {
      // キャンセル失敗は無視する（タイマーが動作していない場合など）
      // ignore: avoid_print
      print('[StealthCommandHandler] エスケープタイマーキャンセルエラー: $e');
    }
  }

  // =========================================================
  // プライベートメソッド
  // =========================================================

  /// トリプルタップ処理: フラッシュSOSパターンを実行してタイムラインに記録する
  Future<void> _handleFlash() async {
    try {
      // ignore: avoid_print
      print('[StealthCommandHandler] フラッシュSOS開始');

      // フラッシュ点滅前にタイムラインへ記録する
      // （点滅中にアプリが中断されても記録が残るように順序を先にする）
      await _logger.log(
        TimelineEventType.flashTriggered,
        'LEDフラッシュ（SOSパターン）を起動しました',
      );

      // SOSパターン点滅を実行する
      await _flash.flashSOS();

      // ignore: avoid_print
      print('[StealthCommandHandler] フラッシュSOS完了');
    } catch (e) {
      // フラッシュエラーはバックグラウンドでも致命的にしない
      // ignore: avoid_print
      print('[StealthCommandHandler] フラッシュ実行エラー: $e');
    }
  }

  /// ダブルタップ処理: 録音状態に応じて開始または停止・文字起こしを行う
  ///
  /// 録音中のとき : 録音を停止して文字起こしを実行する
  ///               （タイムラインへの記録は VoiceMemoRecorder 内で行われる）
  /// 停止中のとき : 録音を開始してタイムラインに記録する
  Future<void> _handleVoiceMemo() async {
    try {
      if (_recorder.isRecording) {
        // ---- 録音停止・文字起こし ----
        // ignore: avoid_print
        print('[StealthCommandHandler] 録音停止・文字起こし開始');

        // stopAndTranscribe の内部でタイムラインへの記録も完了する
        final result = await _recorder.stopAndTranscribe();

        if (result != null) {
          // ignore: avoid_print
          print(
            '[StealthCommandHandler] 文字起こし完了: '
            '${result.transcription != null ? "${result.transcription!.length}文字" : "失敗"}',
          );
        } else {
          // ignore: avoid_print
          print('[StealthCommandHandler] 録音停止に失敗しました');
        }
      } else {
        // ---- 録音開始 ----
        // ignore: avoid_print
        print('[StealthCommandHandler] 録音開始');

        final started = await _recorder.startRecording();

        if (started) {
          // 録音開始に成功した場合のみタイムラインに記録する
          await _logger.log(
            TimelineEventType.voiceMemo,
            'ボイスメモの録音を開始しました',
          );
          // ignore: avoid_print
          print('[StealthCommandHandler] 録音開始に成功しました');
        } else {
          // マイクパーミッションなし、またはハードウェアエラー
          // ignore: avoid_print
          print('[StealthCommandHandler] 録音開始に失敗しました（パーミッションまたはハードウェアエラー）');
        }
      }
    } catch (e) {
      // ボイスメモ処理のエラーはバックグラウンドでも致命的にしない
      // ignore: avoid_print
      print('[StealthCommandHandler] ボイスメモ処理エラー: $e');
    }
  }
}

// =========================================================
// Riverpod プロバイダー
// =========================================================

/// StealthCommandHandler の Riverpodプロバイダー
///
/// アプリ全体でシングルトンとして使用する。
/// 依存するプロバイダーはすべて ref.read で取得する（監視不要）。
final stealthCommandHandlerProvider = Provider<StealthCommandHandler>((ref) {
  return StealthCommandHandler(
    flash: ref.read(flashControllerProvider),
    recorder: ref.read(voiceMemoRecorderProvider),
    escapeTimer: ref.read(escapeTimerProvider),
    logger: ref.read(timelineLoggerProvider),
  );
});
