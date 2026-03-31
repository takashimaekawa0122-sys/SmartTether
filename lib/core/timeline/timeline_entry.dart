import 'package:flutter/material.dart';

/// タイムラインに表示するイベントの種類
enum TimelineEventType {
  monitoringStarted,   // 監視開始
  monitoringStopped,   // 監視停止（安全圏）
  monitoringPaused,    // 一時停止（お留守番）
  warning,             // 置き忘れ警告
  alert,               // 置き忘れ確定
  theftDetected,       // 盗難検知
  voiceMemo,           // ボイスメモ
  flashTriggered,      // LEDフラッシュ
  escapeTimerStarted,  // スマートエスケープ起動
  batteryLow,          // バッテリー低下
  bandForgotten,       // バンドつけ忘れ
  systemShutdown,      // システムシャットダウン
}

/// タイムラインの1件のエントリ
class TimelineEntry {
  final String id;
  final DateTime timestamp;
  final TimelineEventType type;
  final String message;
  final String? transcription; // ボイスメモの文字起こし
  final String? audioFilePath; // 録音ファイルのパス
  final Duration? audioDuration; // 録音時間

  const TimelineEntry({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.message,
    this.transcription,
    this.audioFilePath,
    this.audioDuration,
  });

  /// イベント種別に対応するアイコン
  IconData get icon {
    switch (type) {
      case TimelineEventType.monitoringStarted:
        return Icons.link;
      case TimelineEventType.monitoringStopped:
        return Icons.bedtime;
      case TimelineEventType.monitoringPaused:
        return Icons.pause_circle;
      case TimelineEventType.warning:
        return Icons.warning_amber;
      case TimelineEventType.alert:
        return Icons.crisis_alert;
      case TimelineEventType.theftDetected:
        return Icons.security;
      case TimelineEventType.voiceMemo:
        return Icons.mic;
      case TimelineEventType.flashTriggered:
        return Icons.flashlight_on;
      case TimelineEventType.escapeTimerStarted:
        return Icons.phone_in_talk;
      case TimelineEventType.batteryLow:
        return Icons.battery_alert;
      case TimelineEventType.bandForgotten:
        return Icons.watch_off;
      case TimelineEventType.systemShutdown:
        return Icons.power_settings_new;
    }
  }

  /// イベント種別に対応するカラー
  Color get color {
    switch (type) {
      case TimelineEventType.monitoringStarted:
        return const Color(0xFF4ECDC4); // ティール
      case TimelineEventType.monitoringStopped:
      case TimelineEventType.monitoringPaused:
        return const Color(0xFF8B8B9E); // グレー
      case TimelineEventType.warning:
        return const Color(0xFFFF9500); // オレンジ
      case TimelineEventType.alert:
      case TimelineEventType.theftDetected:
        return const Color(0xFFFF6B6B); // 赤
      case TimelineEventType.voiceMemo:
        return const Color(0xFFFFE66D); // ゴールド
      case TimelineEventType.flashTriggered:
        return const Color(0xFF7C3AED); // パープル
      case TimelineEventType.escapeTimerStarted:
        return const Color(0xFF4ECDC4); // ティール
      case TimelineEventType.batteryLow:
        return const Color(0xFFFF9500); // オレンジ
      case TimelineEventType.bandForgotten:
        return const Color(0xFF7C3AED); // パープル
      case TimelineEventType.systemShutdown:
        return const Color(0xFF8B8B9E); // グレー
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'type': type.name,
    'message': message,
    'transcription': transcription,
    'audioFilePath': audioFilePath,
    'audioDurationMs': audioDuration?.inMilliseconds,
  };

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    type: TimelineEventType.values.byName(json['type'] as String),
    message: json['message'] as String,
    transcription: json['transcription'] as String?,
    audioFilePath: json['audioFilePath'] as String?,
    audioDuration: json['audioDurationMs'] != null
        ? Duration(milliseconds: json['audioDurationMs'] as int)
        : null,
  );
}
