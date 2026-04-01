import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/ble/rssi_smoother.dart';

void main() {
  group('RSSISmoother', () {
    late RSSISmoother smoother;

    setUp(() {
      smoother = RSSISmoother(windowSize: 5);
    });

    // -------------------------------------------------------------------------
    // 初期状態
    // -------------------------------------------------------------------------

    test('初期状態ではデータが0件', () {
      expect(smoother.sampleCount, equals(0));
    });

    test('初期状態では isReady が false', () {
      expect(smoother.isReady, isFalse);
    });

    test('データが空のとき smoothedValue は -999 を返す', () {
      expect(smoother.smoothedValue, equals(-999));
    });

    // -------------------------------------------------------------------------
    // サンプル数が window サイズ未満の場合
    // -------------------------------------------------------------------------

    test('サンプル1件のとき smoothedValue は -999（外れ値除去には3件必要）', () {
      smoother.addValue(-60);
      expect(smoother.smoothedValue, equals(-999));
    });

    test('サンプル2件のとき smoothedValue は -999（外れ値除去には3件必要）', () {
      smoother.addValue(-60);
      smoother.addValue(-70);
      // 3件未満は誤検知防止のため -999 を返す
      expect(smoother.smoothedValue, equals(-999));
    });

    test('サンプル数が windowSize 未満のとき isReady は false', () {
      smoother.addValue(-60);
      smoother.addValue(-70);
      expect(smoother.isReady, isFalse);
    });

    // -------------------------------------------------------------------------
    // 外れ値除去付き移動平均（3件以上）
    // -------------------------------------------------------------------------

    test('3件以上のとき最大・最小を除いた平均を返す', () {
      // [-60, -70, -65] → ソート: [-70, -65, -60]
      // 最大・最小を除くと [-65] だけ → 平均 -65.0
      smoother.addValue(-60);
      smoother.addValue(-70);
      smoother.addValue(-65);
      expect(smoother.smoothedValue, closeTo(-65.0, 0.001));
    });

    test('5件の移動平均が正しく計算される（外れ値除去あり）', () {
      // [-60, -70, -65, -68, -62]
      // ソート: [-70, -68, -65, -62, -60]
      // 最大(-60)・最小(-70)を除く: [-68, -65, -62] → 平均 ≒ -65.0
      smoother.addValue(-60);
      smoother.addValue(-70);
      smoother.addValue(-65);
      smoother.addValue(-68);
      smoother.addValue(-62);

      expect(smoother.smoothedValue, closeTo(-65.0, 0.001));
    });

    test('windowSize 件に達したとき isReady が true になる', () {
      for (var i = 0; i < 5; i++) {
        smoother.addValue(-60);
      }
      expect(smoother.isReady, isTrue);
    });

    // -------------------------------------------------------------------------
    // 古い値の押し出し
    // -------------------------------------------------------------------------

    test('windowSize を超えると古い値が押し出される', () {
      // windowSize=5 のスムーザーに6件追加
      // 最初の -60 が押し出されて残るのは後ろの5件になるはず
      smoother.addValue(-60); // これが押し出される
      smoother.addValue(-70);
      smoother.addValue(-70);
      smoother.addValue(-70);
      smoother.addValue(-70);
      smoother.addValue(-70); // 6件目を追加 → -60が除去される

      expect(smoother.sampleCount, equals(5));
      // 全件 -70 なので smoothedValue は -70 になるはず
      expect(smoother.smoothedValue, closeTo(-70.0, 0.001));
    });

    test('windowSize を超えてもサンプル数は windowSize を超えない', () {
      for (var i = 0; i < 10; i++) {
        smoother.addValue(-60 - i);
      }
      expect(smoother.sampleCount, equals(5));
    });

    // -------------------------------------------------------------------------
    // reset
    // -------------------------------------------------------------------------

    test('reset 後はデータが0件になる', () {
      smoother.addValue(-60);
      smoother.addValue(-70);
      smoother.reset();

      expect(smoother.sampleCount, equals(0));
      expect(smoother.isReady, isFalse);
    });

    test('reset 後の smoothedValue は -999 を返す', () {
      smoother.addValue(-60);
      smoother.reset();

      expect(smoother.smoothedValue, equals(-999));
    });

    // -------------------------------------------------------------------------
    // デフォルト windowSize
    // -------------------------------------------------------------------------

    test('引数なしのとき windowSize はデフォルト7', () {
      final defaultSmoother = RSSISmoother();
      expect(defaultSmoother.isReady, isFalse);

      for (var i = 0; i < 7; i++) {
        defaultSmoother.addValue(-60);
      }
      expect(defaultSmoother.isReady, isTrue);
    });
  });
}
