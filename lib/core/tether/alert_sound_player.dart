/// アラート音の再生を管理するクラス
///
/// just_audioを使い、assets/sounds/alert.mp3 をループ再生する。
/// MP3ファイルが存在しない場合は HapticFeedback による繰り返し振動にフォールバックする。
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

  /// 振動フォールバック用タイマー
  Timer? _hapticTimer;

  /// 現在再生中かどうか（MP3再生 or 振動フォールバック）
  bool get isPlaying => _player.playing || _hapticTimer != null;

  /// アラート音のループ再生を開始する
  ///
  /// LoopMode.one（1曲リピート）でassets/sounds/alert.mp3を再生する。
  /// MP3の読み込みに失敗した場合は HapticFeedback による繰り返し振動にフォールバックする。
  /// すでに再生中の場合は何もしない。
  Future<void> startAlert() async {
    // 重複再生を防ぐ
    if (isPlaying) return;

    try {
      // アセットを読み込んでループモードを設定
      await _player.setAsset('assets/sounds/alert.mp3');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (e) {
      // ignore: avoid_print
      print('[AlertSoundPlayer] MP3再生失敗、振動にフォールバック: $e');
      // MP3がない場合はタイマーで繰り返し振動
      _startHapticLoop();
    }
  }

  /// アラート音を停止する
  ///
  /// 再生中でない場合は何もしない。MP3再生・振動フォールバックの両方を停止する。
  Future<void> stopAlert() async {
    if (!isPlaying) return;

    try {
      await _player.stop();
    } catch (e) {
      // 停止失敗時もクラッシュさせない
      // ignore: avoid_print
      print('[AlertSoundPlayer] 再生停止に失敗: $e');
    }

    _stopHapticLoop();
  }

  /// 1秒ごとに HapticFeedback.heavyImpact() を繰り返す振動ループを開始する
  void _startHapticLoop() {
    _hapticTimer?.cancel();
    // 即時1回目を実行してからタイマーで継続する
    HapticFeedback.heavyImpact();
    _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  /// 振動ループを停止する
  void _stopHapticLoop() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  /// リソースを解放する
  ///
  /// Riverpodの ref.onDispose から呼び出される。
  void dispose() {
    _stopHapticLoop();
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
