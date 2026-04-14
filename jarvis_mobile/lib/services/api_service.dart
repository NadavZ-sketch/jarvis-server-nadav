import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_settings.dart';

class ApiService {
  final AppSettings settings;
  static const _timeout = Duration(seconds: 15);

  ApiService(this.settings);

  Uri _uri(String path) => Uri.parse('${settings.serverUrl}$path');

  // ─── Tasks ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTasks() async {
    final res = await http.get(_uri('/tasks')).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['tasks'] ?? []);
  }

  Future<Map<String, dynamic>> addTask(String content) async {
    final res = await http.post(
      _uri('/tasks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'content': content}),
    ).timeout(_timeout);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteTask(String id) async {
    await http.delete(_uri('/tasks/$id')).timeout(_timeout);
  }

  // ─── Reminders ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getReminders() async {
    final res = await http.get(_uri('/reminders')).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['reminders'] ?? []);
  }

  Future<Map<String, dynamic>> addReminder(
      String text, String scheduledTime) async {
    final res = await http.post(
      _uri('/reminders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'scheduled_time': scheduledTime}),
    ).timeout(_timeout);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteReminder(String id) async {
    await http.delete(_uri('/reminders/$id')).timeout(_timeout);
  }

  // ─── Contacts ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getContacts() async {
    final res = await http.get(_uri('/contacts')).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['contacts'] ?? []);
  }

  Future<void> deleteContact(String id) async {
    await http.delete(_uri('/contacts/$id')).timeout(_timeout);
  }

  // ─── Shopping ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getShopping() async {
    final res = await http.get(_uri('/shopping')).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<Map<String, dynamic>> addShoppingItem(String item) async {
    final res = await http.post(
      _uri('/shopping'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'item': item}),
    ).timeout(_timeout);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteShoppingItem(String id) async {
    await http.delete(_uri('/shopping/$id')).timeout(_timeout);
  }

  // ─── Notes ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNotes() async {
    final res = await http.get(_uri('/notes')).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['notes'] ?? []);
  }

  Future<Map<String, dynamic>> addNote(String content,
      {String title = ''}) async {
    final res = await http.post(
      _uri('/notes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': title, 'content': content}),
    ).timeout(_timeout);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteNote(String id) async {
    await http.delete(_uri('/notes/$id')).timeout(_timeout);
  }
}
