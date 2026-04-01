import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tether/core/zone/adaptive_threshold_learner.dart';

void main() {
  group('AdaptiveThresholdLearner', () {
    late AdaptiveThresholdLearner learner;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      learner = AdaptiveThresholdLearner();
      await learner.initialize(); // _initialized = true にしておかないと addConnectedSample が非同期になる
    });

    // -------------------------------------------------------------------------
    // 初期状態
    // -------------------------------------------------------------------------

    test('初期状態では sampleCount が 0', () {
      expect(learner.sampleCount, equals(0));
    });

    test('初期状態では isLearned が false', () {
      expect(learner.isLearned, isFalse);
    });

    test('初期状態では threshold がデフォルト値（-75.0）', () {
      expect(learner.threshold, equals(-75.0));
    });

    // -------------------------------------------------------------------------
    // サンプル10件未満はデフォルト閾値
    // -------------------------------------------------------------------------

    test('サンプル9件以下のとき threshold はデフォルト値（-75.0）のまま', () {
      for (var i = 0; i < 9; i++) {
        learner.addConnectedSample(-65.0);
      }

      expect(learner.threshold, equals(-75.0));
      expect(learner.isLearned, isFalse);
    });

    test('サンプル1件のとき threshold はデフォルト値（-75.0）', () {
      learner.addConnectedSample(-60.0);
      expect(learner.threshold, equals(-75.0));
    });

    // -------------------------------------------------------------------------
    // 10件以上で学習した閾値が返る
    // -------------------------------------------------------------------------

    test('サンプル10件以上で isLearned が true になる', () {
      for (var i = 0; i < 10; i++) {
        learner.addConnectedSample(-65.0);
      }
      expect(learner.isLearned, isTrue);
    });

    test('10件以上で threshold がデフォルトから変化する', () {
      // 全部 -65.0 を10件追加
      for (var i = 0; i < 10; i++) {
        learner.addConnectedSample(-65.0);
      }
      // 標準偏差0のとき threshold = mean - 0*1.5 = -65.0
      expect(learner.threshold, closeTo(-65.0, 0.001));
    });

    test('閾値は 平均 - 標準偏差×1.5 で計算される', () {
      // 分散のあるデータを10件追加
      final samples = [-60.0, -62.0, -64.0, -66.0, -68.0,
                       -70.0, -72.0, -74.0, -76.0, -78.0];
      for (final s in samples) {
        learner.addConnectedSample(s);
      }

      final mean = samples.reduce((a, b) => a + b) / samples.length;
      final variance = samples
          .map((v) => pow(v - mean, 2).toDouble())
          .reduce((a, b) => a + b) / samples.length;
      final stdDev = sqrt(variance);
      final expectedThreshold = mean - stdDev * 1.5;

      expect(learner.threshold, closeTo(expectedThreshold, 0.001));
    });

    test('同じ値10件のとき threshold は平均値に等しい（標準偏差0）', () {
      for (var i = 0; i < 10; i++) {
        learner.addConnectedSample(-70.0);
      }
      expect(learner.threshold, closeTo(-70.0, 0.001));
    });

    // -------------------------------------------------------------------------
    // 最大サンプル数を超えたとき古いサンプルが削除される
    // -------------------------------------------------------------------------

    test('200件を超えると古いサンプルが削除されてサンプル数が200を超えない', () {
      for (var i = 0; i < 201; i++) {
        learner.addConnectedSample(-65.0 - i * 0.01);
      }
      expect(learner.sampleCount, equals(200));
    });

    // -------------------------------------------------------------------------
    // reset()
    // -------------------------------------------------------------------------

    test('reset() 後は sampleCount が 0 になる', () {
      for (var i = 0; i < 10; i++) {
        learner.addConnectedSample(-65.0);
      }
      learner.reset();

      expect(learner.sampleCount, equals(0));
    });

    test('reset() 後は threshold がデフォルト値（-75.0）に戻る', () {
      for (var i = 0; i < 10; i++) {
        learner.addConnectedSample(-65.0);
      }
      learner.reset();

      expect(learner.threshold, equals(-75.0));
    });

    test('reset() 後は isLearned が false になる', () {
      for (var i = 0; i < 10; i++) {
        learner.addConnectedSample(-65.0);
      }
      learner.reset();

      expect(learner.isLearned, isFalse);
    });

    // -------------------------------------------------------------------------
    // initialize() で SharedPreferences からサンプルを読み込む
    // -------------------------------------------------------------------------

    test('initialize() で保存済みサンプルを読み込み閾値が復元される', () async {
      // 10件のサンプルを SharedPreferences に直接書き込む
      final samples = List.generate(10, (i) => -65.0 - i.toDouble());
      SharedPreferences.setMockInitialValues({
        'rssi_threshold_data': jsonEncode(samples),
      });

      final learnerWithData = AdaptiveThresholdLearner();
      await learnerWithData.initialize();

      expect(learnerWithData.sampleCount, equals(10));
      expect(learnerWithData.isLearned, isTrue);
      expect(learnerWithData.threshold, isNot(equals(-75.0)));
    });

    test('initialize() で保存データが空のとき sampleCount は 0 のまま', () async {
      SharedPreferences.setMockInitialValues({});

      await learner.initialize();

      expect(learner.sampleCount, equals(0));
      expect(learner.threshold, equals(-75.0));
    });

    test('initialize() で不正な JSON が保存されていてもクラッシュしない', () async {
      SharedPreferences.setMockInitialValues({
        'rssi_threshold_data': 'not valid json {{{',
      });

      final learnerWithBadData = AdaptiveThresholdLearner();
      await expectLater(learnerWithBadData.initialize(), completes);

      // デフォルト値のまま動作を継続する
      expect(learnerWithBadData.threshold, equals(-75.0));
    });

    // -------------------------------------------------------------------------
    // サンプルの追加と閾値の継続的な更新
    // -------------------------------------------------------------------------

    test('サンプルを追加するたびに sampleCount が増加する', () {
      learner.addConnectedSample(-65.0);
      expect(learner.sampleCount, equals(1));

      learner.addConnectedSample(-66.0);
      expect(learner.sampleCount, equals(2));
    });

    test('9件から10件に増えるタイミングで isLearned が true に変わる', () {
      for (var i = 0; i < 9; i++) {
        learner.addConnectedSample(-65.0);
      }
      expect(learner.isLearned, isFalse);

      learner.addConnectedSample(-65.0);
      expect(learner.isLearned, isTrue);
    });
  });
}
