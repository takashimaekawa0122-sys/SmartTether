import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/timeline/timeline_entry.dart';

/// タイムラインのダミーデータ（開発確認用）
final _dummyEntries = [
  TimelineEntry(
    id: '1',
    timestamp: DateTime.now().subtract(const Duration(hours: 3)),
    type: TimelineEventType.monitoringStarted,
    message: '自宅のWi-Fiから切断。テザー監視を開始しました。',
  ),
  TimelineEntry(
    id: '2',
    timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    type: TimelineEventType.voiceMemo,
    message: 'ボイスメモを録音しました（2分14秒）',
    transcription: '山田部長から来週の件について、期限を金曜日までとするよう指示がありました。',
    audioDuration: const Duration(minutes: 2, seconds: 14),
  ),
  TimelineEntry(
    id: '3',
    timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
    type: TimelineEventType.warning,
    message: 'バンドとの接続が弱まっています。',
  ),
  TimelineEntry(
    id: '4',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    type: TimelineEventType.monitoringStopped,
    message: '自宅のWi-Fiに接続。監視をスリープします。',
  ),
];

/// Smart Tetherのメイン画面（タイムラインUI）
class TimelinePage extends ConsumerWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        title: const Text(
          'Smart Tether',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // 監視ステータスインジケーター
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                _PulsingDot(color: const Color(0xFF4ECDC4)),
                const SizedBox(width: 6),
                const Text(
                  '監視中',
                  style: TextStyle(
                    color: Color(0xFF4ECDC4),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _dummyEntries.length,
        itemBuilder: (context, index) {
          return _TimelineEntryWidget(entry: _dummyEntries[index]);
        },
      ),
    );
  }
}

/// タイムラインの1件のエントリウィジェット
class _TimelineEntryWidget extends StatelessWidget {
  final TimelineEntry entry;

  const _TimelineEntryWidget({required this.entry});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(entry.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // タイムライン左側（時刻・線・アイコン）
          Column(
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
          ),
          const SizedBox(width: 12),
          // エントリ内容
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: entry.color.withValues(alpha:0.3),
                  width: 1,
                ),
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
                  // ボイスメモの文字起こし
                  if (entry.transcription != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '「${entry.transcription}」',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha:0.7),
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
                          onTap: () {},
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.copy,
                          label: 'コピー',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// アクションボタン（再生・コピーなど）
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
          color: const Color(0xFF7C3AED).withValues(alpha:0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF7C3AED).withValues(alpha:0.5),
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

/// 呼吸するように点滅するドット（監視中インジケーター）
class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
