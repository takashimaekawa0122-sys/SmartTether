import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/security/app_secrets.dart';
import 'ui/timeline/timeline_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 開発用プレースホルダーを設定（Band 9到着後に削除）
  await AppSecrets.setDevelopmentPlaceholders();

  runApp(
    const ProviderScope(
      child: SmartTetherApp(),
    ),
  );
}

class SmartTetherApp extends StatelessWidget {
  const SmartTetherApp({super.key});

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
      home: const TimelinePage(),
    );
  }
}
