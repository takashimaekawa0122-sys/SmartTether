import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/timeline/timeline_entry.dart';
import 'core/timeline/timeline_logger.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'ui/alert/alert_overlay.dart';
import 'ui/onboarding/onboarding_page.dart';
import 'ui/timeline/timeline_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日本語ロケールの日付フォーマットを初期化する
  try {
    await initializeDateFormatting('ja');
  } catch (e) {
    // ignore: avoid_print
    print('[main] ロケール初期化エラー（続行）: $e');
  }

  // バックグラウンドサービスを設定する（起動はユーザー操作まで行わない）
  // 失敗してもアプリ自体は起動できるようにエラーを握りつぶす
  try {
    await initializeBackgroundService();
  } catch (e) {
    // ignore: avoid_print
    print('[main] バックグラウンドサービス初期化エラー（続行）: $e');
  }

  // 通知サービスを初期化する（通知チャンネル作成・権限申請）
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    // ignore: avoid_print
    print('[main] NotificationService初期化エラー（続行）: $e');
  }

  // Auth Key等はnullのまま管理し、設定画面で入力する
  // （起動時のプレースホルダー上書きはAuth Key消失の原因になるため廃止）

  // 初回起動チェック
  var showOnboarding = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    showOnboarding = !onboardingDone;
  } catch (e) {
    // ignore: avoid_print
    print('[main] SharedPreferences読み込みエラー（初回起動扱い）: $e');
  }

  runApp(
    ProviderScope(
      child: SmartTetherApp(showOnboarding: showOnboarding),
    ),
  );
}

/// TimelinePage の上に AlertOverlayController を重ねるルートスタック
///
/// AlertOverlayController は tetherStateStreamProvider を監視して
/// 警告状態になると自動的に全画面オーバーレイを表示する。
class _HomeStack extends StatelessWidget {
  const _HomeStack();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        TimelinePage(),
        AlertOverlayController(),
      ],
    );
  }
}

/// アプリのルートウィジェット
///
/// [ConsumerStatefulWidget] を使うことで Riverpod の [timelineLoggerProvider] に
/// アクセスしながら、バックグラウンドIPC（'timelineEntry'）の購読ライフサイクルを
/// 適切に管理する。
class SmartTetherApp extends ConsumerStatefulWidget {
  final bool showOnboarding;

  const SmartTetherApp({super.key, required this.showOnboarding});

  @override
  ConsumerState<SmartTetherApp> createState() => _SmartTetherAppState();
}

class _SmartTetherAppState extends ConsumerState<SmartTetherApp> {
  StreamSubscription<Map<String, dynamic>?>? _timelineEntrySub;

  @override
  void initState() {
    super.initState();
    _subscribeToBackgroundTimeline();
  }

  /// バックグラウンドIsolateからの 'timelineEntry' イベントを購読する
  ///
  /// バックグラウンドサービスが _invokeTimelineEntry() で送ったデータを受け取り、
  /// UIIsolateの [TimelineLogger] インスタンスに [TimelineLogger.addEntry] で追記する。
  /// これにより [_TimelineEntriesNotifier] のリスナー経由でタイムライン画面が更新される。
  void _subscribeToBackgroundTimeline() {
    _timelineEntrySub =
        FlutterBackgroundService().on('timelineEntry').listen((data) async {
      if (data == null) return;
      try {
        final entry = TimelineEntry.fromJson(data);
        final logger = ref.read(timelineLoggerProvider);
        await logger.addEntry(entry);
      } catch (e) {
        // ignore: avoid_print
        print('[SmartTetherApp] timelineEntry 受信エラー: $e');
      }
    });
  }

  @override
  void dispose() {
    _timelineEntrySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Tether',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF4ECDC4),
          surface: Color(0xFF1E1E2E),
        ),
        useMaterial3: true,
      ),
      home: widget.showOnboarding ? const OnboardingPage() : const _HomeStack(),
    );
  }
}
