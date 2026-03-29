import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'timeline_entry.dart';

/// タイムラインのログを管理するクラス
class TimelineLogger {
  static const _storageKey = 'timeline_entries';
  static const _maxEntries = 100;

  final List<TimelineEntry> _entries = [];
  final _listeners = <void Function(TimelineEntry)>[];

  /// 新しいイベントをタイムラインに追加する
  Future<void> log(TimelineEventType type, String message, {
    String? transcription,
    String? audioFilePath,
    Duration? audioDuration,
  }) async {
    final entry = TimelineEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_entries.length}',
      timestamp: DateTime.now(),
      type: type,
      message: message,
      transcription: transcription,
      audioFilePath: audioFilePath,
      audioDuration: audioDuration,
    );
    await _addEntry(entry);
  }

  /// バックグラウンドIPC経由で受け取った既存の [TimelineEntry] を追加する
  ///
  /// バックグラウンドIsolateが invoke('timelineEntry') で送ったデータを
  /// メインIsolateで復元したエントリをここに追加するために使う。
  Future<void> addEntry(TimelineEntry entry) async {
    await _addEntry(entry);
  }

  Future<void> _addEntry(TimelineEntry entry) async {
    _entries.insert(0, entry); // 最新が先頭

    // 上限を超えたら古いものを削除
    if (_entries.length > _maxEntries) {
      _entries.removeLast();
    }

    await _persist();

    // リスナーに通知（1つが例外をスローしても後続リスナーは呼び続ける）
    for (final listener in List.of(_listeners)) {
      try {
        listener(entry);
      } catch (e) {
        // ignore: avoid_print
        print('[TimelineLogger] リスナー例外: $e');
      }
    }
  }

  /// 保存済みのタイムラインを読み込む
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null) return;

    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(list
            .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
            .toList());
    } catch (_) {
      // 読み込み失敗は無視（空のタイムラインで続行）
    }
  }

  /// 現在のエントリ一覧（新しい順）
  List<TimelineEntry> get entries => List.unmodifiable(_entries);

  /// エントリ追加時のコールバックを登録する
  void addListener(void Function(TimelineEntry) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(TimelineEntry) listener) {
    _listeners.remove(listener);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }
}

/// TimelineLogger の Riverpod プロバイダー
///
/// アプリ全体でシングルトンとして使用する。
/// voice_memo_recorder.dart など他のファイルからはここを import する。
final timelineLoggerProvider = Provider<TimelineLogger>((ref) {
  return TimelineLogger();
});
