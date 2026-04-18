import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static Future<void> saveList(
      String key, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_$key', jsonEncode(items));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> loadList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('cache_$key');
      if (str == null) return null;
      return List<Map<String, dynamic>>.from(jsonDecode(str));
    } catch (_) {
      return null;
    }
  }
}
