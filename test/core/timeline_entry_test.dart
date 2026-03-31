import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/timeline/timeline_entry.dart';

void main() {
  group('TimelineEntry', () {
    // -------------------------------------------------------------------------
    // 生成
    // -------------------------------------------------------------------------

    test('必須フィールドだけで生成できる', () {
      final entry = TimelineEntry(
        id: 'test-id-001',
        timestamp: DateTime(2026, 3, 25, 10, 0, 0),
        type: TimelineEventType.warning,
        message: '置き忘れ警告',
      );

      expect(entry.id, equals('test-id-001'));
      expect(entry.type, equals(TimelineEventType.warning));
      expect(entry.message, equals('置き忘れ警告'));
      expect(entry.transcription, isNull);
      expect(entry.audioFilePath, isNull);
      expect(entry.audioDuration, isNull);
    });

    test('オプションフィールドを含めて生成できる', () {
      final entry = TimelineEntry(
        id: 'test-id-002',
        timestamp: DateTime(2026, 3, 25, 11, 0, 0),
        type: TimelineEventType.voiceMemo,
        message: 'ボイスメモ記録',
        transcription: '今日の買い物メモ',
        audioFilePath: '/path/to/audio.m4a',
        audioDuration: const Duration(seconds: 30),
      );

      expect(entry.transcription, equals('今日の買い物メモ'));
      expect(entry.audioFilePath, equals('/path/to/audio.m4a'));
      expect(entry.audioDuration, equals(const Duration(seconds: 30)));
    });

    // -------------------------------------------------------------------------
    // toJson / fromJson の往復テスト
    // -------------------------------------------------------------------------

    group('toJson / fromJson', () {
      test('必須フィールドだけの往復変換が正しい', () {
        final original = TimelineEntry(
          id: 'round-trip-001',
          timestamp: DateTime(2026, 3, 25, 9, 30, 0),
          type: TimelineEventType.alert,
          message: '置き忘れ確定',
        );

        final json = original.toJson();
        final restored = TimelineEntry.fromJson(json);

        expect(restored.id, equals(original.id));
        expect(restored.timestamp, equals(original.timestamp));
        expect(restored.type, equals(original.type));
        expect(restored.message, equals(original.message));
        expect(restored.transcription, isNull);
        expect(restored.audioFilePath, isNull);
        expect(restored.audioDuration, isNull);
      });

      test('オプションフィールドを含む往復変換が正しい', () {
        final original = TimelineEntry(
          id: 'round-trip-002',
          timestamp: DateTime(2026, 3, 25, 12, 0, 0),
          type: TimelineEventType.voiceMemo,
          message: 'ボイスメモ',
          transcription: 'テスト音声テキスト',
          audioFilePath: '/recordings/memo.m4a',
          audioDuration: const Duration(seconds: 45),
        );

        final json = original.toJson();
        final restored = TimelineEntry.fromJson(json);

        expect(restored.transcription, equals(original.transcription));
        expect(restored.audioFilePath, equals(original.audioFilePath));
        expect(restored.audioDuration, equals(original.audioDuration));
      });

      test('toJson の timestamp は ISO8601 文字列形式', () {
        final entry = TimelineEntry(
          id: 'json-format-test',
          timestamp: DateTime.utc(2026, 3, 25, 8, 0, 0),
          type: TimelineEventType.monitoringStarted,
          message: '監視開始',
        );

        final json = entry.toJson();
        expect(json['timestamp'], isA<String>());
        // DateTime.parse で復元できることを確認
        expect(() => DateTime.parse(json['timestamp'] as String), returnsNormally);
      });

      test('toJson の type は enum の name 文字列', () {
        final entry = TimelineEntry(
          id: 'type-test',
          timestamp: DateTime(2026, 3, 25),
          type: TimelineEventType.theftDetected,
          message: '盗難検知',
        );

        final json = entry.toJson();
        expect(json['type'], equals('theftDetected'));
      });

      test('audioDurationMs が null のとき toJson は null を含む', () {
        final entry = TimelineEntry(
          id: 'null-duration',
          timestamp: DateTime(2026, 3, 25),
          type: TimelineEventType.warning,
          message: '警告',
        );

        final json = entry.toJson();
        expect(json['audioDurationMs'], isNull);
      });

      test('audioDuration が設定されているとき toJson は ms 整数を含む', () {
        final entry = TimelineEntry(
          id: 'duration-test',
          timestamp: DateTime(2026, 3, 25),
          type: TimelineEventType.voiceMemo,
          message: 'メモ',
          audioDuration: const Duration(milliseconds: 12345),
        );

        final json = entry.toJson();
        expect(json['audioDurationMs'], equals(12345));
      });

      test('不明な type 文字列は monitoringStarted にフォールバックする', () {
        final json = {
          'id': 'fallback-test',
          'timestamp': '2026-03-25T00:00:00.000',
          'type': 'unknownEventType',
          'message': 'テスト',
          'transcription': null,
          'audioFilePath': null,
          'audioDurationMs': null,
        };

        final entry = TimelineEntry.fromJson(json);
        expect(entry.type, equals(TimelineEventType.monitoringStarted));
      });
    });

    // -------------------------------------------------------------------------
    // 全 TimelineEventType の name 文字列変換
    // -------------------------------------------------------------------------

    group('TimelineEventType の name 文字列', () {
      final expectedNames = {
        TimelineEventType.monitoringStarted: 'monitoringStarted',
        TimelineEventType.monitoringStopped: 'monitoringStopped',
        TimelineEventType.monitoringPaused: 'monitoringPaused',
        TimelineEventType.warning: 'warning',
        TimelineEventType.alert: 'alert',
        TimelineEventType.theftDetected: 'theftDetected',
        TimelineEventType.voiceMemo: 'voiceMemo',
        TimelineEventType.flashTriggered: 'flashTriggered',
        TimelineEventType.escapeTimerStarted: 'escapeTimerStarted',
        TimelineEventType.batteryLow: 'batteryLow',
        TimelineEventType.bandForgotten: 'bandForgotten',
        TimelineEventType.systemShutdown: 'systemShutdown',
      };

      for (final entry in expectedNames.entries) {
        test('${entry.key} の name が "${entry.value}"', () {
          expect(entry.key.name, equals(entry.value));
        });
      }

      test('全 TimelineEventType は toJson/fromJson で往復変換できる', () {
        for (final eventType in TimelineEventType.values) {
          final original = TimelineEntry(
            id: 'type-roundtrip-${eventType.name}',
            timestamp: DateTime(2026, 3, 25),
            type: eventType,
            message: 'テスト: ${eventType.name}',
          );

          final restored = TimelineEntry.fromJson(original.toJson());
          expect(restored.type, equals(eventType),
              reason: '${eventType.name} の往復変換が失敗した');
        }
      });
    });

    // -------------------------------------------------------------------------
    // icon / color プロパティ（例外が出ないことを確認）
    // -------------------------------------------------------------------------

    test('全 TimelineEventType で icon プロパティが例外なく取得できる', () {
      for (final eventType in TimelineEventType.values) {
        final entry = TimelineEntry(
          id: 'icon-test',
          timestamp: DateTime(2026, 3, 25),
          type: eventType,
          message: 'テスト',
        );
        expect(() => entry.icon, returnsNormally,
            reason: '${eventType.name} の icon 取得で例外が発生した');
      }
    });

    test('全 TimelineEventType で color プロパティが例外なく取得できる', () {
      for (final eventType in TimelineEventType.values) {
        final entry = TimelineEntry(
          id: 'color-test',
          timestamp: DateTime(2026, 3, 25),
          type: eventType,
          message: 'テスト',
        );
        expect(() => entry.color, returnsNormally,
            reason: '${eventType.name} の color 取得で例外が発生した');
      }
    });
  });
}
