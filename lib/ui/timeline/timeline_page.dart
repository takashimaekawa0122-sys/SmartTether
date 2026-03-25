import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/security/app_secrets.dart';
import '../../core/stealth/stealth_trigger.dart';
import '../../core/tether/alert_state.dart';
import '../../core/timeline/timeline_entry.dart';
import '../../core/timeline/timeline_logger.dart';
import '../../services/background_service.dart';
import '../settings/settings_page.dart';
import 'timeline_entry_widget.dart';

// ============================================================
// タイムラインエントリ一覧プロバイダー
// ============================================================

/// タイムラインのエントリ一覧を管理する StateNotifier
///
/// TimelineLogger のリスナー経由で新しいエントリを受け取り、
/// UIをリアクティブに更新する。
class _TimelineEntriesNotifier extends StateNotifier<List<TimelineEntry>> {
  _TimelineEntriesNotifier(TimelineLogger logger)
      : super(List.unmodifiable(logger.entries)) {
    // ロード済みエントリを初期値として設定したうえで
    // 以降の追加をリスナーで受け取る
    _listener = (entry) {
      state = List.unmodifiable([entry, ...state]);
    };
    logger.addListener(_listener);
    _logger = logger;
  }

  late final TimelineLogger _logger;
  late final void Function(TimelineEntry) _listener;

  @override
  void dispose() {
    _logger.removeListener(_listener);
    super.dispose();
  }
}

/// UI側でタイムラインエントリを監視するプロバイダー
final _timelineEntriesProvider =
    StateNotifierProvider<_TimelineEntriesNotifier, List<TimelineEntry>>((ref) {
  final logger = ref.watch(timelineLoggerProvider);
  return _TimelineEntriesNotifier(logger);
});

// ============================================================
// ドットのカラーマッピング（TetherState → Color）
// ============================================================

Color _dotColorForState(TetherState? state) {
  switch (state) {
    case TetherState.sleeping:
    case null:
      return const Color(0xFF4ECDC4); // ティール
    case TetherState.monitoring:
    case TetherState.grace:
      return const Color(0xFFFFE66D); // ゴールド
    case TetherState.warning:
    case TetherState.confirmed:
      return const Color(0xFFFF6B6B); // 赤
    case TetherState.standby:
      return const Color(0xFF4ECDC4); // ティール
  }
}

String _statusLabelForState(TetherState? state) {
  switch (state) {
    case TetherState.sleeping:
    case null:
      return 'スリープ中';
    case TetherState.monitoring:
    case TetherState.grace:
      return '監視中';
    case TetherState.warning:
      return '警告';
    case TetherState.confirmed:
      return '要確認';
    case TetherState.standby:
      return 'お留守番';
  }
}

// ============================================================
// メイン画面
// ============================================================

/// Smart Tetherのメイン画面（タイムラインUI）
class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key});

  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  bool _isStarting = false;

  Future<void> _toggleMonitoring() async {
    final isRunning = ref.read(backgroundServiceProvider);

    if (isRunning) {
      // 停止
      await ref.read(backgroundServiceProvider.notifier).stopMonitoring();
      await ref.read(bleManagerProvider).disconnect();
      return;
    }

    // 開始：Band 9 設定チェック
    final mac = await AppSecrets.getBandMacAddress();
    final authKey = await AppSecrets.getBandAuthKey();
    final isConfigured = mac != null &&
        mac != 'XX:XX:XX:XX:XX:XX' &&
        authKey != null &&
        authKey != 'X';

    if (!isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('先に設定画面でBand 9を設定してください'),
            backgroundColor: const Color(0xFFFF6B6B),
            action: SnackBarAction(
              label: '設定を開く',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isStarting = true);
    try {
      // バックグラウンドサービス起動
      await ref.read(backgroundServiceProvider.notifier).startMonitoring();
      // BLE接続開始
      final result = await ref.read(bleManagerProvider).connect();
      if (result is BleFailure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('BLE接続エラー: ${result.error}'),
            backgroundColor: const Color(0xFFFF6B6B),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // BLE接続完了と同時にステルストリガー監視を起動する。
    // stealthTriggerProvider は内部で bleConnectionStateProvider を listen して
    // 自動的に開始・停止するため、ref.watch するだけで十分。
    ref.watch(stealthTriggerProvider);

    final tetherStateAsync = ref.watch(tetherStateStreamProvider);
    final tetherState = tetherStateAsync.valueOrNull;
    final dotColor = _dotColorForState(tetherState);
    final statusLabel = _statusLabelForState(tetherState);

    final bleStateAsync = ref.watch(bleConnectionStateProvider);
    final bleState = bleStateAsync.valueOrNull;
    final rssiAsync = ref.watch(bleRssiProvider);
    final rssi = rssiAsync.valueOrNull;

    final isRunning = ref.watch(backgroundServiceProvider);
    final entries = ref.watch(_timelineEntriesProvider);

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
          // BLE接続状態バッジ
          if (bleState != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _BleBadge(state: bleState, rssi: rssi),
            ),
          // 監視ステータスインジケーター
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                _PulsingDot(color: dotColor),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: dotColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // 設定画面への遷移ボタン
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF8B8B9E)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: entries.isEmpty
          ? _EmptyState()
          : _TimelineList(entries: entries),
      floatingActionButton: _MonitoringFab(
        isRunning: isRunning,
        isStarting: _isStarting,
        onTap: _toggleMonitoring,
      ),
    );
  }
}

