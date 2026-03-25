import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/security/app_secrets.dart';
import 'services/background_service.dart';
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

  // 開発用プレースホルダーを設定（Band 9到着後に削除）
  try {
    await AppSecrets.setDevelopmentPlaceholders();
  } catch (e) {
    // ignore: avoid_print
    print('[main] AppSecrets初期化エラー（続行）: $e');
  }

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

class SmartTetherApp extends StatelessWidget {
  final bool showOnboarding;

  const SmartTetherApp({super.key, required this.showOnboarding});

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
      home: showOnboarding ? const OnboardingPage() : const _HomeStack(),
    );
  }
}
