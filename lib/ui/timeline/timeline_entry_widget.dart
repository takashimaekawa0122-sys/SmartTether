import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/timeline/timeline_entry.dart';

/// タイムラインの1件のエントリウィジェット
///
/// デザイン仕様:
///   - カード左端に 3px のカラーバー（entry.color）
///   - 影: blurRadius 20, offset (0, 4)
///   - voiceMemo タイプ時は「▶ 再生」「コピー」ボタンを表示
///   - [showDateHeader] が true のとき日付区切りヘッダーを上部に表示
class TimelineEntryWidget extends StatelessWidget {
  final TimelineEntry entry;

  /// 前のエントリと日付が異なる場合に true を渡すと日付区切りを表示する
  final bool showDateHeader;

  const TimelineEntryWidget({
    super.key,
    required this.entry,
    this.showDateHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(entry.timestamp);
    final dateStr = DateFormat('M月d日（E）', 'ja').format(entry.timestamp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日付区切りヘッダー
        if (showDateHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Divider(color: Color(0xFF2E2E4E), thickness: 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    dateStr,
                    style: const TextStyle(
                      color: Color(0xFF4A4A5E),
                      fontSize: 12,
                    ),
                  ),
                ),
                const Expanded(
                  child: Divider(color: Color(0xFF2E2E4E), thickness: 1),
                ),
              ],
            ),
          ),

        // エントリ本体
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側: 時刻 + アイコン円
              _TimelineLeftColumn(
                timeStr: timeStr,
                entry: entry,
              ),

              const SizedBox(width: 12),

              // 右側: カード
              Expanded(
                child: _EntryCard(entry: entry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// 左列（時刻 + アイコン円）
// ----------------------------------------------------------------

class _TimelineLeftColumn extends StatelessWidget {
  final String timeStr;
  final TimelineEntry entry;

  const _TimelineLeftColumn({
    required this.timeStr,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          timeStr,
          style: const TextStyle(
            color: Color(0xFF8B8B9E),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: entry.color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: entry.color, width: 1.5),
          ),
          child: Icon(entry.icon, color: entry.color, size: 16),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// エントリカード
// ----------------------------------------------------------------

class _EntryCard extends StatelessWidget {
  final TimelineEntry entry;

  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: entry.color, width: 3),
          top: BorderSide(color: entry.color.withValues(alpha: 0.2), width: 1),
          right: BorderSide(color: entry.color.withValues(alpha: 0.2), width: 1),
          bottom: BorderSide(color: entry.color.withValues(alpha: 0.2), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: entry.color.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),

          // ボイスメモの文字起こし表示
          if (entry.transcription != null) ...[
            const SizedBox(height: 8),
            Text(
              '「${entry.transcription}」',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ActionButton(
                  icon: Icons.play_arrow,
                  label: '再生',
                  onTap: () {
                    // TODO: 音声・文字起こしエージェントで実装
                  },
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.copy,
                  label: 'コピー',
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: entry.transcription!),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('文字起こしをコピーしました'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Color(0xFF1E1E2E),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],

          // 録音時間の表示
          if (entry.audioDuration != null && entry.transcription == null) ...[
            const SizedBox(height: 4),
            Text(
              '録音時間: ${_formatDuration(entry.audioDuration!)}',
              style: const TextStyle(
                color: Color(0xFF8B8B9E),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// ----------------------------------------------------------------
// アクションボタン
// ----------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF7C3AED)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7C3AED),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
