import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tether/core/timeline/timeline_entry.dart';
import 'package:smart_tether/core/timeline/timeline_logger.dart';

void main() {
  group('TimelineLogger', () {
    late TimelineLogger logger;

    setUp(() async {
      // SharedPreferences をモック初期値で初期化
      SharedPreferences.setMockInitialValues({});
      logger = TimelineLogger();
    });

    // -------------------------------------------------------------------------
    // log() でエントリが追加される
    // -------------------------------------------------------------------------

    test('log() を呼ぶとエントリが1件追加される', () async {
      await logger.log(TimelineEventType.warning, '置き忘れ警告');

      expect(logger.entries.length, equals(1));
    });

    test('log() で追加したエントリの type と message が正しい', () async {
      await logger.log(TimelineEventType.alert, '置き忘れ確定');

      final entry = logger.entries.first;
      expect(entry.type, equals(TimelineEventType.alert));
      expect(entry.message, equals('置き忘れ確定'));
    });

    test('log() を複数回呼ぶと複数件追加される', () async {
      await logger.log(TimelineEventType.monitoringStarted, '監視開始');
      await logger.log(TimelineEventType.warning, '警告');
      await logger.log(TimelineEventType.alert, '確定');

      expect(logger.entries.length, equals(3));
    });

    test('最新のエントリが先頭に来る（新しい順）', () async {
      await logger.log(TimelineEventType.monitoringStarted, '1番目');
      await logger.log(TimelineEventType.warning, '2番目');

      expect(logger.entries.first.message, equals('2番目'));
      expect(logger.entries.last.message, equals('1番目'));
    });

    test('オプションフィールド付きで log() が正しく動作する', () async {
      await logger.log(
        TimelineEventType.voiceMemo,
        'ボイスメモ',
        transcription: '文字起こし結果',
        audioFilePath: '/path/to/memo.m4a',
        audioDuration: const Duration(seconds: 20),
      );

      final entry = logger.entries.first;
      expect(entry.transcription, equals('文字起こし結果'));
      expect(entry.audioFilePath, equals('/path/to/memo.m4a'));
      expect(entry.audioDuration, equals(const Duration(seconds: 20)));
    });

    // -------------------------------------------------------------------------
    // リスナーが呼ばれること
    // -------------------------------------------------------------------------

    test('log() するとリスナーが呼ばれる', () async {
      TimelineEntry? received;
      logger.addListener((entry) {
        received = entry;
      });

      await logger.log(TimelineEventType.warning, '警告テスト');

      expect(received, isNotNull);
      expect(received!.message, equals('警告テスト'));
    });

    test('複数のリスナーがそれぞれ呼ばれる', () async {
      int callCount = 0;
      logger.addListener((_) => callCount++);
      logger.addListener((_) => callCount++);

      await logger.log(TimelineEventType.alert, '確定');

      expect(callCount, equals(2));
    });

    test('removeListener 後はリスナーが呼ばれない', () async {
      int callCount = 0;
      void listener(TimelineEntry _) => callCount++;

      logger.addListener(listener);
      logger.removeListener(listener);

      await logger.log(TimelineEventType.warning, '警告');

      expect(callCount, equals(0));
    });

    // -------------------------------------------------------------------------
    // 最大件数を超えないこと
    // -------------------------------------------------------------------------

    test('100件を超えると古いエントリが削除される', () async {
      // 101件ログに追加する
      for (var i = 0; i < 101; i++) {
        await logger.log(TimelineEventType.monitoringStarted, 'エントリ$i');
      }

      // 上限の100件を超えないこと
      expect(logger.entries.length, equals(100));
    });

    test('100件ちょうどのときはすべて保持される', () async {
      for (var i = 0; i < 100; i++) {
        await logger.log(TimelineEventType.monitoringStarted, 'エントリ$i');
      }

      expect(logger.entries.length, equals(100));
    });

    test('100件を超えたとき最古のエントリが削除される', () async {
      // 最初のエントリを「最古マーカー」として識別できるようにする
      await logger.log(TimelineEventType.monitoringStarted, '最古のエントリ');

      for (var i = 1; i < 101; i++) {
        await logger.log(TimelineEventType.warning, 'エントリ$i');
      }

      // 最古のエントリ（リストの末尾）が削除されていること
      final messages = logger.entries.map((e) => e.message).toList();
      expect(messages, isNot(contains('最古のエントリ')));
    });

    // -------------------------------------------------------------------------
    // entries はイミュータブル
    // -------------------------------------------------------------------------

    test('entries は変更不可なリストを返す', () async {
      await logger.log(TimelineEventType.warning, '警告');

      final entries = logger.entries;
      // UnmodifiableListMixin は型チェック前に UnsupportedError を投げないため、
      // 有効な型の値を渡して UnsupportedError を確認する
      final dummy = TimelineEntry(
        id: 'dummy',
        timestamp: DateTime(2026, 3, 25),
        type: TimelineEventType.warning,
        message: 'dummy',
      );
      expect(
        () => entries.add(dummy),
        throwsUnsupportedError,
      );
    });

    // -------------------------------------------------------------------------
    // load() / 永続化のテスト
    // -------------------------------------------------------------------------

    test('log() 後に新しい TimelineLogger でロードするとエントリが復元される', () async {
      await logger.log(TimelineEventType.alert, '復元テスト');

      // 別のインスタンスで読み込む
      final logger2 = TimelineLogger();
      await logger2.load();

      expect(logger2.entries.length, equals(1));
      expect(logger2.entries.first.message, equals('復元テスト'));
    });

    test('空の SharedPreferences で load() を呼んでもエラーにならない', () async {
      await expectLater(logger.load(), completes);
      expect(logger.entries, isEmpty);
    });
  });
}
