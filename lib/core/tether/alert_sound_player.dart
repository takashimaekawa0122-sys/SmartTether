/// アラート音の再生を管理するクラス
///
/// assets/sounds/alert.wav が存在すれば just_audio でループ再生する。
/// WAV が存在しない場合は SystemSound（iOS: 1005 アラート音）を使い、
/// それも失敗した場合は HapticFeedback による繰り返し振動にフォールバックする。
/// バックグラウンドでも動作するよう、ハードウェア操作はすべてtry-catchで保護する。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// アラート音プレイヤー
///
/// 使い方:
/// ```dart
/// final player = ref.read(alertSoundPlayerProvider);
/// await player.startAlert();  // 再生開始
/// await player.stopAlert();   // 停止
/// ```
class AlertSoundPlayer {
  /// just_audioのプレイヤーインスタンス
  final AudioPlayer _player = AudioPlayer();

  /// フォールバック用タイマー（SystemSound繰り返し or Haptic繰り返し）
  Timer? _fallbackTimer;

  /// startAlert()の非同期処理中かどうか（重複呼び出しガード用）
  bool _isStarting = false;

  /// 現在再生中かどうか（MP3再生 or フォールバック）
  bool get isPlaying => _player.playing || _fallbackTimer != null;

  /// アラート音のループ再生を開始する
  ///
  /// 優先順位:
  ///   1. assets/sounds/alert.wav をループ再生（just_audio）
  ///   2. SystemSound.play(1005)（iOSアラート音）を繰り返し再生
  ///   3. HapticFeedback.heavyImpact() を繰り返し（最終フォールバック）
  ///
  /// すでに再生中の場合は何もしない。
  Future<void> startAlert() async {
    // 再生中または非同期処理中の重複呼び出しを防ぐ
    if (isPlaying || _isStarting) return;
    _isStarting = true;

    try {
      // アセットを読み込んでループモードを設定
      await _player.setAsset('assets/sounds/alert.wav');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (e) {
      // ignore: avoid_print
      print('[AlertSoundPlayer] MP3再生失敗、SystemSoundにフォールバック: $e');
      // MP3がない場合はSystemSoundを繰り返し再生する
      _startSystemSoundLoop();
    } finally {
      _isStarting = false;
    }
  }

  /// アラート音を停止する
  ///
  /// 再生中でない場合は何もしない。MP3再生・フォールバックの両方を停止する。
  Future<void> stopAlert() async {
    if (!isPlaying) return;

    try {
      await _player.stop();
    } catch (e) {
      // 停止失敗時もクラッシュさせない
      // ignore: avoid_print
      print('[AlertSoundPlayer] 再生停止に失敗: $e');
    }

    _stopFallbackLoop();
  }

  /// 2秒ごとに SystemSound.play() + HapticFeedback を繰り返すループを開始する
  ///
  /// iOS では SystemSound ID 1005（アラート音）を再生する。
  /// Android では SystemSound.play は効果が限定的なため、
  /// HapticFeedback も併用して確実にユーザーに通知する。
  void _startSystemSoundLoop() {
    _fallbackTimer?.cancel();
    // 即時1回目を実行してからタイマーで継続する
    _playSystemSoundWithHaptic();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _playSystemSoundWithHaptic();
    });
  }

  /// SystemSound と HapticFeedback を同時に再生する
  void _playSystemSoundWithHaptic() {
    try {
      // iOS: 1005 はアラート音。Android: beep音。
      SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      // ignore: avoid_print
      print('[AlertSoundPlayer] SystemSound再生失敗: $e');
    }
    try {
      HapticFeedback.heavyImpact();
    } catch (e) {
      // ignore: avoid_print
      print('[AlertSoundPlayer] HapticFeedback失敗: $e');
    }
  }

  /// フォールバックループを停止する
  void _stopFallbackLoop() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  /// リソースを解放する
  ///
  /// Riverpodの ref.onDispose から呼び出される。
  void dispose() {
    _stopFallbackLoop();
    try {
      _player.dispose();
    } catch (e) {
      // ignore: avoid_print
      print('[AlertSoundPlayer] dispose に失敗: $e');
    }
  }
}

/// AlertSoundPlayer の Riverpodプロバイダー
///
/// アプリ全体でシングルトンとして使用する。
/// アプリ終了時に ref.onDispose で自動的に dispose される。
final alertSoundPlayerProvider = Provider<AlertSoundPlayer>((ref) {
  final player = AlertSoundPlayer();

  // Riverpodがこのプロバイダーを破棄するときにdisposeを呼ぶ
  ref.onDispose(player.dispose);

  return player;
});
