import 'package:flutter/material.dart';

import 'alert/alert_overlay.dart';
import 'timeline/timeline_page.dart';

/// TimelinePage の上に AlertOverlayController を重ねるルートスタック
///
/// AlertOverlayController は tetherStateStreamProvider を監視して
/// 警告状態になると自動的に全画面オーバーレイを表示する。
class HomeStack extends StatelessWidget {
  const HomeStack({super.key});

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
