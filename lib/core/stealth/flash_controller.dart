/// カメラフラッシュ（トーチ）の制御クラス
///
/// torch_lightを使いカメラLEDフラッシュをON/OFFする。
/// SOSパターン（短3回→長3回→短3回）の点滅にも対応。
/// ハードウェア操作はすべてtry-catchで保護する。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:torch_light/torch_light.dart';

/// カメラフラッシュコントローラー
///
/// 使い方:
/// ```dart
/// final flash = ref.read(flashControllerProvider);
/// await flash.turnOn();        // フラッシュON
/// await flash.turnOff();       // フラッシュOFF
/// await flash.flashSOS();      // SOSパターン点滅
/// ```
class FlashController {
  /// フラッシュが現在ONかどうかを追跡するフラグ
  /// torch_lightには状態取得APIがないため自前で管理する
  bool _isOn = false;

  /// フラッシュが現在ONかどうか
  bool get isOn => _isOn;

  /// フラッシュをONにする
  ///
  /// torch_lightの EnableTorchException をキャッチして処理する。
  Future<void> turnOn() async {
    try {
      await TorchLight.enableTorch();
      _isOn = true;
    } on EnableTorchException catch (e) {
      // フラッシュ有効化に失敗（ハードウェア非対応・カメラ使用中など）
      // ignore: avoid_print
      print('[FlashController] フラッシュONに失敗: $e');
    } catch (e) {
      // その他の予期しないエラー
      // ignore: avoid_print
      print('[FlashController] 予期しないエラー（turnOn）: $e');
    }
  }

  /// フラッシュをOFFにする
  ///
  /// torch_lightの DisableTorchException をキャッチして処理する。
  Future<void> turnOff() async {
    try {
      await TorchLight.disableTorch();
      _isOn = false;
    } on DisableTorchException catch (e) {
      // フラッシュ無効化に失敗
      _isOn = false;
      // ignore: avoid_print
      print('[FlashController] フラッシュOFFに失敗: $e');
    } catch (e) {
      // その他の予期しないエラー
      _isOn = false;
      // ignore: avoid_print
      print('[FlashController] 予期しないエラー（turnOff）: $e');
    }
  }

  /// SOSパターンでフラッシュを点滅させる
  ///
  /// 国際モールス符号のSOS: 短3回（・・・）→長3回（---）→短3回（・・・）
  ///
  /// 短点滅: 200ms ON → 200ms OFF
  /// 長点滅: 600ms ON → 200ms OFF
  Future<void> flashSOS() async {
    // 短点滅（・）のパターン
    Future<void> shortFlash() async {
      await turnOn();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await turnOff();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // 長点滅（-）のパターン
    Future<void> longFlash() async {
      await turnOn();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await turnOff();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    try {
      // ・・・（短3回）
      for (var i = 0; i < 3; i++) {
        await shortFlash();
      }
      // ---（長3回）
      for (var i = 0; i < 3; i++) {
        await longFlash();
      }
      // ・・・（短3回）
      for (var i = 0; i < 3; i++) {
        await shortFlash();
      }
    } catch (e) {
      // SOSパターン実行中のエラーは途中で終了させる
      // フラッシュが残ったままにならないよう、必ずOFFにする
      await turnOff();
      // ignore: avoid_print
      print('[FlashController] SOSパターン実行中にエラー: $e');
    }
  }
}

/// FlashController の Riverpodプロバイダー
///
/// アプリ全体でシングルトンとして使用する。
final flashControllerProvider = Provider<FlashController>((ref) {
  return FlashController();
});
