import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('HomeController aiRank cache', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('aiRank is null before load', () async {
      SharedPreferences.setMockInitialValues({
        'home_ai_rank_v1': 'קדם ראשון: משימה X — פג מחר',
        'home_ai_rank_v1_ts': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('home_ai_rank_v1');
      final tsStr = prefs.getString('home_ai_rank_v1_ts');
      expect(cached, isNotNull);
      final ts = DateTime.tryParse(tsStr!);
      expect(ts, isNotNull);
      expect(DateTime.now().difference(ts!).inHours < 8, isTrue);
    });

    test('stale cache (>8h) should not be used', () async {
      SharedPreferences.setMockInitialValues({
        'home_ai_rank_v1': 'old rank',
        'home_ai_rank_v1_ts': DateTime.now()
            .subtract(const Duration(hours: 9))
            .toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final tsStr = prefs.getString('home_ai_rank_v1_ts');
      final ts = DateTime.tryParse(tsStr!)!;
      expect(DateTime.now().difference(ts).inHours < 8, isFalse);
    });
  });
}
