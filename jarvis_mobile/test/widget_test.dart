import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jarvis_mobile/main.dart';

void main() {
  testWidgets('JarvisApp renders splash screen branding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const JarvisApp());
    await tester.pump();

    expect(find.text('Jarvis'), findsOneWidget);
    expect(find.text('העוזר האישי שלך'), findsOneWidget);

    // Advance past the 2 s navigation timer so no pending timer leaks
    // between tests (SplashScreen.dispose() is then called, stopping
    // the animation controllers cleanly).
    await tester.pump(const Duration(seconds: 3));
  });
}
