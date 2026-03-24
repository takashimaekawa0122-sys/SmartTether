import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/main.dart';

void main() {
  testWidgets('Smart Tether アプリが起動するスモークテスト', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: SmartTetherApp(showOnboarding: false)),
    );
    // タイムライン画面が表示されることを確認
    expect(find.text('Smart Tether'), findsOneWidget);
  });
}
