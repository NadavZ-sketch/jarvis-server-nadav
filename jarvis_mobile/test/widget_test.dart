import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jarvis_mobile/main.dart' show JC;

// JarvisApp involves SplashScreen (repeating animations, Future.delayed
// navigation, platform channels) which makes reliable pumpWidget tests
// impractical in headless CI. Design-token unit tests provide stable
// coverage of the shared colour constants used throughout every screen.
void main() {
  group('JC design tokens', () {
    test('background palette', () {
      expect(JC.bg,         const Color(0xFF05090E));
      expect(JC.surface,    const Color(0xFF0B1422));
      expect(JC.surfaceAlt, const Color(0xFF0F1929));
      expect(JC.border,     const Color(0xFF1A2E4A));
    });

    test('blue palette', () {
      expect(JC.blue500, const Color(0xFF3B82F6));
      expect(JC.blue400, const Color(0xFF60A5FA));
      expect(JC.blue300, const Color(0xFF93C5FD));
    });

    test('text palette', () {
      expect(JC.textPrimary,   const Color(0xFFF1F5F9));
      expect(JC.textSecondary, const Color(0xFF94A3B8));
      expect(JC.textMuted,     const Color(0xFF475569));
    });

    test('bubble and action colors', () {
      expect(JC.userBubble,   const Color(0xFF11284A));
      expect(JC.jarvisBubble, const Color(0xFF0B1929));
      expect(JC.cancelRed,    const Color(0xFFEF4444));
    });
  });
}
