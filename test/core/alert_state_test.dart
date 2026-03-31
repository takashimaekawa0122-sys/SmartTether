import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/tether/alert_state.dart';

void main() {
  group('TetherState', () {
    // -------------------------------------------------------------------------
    // isAlerting プロパティ
    // -------------------------------------------------------------------------

    group('isAlerting', () {
      test('sleeping は isAlerting が false', () {
        expect(TetherState.sleeping.isAlerting, isFalse);
      });

      test('monitoring は isAlerting が false', () {
        expect(TetherState.monitoring.isAlerting, isFalse);
      });

      test('grace は isAlerting が false', () {
        expect(TetherState.grace.isAlerting, isFalse);
      });

      test('warning は isAlerting が true', () {
        expect(TetherState.warning.isAlerting, isTrue);
      });

      test('confirmed は isAlerting が true', () {
        expect(TetherState.confirmed.isAlerting, isTrue);
      });

      test('standby は isAlerting が false', () {
        expect(TetherState.standby.isAlerting, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // label プロパティ
    // -------------------------------------------------------------------------

    group('label', () {
      test('sleeping のラベルが正しい', () {
        expect(TetherState.sleeping.label, equals('安全圏・監視スリープ中'));
      });

      test('monitoring のラベルが正しい', () {
        expect(TetherState.monitoring.label, equals('危険圏・監視中'));
      });

      test('grace のラベルが正しい', () {
        expect(TetherState.grace.label, equals('再接続を試行中...'));
      });

      test('warning のラベルが正しい', () {
        expect(TetherState.warning.label, equals('警告：バンドが離れています'));
      });

      test('confirmed のラベルが正しい', () {
        expect(TetherState.confirmed.label, contains('置き忘れを検知しました'));
      });

      test('standby のラベルが正しい', () {
        expect(TetherState.standby.label, equals('お留守番モード'));
      });
    });

    // -------------------------------------------------------------------------
    // 遷移条件の確認（コメント定義との整合性）
    // -------------------------------------------------------------------------

    group('状態の定義', () {
      test('全部で6種類の状態が存在する', () {
        expect(TetherState.values.length, equals(6));
      });

      test('isAlerting が true になるのは warning と confirmed のみ', () {
        final alertingStates =
            TetherState.values.where((s) => s.isAlerting).toList();
        expect(alertingStates, containsAll([TetherState.warning, TetherState.confirmed]));
        expect(alertingStates.length, equals(2));
      });

      test('isAlerting が false になるのは4種類の状態', () {
        final nonAlertingStates =
            TetherState.values.where((s) => !s.isAlerting).toList();
        expect(nonAlertingStates.length, equals(4));
      });
    });
  });
}
