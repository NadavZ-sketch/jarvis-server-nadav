import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jarvis_mobile/main.dart';

void main() {
  group('JarvisApp smoke tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders splash screen with Jarvis branding', (tester) async {
      await tester.pumpWidget(const JarvisApp());
      await tester.pump();

      expect(find.text('Jarvis'), findsOneWidget);
      expect(find.text('העוזר האישי שלך'), findsOneWidget);
    });

    testWidgets('splash screen has MaterialApp structure', (tester) async {
      await tester.pumpWidget(const JarvisApp());
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
