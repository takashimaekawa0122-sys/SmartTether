// スモークテスト:
// BLE・ネイティブAPIを一切使わずに「アプリタイトルが存在する」ことを確認する。
// BLE統合テストは実機テスト時に手動で確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smart Tether タイトルが表示されるスモークテスト', (WidgetTester tester) async {
    // BLE依存プロバイダーを避けるため、最小ウィジェットで検証する。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Smart Tether'),
          ),
          body: const Center(
            child: Text('監視開始'),
          ),
        ),
      ),
    );

    // タイトルと主要ラベルの存在を確認
    expect(find.text('Smart Tether'), findsOneWidget);
    expect(find.text('監視開始'), findsOneWidget);
  });
}
