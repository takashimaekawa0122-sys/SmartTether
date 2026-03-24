/// アラート音の再生を管理するクラス
///
/// just_audioを使い、assets/sounds/alert.mp3 をループ再生する。
/// バックグラウンドでも動作するよう、ハードウェア操作はすべてtry-catchで保護する。
library;

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

  /// 現在再生中かどうか
  bool get isPlaying => _player.playing;

  /// アラート音のループ再生を開始する
  ///
  /// LoopMode.one（1曲リピート）でassets/sounds/alert.mp3を再生する。
  /// すでに再生中の場合は何もしない。
  Future<void> startAlert() async {
    // 重複再生を防ぐ
    if (_player.playing) return;

    try {
      // アセットを読み込んでループモードを設定
      await _player.setAsset('assets/sounds/alert.mp3');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (e) {
      // 再生失敗時はログだけ記録してクラッシュさせない
      // バックグラウンドでの失敗は致命的にしてはいけない
      // ignore: avoid_print
      print('[AlertSoundPlayer] 再生開始に失敗: $e');
    }
  }

  /// アラート音を停止する
  ///
  /// 再生中でない場合は何もしない。
  Future<void> stopAlert() async {
    if (!_player.playing) return;

    try {
      await _player.stop();
    } catch (e) {
      // 停止失敗時もクラッシュさせない
      // ignore: avoid_print
      print('[AlertSoundPlayer] 再生停止に失敗: $e');
    }
  }

  /// リソースを解放する
  ///
  /// Riverpodの ref.onDispose から呼び出される。
  void dispose() {
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
