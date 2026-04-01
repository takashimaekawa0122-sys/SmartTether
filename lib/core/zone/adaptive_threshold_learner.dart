import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RSSI閾値を環境に応じて自動学習するクラス
///
/// 接続中に観測したRSSI値を蓄積し、
/// 「平均 - 標準偏差×1.5」を切断アラートの閾値として使う。
/// データが少ない間はデフォルト値（-75.0 dBm）で動作する（コールドスタート対応）。
class AdaptiveThresholdLearner {
  /// SharedPreferencesへの保存キー
  static const _kPrefsKey = 'rssi_threshold_data';

  /// データ不足時に返すデフォルト閾値（dBm）
  static const double _kDefaultThreshold = -75.0;

  /// 学習を開始するために必要な最低サンプル数
  static const int _kMinSamples = 10;

  /// 保持するサンプルの最大件数（古いものから削除）
  static const int _kMaxSamples = 200;

  /// 閾値計算に使う標準偏差の係数
  static const double _kStdDevMultiplier = 1.5;

  /// 接続中に取得したRSSIサンプル一覧
  final List<double> _samples = [];

  /// 現在計算済みの閾値（キャッシュ）
  double _threshold = _kDefaultThreshold;

  /// 未初期化フラグ（initialize()完了前にthresholdが参照された場合の防衛用）
  bool _initialized = false;

  /// SharedPreferencesから保存済みのサンプルを読み込む
  ///
  /// アプリ起動時に一度呼ぶ。
  /// 読み込みに失敗してもデフォルト値で動作を継続する。
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw == null) return;

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _samples.clear();
        for (final v in decoded) {
          if (v is num) _samples.add(v.toDouble());
        }
        _recalculate();
      }
    } catch (e) {
      // 読み込みエラーはデフォルト値のまま継続（ログのみ記録）
      // ignore: avoid_print
      print('[AdaptiveThresholdLearner] initialize error: $e');
    } finally {
      _initialized = true;
    }
  }

  /// 接続中のRSSI値を1件記録し、閾値を再計算する
  ///
  /// [rssi]: flutter_reactive_bleが返す生RSSI（dBm）。
  /// RSSISmoother通過後の平滑値を渡すことを推奨。
  Future<void> addConnectedSample(double rssi) async {
    // 未初期化の場合は保存済みデータを読み込んでから追記する
    if (!_initialized) {
      await initialize();
    }
    _samples.add(rssi);

    // 上限を超えた分は先頭（古いサンプル）から削除する
    while (_samples.length > _kMaxSamples) {
      _samples.removeAt(0);
    }

    _recalculate();
    _persistAsync();
  }

  /// 現在の閾値（dBm）
  ///
  /// サンプルが[_kMinSamples]件未満のときは[_kDefaultThreshold]を返す。
  double get threshold => _threshold;

  /// 現在のサンプル数
  int get sampleCount => _samples.length;

  /// 学習が有効かどうか（サンプルが十分に集まっているか）
  bool get isLearned => _samples.length >= _kMinSamples;

  /// サンプルをすべて消去し、閾値をデフォルトに戻す
  void reset() {
    _samples.clear();
    _threshold = _kDefaultThreshold;
    _persistAsync();
  }

  // ---------------------------------------------------------------------------
  // 内部処理
  // ---------------------------------------------------------------------------

  /// サンプルから閾値を再計算する
  ///
  /// サンプルが[_kMinSamples]件未満の場合はデフォルト値を維持する。
  void _recalculate() {
    if (_samples.length < _kMinSamples) {
      _threshold = _kDefaultThreshold;
      return;
    }

    final mean = _mean(_samples);
    final stdDev = _stdDev(_samples, mean);

    // 閾値 = 平均 - 標準偏差×1.5
    // 例: 平均-65dBm、標準偏差4dBm → 閾値 -71.0dBm
    _threshold = mean - stdDev * _kStdDevMultiplier;
  }

  /// リストの平均を返す
  double _mean(List<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// 母標準偏差を返す
  double _stdDev(List<double> values, double mean) {
    final variance =
        values.map((v) => pow(v - mean, 2).toDouble()).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance);
  }

  /// 非同期でSharedPreferencesに書き込む
  ///
  /// 書き込みの完了を待たずに返すため、UIをブロックしない。
  void _persistAsync() {
    _saveToPrefs().catchError((Object e) {
      // 保存失敗はアプリ動作に影響しないため握りつぶす
      // ignore: avoid_print
      print('[AdaptiveThresholdLearner] persist error: $e');
    });
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(_samples));
  }
}

/// Riverpodプロバイダー
///
/// アプリ全体で単一インスタンスを共有する。
/// プロバイダー生成時に initialize() を非同期で開始する。
/// 初期化完了前に addConnectedSample() が呼ばれた場合は内部で待機する。
final adaptiveThresholdProvider = Provider<AdaptiveThresholdLearner>((ref) {
  final learner = AdaptiveThresholdLearner();
  unawaited(learner.initialize());
  return learner;
});