// ============================================================
// タイムラインリスト（AnimatedList）
// ============================================================

class _TimelineList extends StatefulWidget {
  final List<TimelineEntry> entries;

  const _TimelineList({required this.entries});

  @override
  State<_TimelineList> createState() => _TimelineListState();
}

class _TimelineListState extends State<_TimelineList> {
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<TimelineEntry> _currentEntries;

  @override
  void initState() {
    super.initState();
    _currentEntries = List.of(widget.entries);
  }

  @override
  void didUpdateWidget(_TimelineList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 先頭に新しいエントリが追加された場合にアニメーション
    if (widget.entries.length > _currentEntries.length) {
      final newCount = widget.entries.length - _currentEntries.length;
      for (var i = 0; i < newCount; i++) {
        _currentEntries.insert(i, widget.entries[i]);
        _listKey.currentState?.insertItem(i,
            duration: const Duration(milliseconds: 300));
      }
    } else {
      // エントリが減った場合（クリアなど）はキーを再生成してリビルド
      setState(() {
        _listKey = GlobalKey<AnimatedListState>();
        _currentEntries = List.of(widget.entries);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      padding: const EdgeInsets.symmetric(vertical: 8),
      initialItemCount: _currentEntries.length,
      itemBuilder: (context, index, animation) {
        if (index >= _currentEntries.length) return const SizedBox.shrink();
        final entry = _currentEntries[index];

        // 日付区切りの判定（前のエントリと日付が異なるか）
        final showDateHeader = index == _currentEntries.length - 1 ||
            !_isSameDay(
              entry.timestamp,
              _currentEntries[index + 1].timestamp,
            );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.3),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: FadeTransition(
            opacity: animation,
            child: TimelineEntryWidget(
              key: ValueKey(entry.id),
              entry: entry,
              showDateHeader: showDateHeader,
            ),
          ),
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ============================================================
// BLE接続状態バッジ
// ============================================================

class _BleBadge extends StatelessWidget {
  final BleConnectionState state;
  final double? rssi;

  const _BleBadge({required this.state, this.rssi});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      BleConnectionState.connected => (
          const Color(0xFF4ECDC4),
          rssi != null ? '${rssi!.round()}dBm' : 'BLE接続中',
        ),
      BleConnectionState.connecting => (
          const Color(0xFFFFE66D),
          '接続中...',
        ),
      BleConnectionState.authenticating => (
          const Color(0xFFFFE66D),
          '認証中...',
        ),
      BleConnectionState.error => (
          const Color(0xFFFF6B6B),
          'BLEエラー',
        ),
      BleConnectionState.disconnected => (
          const Color(0xFF4A4A5E),
          'BLE未接続',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 監視開始/停止 FAB
// ============================================================

class _MonitoringFab extends StatelessWidget {
  final bool isRunning;
  final bool isStarting;
  final VoidCallback onTap;

  const _MonitoringFab({
    required this.isRunning,
    required this.isStarting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isRunning
        ? const Color(0xFFFF6B6B) // 停止ボタン: 赤
        : const Color(0xFF7C3AED); // 開始ボタン: パープル

    return FloatingActionButton.extended(
      onPressed: isStarting ? null : onTap,
      backgroundColor: color,
      foregroundColor: Colors.white,
      elevation: 4,
      icon: isStarting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(isRunning ? Icons.stop : Icons.play_arrow),
      label: Text(
        isStarting ? '接続中...' : (isRunning ? '監視停止' : '監視開始'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ============================================================
// 空状態ウィジェット
// ============================================================

/// タイムラインが空のときに表示するウィジェット
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            color: Color(0xFF2E2E4E),
            size: 64,
          ),
          SizedBox(height: 16),
          Text(
            'まだイベントはありません',
            style: TextStyle(
              color: Color(0xFF8B8B9E),
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '監視を開始するとここにログが表示されます',
            style: TextStyle(
              color: Color(0xFF4A4A5E),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 呼吸するドット
// ============================================================

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
