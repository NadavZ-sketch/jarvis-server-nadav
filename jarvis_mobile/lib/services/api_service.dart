import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_settings.dart';

class ApiService {
  final AppSettings settings;
  static const _timeout = Duration(seconds: 30);

  ApiService(this.settings);

  Uri _uri(String path) => Uri.parse('${settings.serverUrl}$path');

  /// Maps low-level exceptions to short Hebrew messages safe to show in UI.
  /// The original error is logged via [debugPrint] so devs still see it.
  static String friendlyError(Object error) {
    debugPrint('[ApiService] $error');
    final msg = error.toString();
    if (error is TimeoutException ||
        msg.contains('timeout') ||
        msg.contains('TimeoutException')) {
      return 'תם הזמן. בדוק את החיבור לאינטרנט';
    }
    if (error is SocketException ||
        msg.contains('SocketException') ||
        msg.contains('refused') ||
        msg.contains('ECONNREFUSED') ||
        msg.contains('NetworkError') ||
        msg.contains('Failed host lookup')) {
      return 'השרת לא זמין. ודא שהשרת המקומי פועל';
    }
    if (error is FormatException || msg.contains('FormatException')) {
      return 'תשובה לא תקינה מהשרת';
    }
    if (msg.contains('השרת אינו זמין כרגע')) {
      // _safeBody already returned a Hebrew message; pass through.
      return msg.replaceFirst('Exception: ', '');
    }
    return 'אירעה שגיאה. נסה שוב';
  }

  // Detects Render.com cold-start HTML page and throws a clean error
  String _safeBody(http.Response res) {
    final body = res.body;
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html')) {
      throw Exception('השרת אינו זמין כרגע — נסה שוב בעוד רגע');
    }
    return body;
  }

  // ─── Tasks ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTasks() async {
    final res = await http.get(_uri('/tasks')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['tasks'] ?? []);
  }

  Future<Map<String, dynamic>> addTask(String content) async {
    final res = await http.post(
      _uri('/tasks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'content': content}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteTask(String id) async {
    await http.delete(_uri('/tasks/$id')).timeout(_timeout);
  }

  Future<Map<String, dynamic>> updateTask(String id,
      {bool? done, String? dueDate, String? content}) async {
    final body = <String, dynamic>{};
    if (done    != null) body['done']     = done;
    if (dueDate != null) body['due_date'] = dueDate;
    if (content != null) body['content']  = content;
    final res = await http.put(
      _uri('/tasks/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  // ─── Reminders ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getReminders() async {
    final res = await http.get(_uri('/reminders')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['reminders'] ?? []);
  }

  Future<Map<String, dynamic>> addReminder(
      String text, String scheduledTime) async {
    final res = await http.post(
      _uri('/reminders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'scheduled_time': scheduledTime}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteReminder(String id) async {
    await http.delete(_uri('/reminders/$id')).timeout(_timeout);
  }

  /// Returns fired (due) reminders and removes them from the server queue.
  Future<List<Map<String, dynamic>>> checkFiredReminders() async {
    final res = await http.get(_uri('/check-reminders')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['reminders'] ?? []);
  }

  // ─── Contacts ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getContacts() async {
    final res = await http.get(_uri('/contacts')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['contacts'] ?? []);
  }

  Future<void> deleteContact(String id) async {
    await http.delete(_uri('/contacts/$id')).timeout(_timeout);
  }

  // ─── Shopping ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getShopping() async {
    final res = await http.get(_uri('/shopping')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<Map<String, dynamic>> addShoppingItem(String item) async {
    final res = await http.post(
      _uri('/shopping'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'item': item}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteShoppingItem(String id) async {
    await http.delete(_uri('/shopping/$id')).timeout(_timeout);
  }

  // ─── Notes ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNotes() async {
    final res = await http.get(_uri('/notes')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['notes'] ?? []);
  }

  Future<Map<String, dynamic>> addNote(String content,
      {String title = ''}) async {
    final res = await http.post(
      _uri('/notes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': title, 'content': content}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteNote(String id) async {
    await http.delete(_uri('/notes/$id')).timeout(_timeout);
  }

  Future<Map<String, dynamic>> updateNote(String id,
      {String? title, String? content}) async {
    final body = <String, dynamic>{};
    if (title   != null) body['title']   = title;
    if (content != null) body['content'] = content;
    final res = await http.put(
      _uri('/notes/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }
}
