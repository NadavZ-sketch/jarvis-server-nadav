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

  Future<void> deleteTask(String id) async {
    await http.delete(_uri('/tasks/$id')).timeout(_timeout);
  }

  // ─── Reminders ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getReminders() async {
    final res = await http.get(_uri('/reminders')).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['reminders'] ?? []);
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
}
