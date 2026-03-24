import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/security/app_secrets.dart';
import '../timeline/timeline_page.dart';
import '../alert/alert_overlay.dart';

/// オンボーディング完了フラグのキー
const _kOnboardingDoneKey = 'onboarding_done';

/// 初回起動時に表示する3ステップのオンボーディング画面
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Step 2 で表示するデバイス情報
  String? _macSuffix;
  bool _hasAuthKey = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final mac = await AppSecrets.getBandMacAddress();
    final authKey = await AppSecrets.getBandAuthKey();
    setState(() {
      // MACアドレスの末尾8文字（例: 23:38:E3）
      if (mac != null && mac.length >= 8) {
        _macSuffix = mac.substring(mac.length - 8);
      }
      _hasAuthKey = authKey != null;
    });
  }

  Future<void> _onNextTapped() async {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 「始める」タップ: フラグを保存してメイン画面へ
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboardingDoneKey, true);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const _HomeStack(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // ページコンテンツ
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  _StepWelcome(),
                  _StepBandInfo(
                    macSuffix: _macSuffix,
                    hasAuthKey: _hasAuthKey,
                  ),
                  _StepReady(),
                ],
              ),
            ),

            // ドットインジケーター
            _DotIndicator(
              totalCount: 3,
              currentIndex: _currentPage,
            ),

            const SizedBox(height: 24),

            // 「次へ」/「始める」ボタン
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _onNextTapped,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _currentPage < 2 ? '次へ' : '始める',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Step 1 - ようこそ
// ============================================================

class _StepWelcome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.bluetooth,
      iconColor: const Color(0xFF7C3AED),
      title: 'Smart Tether',
      description: 'Band 9が離れると自動でアラートをお知らせします',
    );
  }
}

// ============================================================
// Step 2 - Band 9 の確認
// ============================================================

class _StepBandInfo extends StatelessWidget {
  final String? macSuffix;
  final bool hasAuthKey;

  const _StepBandInfo({
    required this.macSuffix,
    required this.hasAuthKey,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.watch,
            size: 88,
            color: Color(0xFF7C3AED),
          ),
          const SizedBox(height: 32),
          const Text(
            'Band 9 が登録されています',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Xiaomi Smart Band 9との接続の準備ができています',
            style: TextStyle(
              color: Color(0xFF8B8B9E),
              fontSize: 15,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // デバイス情報カード
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // MACアドレス行
                Row(
                  children: [
                    const Icon(
                      Icons.bluetooth,
                      size: 16,
                      color: Color(0xFF8B8B9E),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'デバイスID: ',
                      style: TextStyle(
                        color: Color(0xFF8B8B9E),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      macSuffix != null ? '...$macSuffix' : '読み込み中...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                if (hasAuthKey) ...[
                  const SizedBox(height: 10),
                  // 認証キー行
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Color(0xFF4ECDC4),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '認証キー: ',
                        style: TextStyle(
                          color: Color(0xFF8B8B9E),
                          fontSize: 14,
                        ),
                      ),
                      const Text(
                        '設定済み',
                        style: TextStyle(
                          color: Color(0xFF4ECDC4),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Step 3 - 準備完了
// ============================================================

class _StepReady extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.check_circle,
      iconColor: const Color(0xFF4ECDC4),
      title: '準備完了！',
      description: 'メイン画面の「監視開始」ボタンをタップするだけで始まります',
    );
  }
}

// ============================================================
// ステップ共通レイアウト
// ============================================================

class _StepScaffold extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _StepScaffold({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 88,
            color: iconColor,
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF8B8B9E),
              fontSize: 15,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ドットインジケーター
// ============================================================

class _DotIndicator extends StatelessWidget {
  final int totalCount;
  final int currentIndex;

  const _DotIndicator({
    required this.totalCount,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalCount, (index) {
        final isActive = index == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF7C3AED)
                : const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(4),
            border: isActive
                ? null
                : Border.all(
                    color: const Color(0xFF4A4A5E),
                    width: 1,
                  ),
          ),
        );
      }),
    );
  }
}

// ============================================================
// メイン画面スタック（TimelinePage + AlertOverlay）
// ============================================================

/// オンボーディング完了後に遷移するホーム画面
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
