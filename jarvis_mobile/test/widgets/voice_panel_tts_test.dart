import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/widgets/chat/voice_panel.dart';

// resolveTtsLanguage backs VoicePanel._initTts(): it decides which locale
// flutter_tts actually speaks in. Full VoicePanel behavior needs a platform
// channel (see voice_panel_orb_tap_test.dart's stub), but this fallback
// logic is pure and worth pinning directly.
void main() {
  group('resolveTtsLanguage', () {
    test('uses the preferred locale when the platform has it installed', () {
      expect(resolveTtsLanguage('he-IL', true), 'he-IL');
    });

    test('falls back to en-US when the preferred locale is unavailable', () {
      expect(resolveTtsLanguage('he-IL', false), 'en-US');
    });

    test('respects a non-Hebrew preference when available', () {
      expect(resolveTtsLanguage('en-US', true), 'en-US');
    });
  });
}
