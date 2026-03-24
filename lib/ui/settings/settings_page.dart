import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/app_secrets.dart';
import '../../core/zone/safe_zone_detector.dart';

// ============================================================
// 内部プロバイダー（SettingsPage専用）
// ============================================================

/// Avalon APIキーが設定済みかどうかを保持するプロバイダー
final _avalonApiKeySetProvider =
    StateProvider<bool>((ref) => false);

/// 現在登録中のセーフゾーンSSIDを保持するプロバイダー
final _safeZoneSsidProvider =
    StateProvider<String?>((ref) => null);

// ============================================================
// 設定画面
// ============================================================

/// Smart Tetherの設定画面
///
/// Avalon APIキー、セーフゾーンSSID、Band 9 MACアドレスを管理する。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _apiKeyController = TextEditingController();
  final _macController = TextEditingController();
  final _authKeyController = TextEditingController();
  bool _isBand9Set = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _macController.dispose();
    _authKeyController.dispose();
    super.dispose();
  }

  /// 起動時に既存の設定値を読み込む
  Future<void> _loadCurrentSettings() async {
    try {
      final apiKey = await AppSecrets.getAvalonApiKey();
      if (mounted) {
        ref.read(_avalonApiKeySetProvider.notifier).state =
            apiKey != null && apiKey.isNotEmpty;
      }

      final detector = ref.read(safeZoneDetectorProvider);
      if (mounted) {
        ref.read(_safeZoneSsidProvider.notifier).state =
            detector.safeZoneSsid;
      }

      final mac = await AppSecrets.getBandMacAddress();
      final authKey = await AppSecrets.getBandAuthKey();
      final isMacReal = mac != null && mac != 'XX:XX:XX:XX:XX:XX';
      final isAuthReal = authKey != null && authKey != 'X';
      if (mounted) {
        setState(() {
          _isBand9Set = isMacReal && isAuthReal;
        });
      }
    } catch (e) {
      // 読み込み失敗時はデフォルト値のまま継続
      debugPrint('[SettingsPage] 設定読み込みエラー: $e');
    }
  }

  /// Avalon APIキーを保存する
  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;

    try {
      await AppSecrets.saveAvalonApiKey(key);
      _apiKeyController.clear();
      if (mounted) {
        ref.read(_avalonApiKeySetProvider.notifier).state = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('APIキーを保存しました'),
            backgroundColor: Color(0xFF4ECDC4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存に失敗しました: $e'),
            backgroundColor: const Color(0xFFFF6B6B),
          ),
        );
      }
    }
  }

  /// 現在のWi-Fi SSIDをセーフゾーンとして登録する
  Future<void> _registerCurrentSsid() async {
    try {
      final detector = ref.read(safeZoneDetectorProvider);
      final ssid = await detector.registerCurrentSsid();
      if (mounted) {
        if (ssid != null) {
          ref.read(_safeZoneSsidProvider.notifier).state = ssid;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$ssid を登録しました'),
              backgroundColor: const Color(0xFF4ECDC4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wi-Fiに接続されていないか、SSID取得に失敗しました'),
              backgroundColor: Color(0xFFFF6B6B),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登録に失敗しました: $e'),
            backgroundColor: const Color(0xFFFF6B6B),
          ),
        );
      }
    }
  }

  /// Band 9のMACアドレスとAuth Keyを保存する
  Future<void> _saveBand9Settings() async {
    final mac = _macController.text.trim();
    final authKey = _authKeyController.text.trim();
    if (mac.isEmpty || authKey.isEmpty) return;

    try {
      await AppSecrets.saveBandMacAddress(mac);
      await AppSecrets.saveBandAuthKey(authKey);
      _macController.clear();
      _authKeyController.clear();
      if (mounted) {
        setState(() {
          _isBand9Set = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Band 9 の設定を保存しました'),
            backgroundColor: Color(0xFF4ECDC4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存に失敗しました: $e'),
            backgroundColor: const Color(0xFFFF6B6B),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isApiKeySet = ref.watch(_avalonApiKeySetProvider);
    final safeZoneSsid = ref.watch(_safeZoneSsidProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '設定',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ---- Avalon API設定 ----
          _SectionHeader(title: 'Avalon API設定'),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isApiKeySet)
                  _StatusBadge(label: '設定済み')
                else
                  const Text(
                    'APIキーが未設定です',
                    style: TextStyle(
                      color: Color(0xFF8B8B9E),
                      fontSize: 14,
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Avalon APIキーを入力',
                    hintStyle: const TextStyle(
                      color: Color(0xFF8B8B9E),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0A0A0F),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF2E2E4E),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PrimaryButton(
                  label: '保存',
                  onPressed: _saveApiKey,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ---- セーフゾーン設定 ----
          _SectionHeader(title: 'セーフゾーン設定'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'セーフゾーン内では置き忘れアラートを抑制します',
              style: TextStyle(
                color: Color(0xFF8B8B9E),
                fontSize: 13,
              ),
            ),
          ),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '登録中のSSID:',
                      style: TextStyle(
                        color: Color(0xFF8B8B9E),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        safeZoneSsid ?? '未設定',
                        style: TextStyle(
                          color: safeZoneSsid != null
                              ? const Color(0xFF4ECDC4)
                              : const Color(0xFF8B8B9E),
                          fontSize: 14,
                          fontWeight: safeZoneSsid != null
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PrimaryButton(
                  label: '現在のWi-Fiを登録',
                  onPressed: _registerCurrentSsid,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ---- Band 9設定 ----
          _SectionHeader(title: 'Band 9設定'),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _isBand9Set
                  ? 'Band 9 が設定済みです'
                  : 'MACアドレスとAuth Keyを入力してください',
              style: const TextStyle(
                color: Color(0xFF8B8B9E),
                fontSize: 13,
              ),
            ),
          ),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isBand9Set) _StatusBadge(label: '設定済み'),
                if (_isBand9Set) const SizedBox(height: 12),

                // MACアドレス入力
                const Text(
                  'MACアドレス',
                  style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _macController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'AA:BB:CC:DD:EE:FF',
                    hintStyle: const TextStyle(
                      color: Color(0xFF4A4A5E),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0A0A0F),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF2E2E4E)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF7C3AED)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Auth Key入力
                const Text(
                  'Auth Key（32桁HEX）',
                  style: TextStyle(color: Color(0xFF8B8B9E), fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _authKeyController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '0123456789abcdef0123456789abcdef',
                    hintStyle: const TextStyle(
                      color: Color(0xFF4A4A5E),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0A0A0F),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF2E2E4E)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF7C3AED)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PrimaryButton(label: '保存', onPressed: _saveBand9Settings),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ============================================================
// 内部ウィジェット
// ============================================================

/// セクションヘッダー
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF7C3AED),
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// カード型コンテナ
class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 設定済みバッジ
class _StatusBadge extends StatelessWidget {
  final String label;

  const _StatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle,
          color: Color(0xFF4ECDC4),
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4ECDC4),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// アクセントカラーのプライマリボタン
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
