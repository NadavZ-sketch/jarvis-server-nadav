import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_settings.dart';

class ApiService {
  final AppSettings settings;
  final http.Client _client;
  static const _timeout = Duration(seconds: 30);

  ApiService(this.settings, {http.Client? client})
      : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('${settings.serverUrl}$path');

  static const Map<String, String> _baseHeaders = {
    'x-user-role': 'member',
    'x-user-plan': 'free',
    'x-user-consent': 'true',
  };

  Map<String, String> _headers([Map<String, String>? extra]) {
    final h = Map<String, String>.from(_baseHeaders);
    if (extra != null) h.addAll(extra);
    return h;
  }

  /// Sends explicit user feedback on a Jarvis reply to the server's feedback
  /// loop. Fire-and-forget: never throws into the UI. [signal] is 'up' or
  /// 'down'; [correction] is an optional "what I actually meant" note.
  Future<void> sendFeedback({
    required String chatId,
    required String messageText,
    required String signal,
    String? correction,
    String source = 'chat',
  }) async {
    try {
      await _client
          .post(
            _uri('/feedback'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({
              'chatId': chatId,
              'messageText': messageText,
              'signal': signal,
              if (correction != null && correction.trim().isNotEmpty)
                'correction': correction.trim(),
              'source': source,
            }),
          )
          .timeout(_timeout);
    } catch (e) {
      debugPrint('[ApiService] sendFeedback failed (suppressed): $e');
    }
  }

  /// Records a generic telemetry event via the smart-telemetry endpoint.
  /// Fire-and-forget: never throws into the UI.
  Future<void> recordTelemetryEvent(
    String eventType, {
    Map<String, dynamic>? payload,
    String? userId,
  }) async {
    try {
      await _client
          .post(
            _uri('/dashboard/smart-telemetry'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({
              'event_type': eventType,
              if (payload != null) 'payload': payload,
              if (userId != null) 'user_id': userId,
            }),
          )
          .timeout(_timeout);
    } catch (e) {
      debugPrint('[ApiService] recordTelemetryEvent failed (suppressed): $e');
    }
  }

  /// Lightweight reachability probe against /health. Returns true if the
  /// server answered with 200. Never throws — used to drive the offline
  /// banner. Works on web and mobile (plain http, no dart:io lookup).
  Future<bool> ping() async {
    try {
      final res = await _client
          .get(_uri('/health'), headers: _baseHeaders)
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

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
    // If the message came from the server and is already in Hebrew, pass it through
    // so the user sees the actual error instead of a generic fallback.
    final clean = msg.startsWith('Exception: ') ? msg.substring(11) : msg;
    if (RegExp(r'[֐-׿]').hasMatch(clean)) return clean;
    return 'אירעה שגיאה. נסה שוב';
  }

  // Detects Render.com cold-start HTML page or HTTP errors and throws a clean error
  String _safeBody(http.Response res) {
    final body = res.body;
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html')) {
      throw Exception('השרת אינו זמין כרגע — נסה שוב בעוד רגע');
    }
    if (res.statusCode >= 400) {
      String? serverMsg;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        serverMsg = (json['error'] ?? json['message']) as String?;
      } catch (_) {}
      throw Exception(serverMsg ?? 'שגיאת שרת (${res.statusCode})');
    }
    return body;
  }

  // ─── Tasks ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTasks() async {
    final res = await _client.get(_uri('/tasks'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['tasks'] ?? []);
  }

  Future<Map<String, dynamic>> addTask(String content,
      {String priority = 'medium',
      String? category,
      String? projectId,
      String? kanbanColumn,
      String? eisenhowerQuad,
      String? sprintId,
      int? storyPoints,
      String? dueDate}) async {
    final body = <String, dynamic>{'content': content, 'priority': priority};
    if (category != null) body['category'] = category;
    if (projectId != null) body['project_id'] = projectId;
    if (kanbanColumn != null) body['kanban_column'] = kanbanColumn;
    if (eisenhowerQuad != null) body['eisenhower_quad'] = eisenhowerQuad;
    if (sprintId != null) body['sprint_id'] = sprintId;
    if (storyPoints != null) body['story_points'] = storyPoints;
    if (dueDate != null) body['due_date'] = dueDate;
    final res = await _client.post(
      _uri('/tasks'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteTask(String id) async {
    await _client.delete(_uri('/tasks/$id')).timeout(_timeout);
  }

  // Pass [clearProject] to unlink a task from its project (sets project_id null).
  Future<Map<String, dynamic>> updateTask(String id,
      {bool? done, String? dueDate, String? content, String? priority,
       String? category,
       String? kanbanColumn, String? eisenhowerQuad, String? sprintId,
       int? storyPoints, String? taskStartDate,
       String? projectId, bool clearProject = false,
       bool clearDueDate = false}) async {
    final body = <String, dynamic>{};
    if (done           != null) body['done']            = done;
    if (clearDueDate)           body['due_date']        = null;
    else if (dueDate   != null) body['due_date']        = dueDate;
    if (content        != null) body['content']         = content;
    if (priority       != null) body['priority']        = priority;
    if (category       != null) body['category']        = category;
    if (kanbanColumn   != null) body['kanban_column']   = kanbanColumn;
    if (eisenhowerQuad != null) body['eisenhower_quad'] = eisenhowerQuad;
    if (sprintId       != null) body['sprint_id']       = sprintId;
    if (storyPoints    != null) body['story_points']    = storyPoints;
    if (taskStartDate  != null) body['task_start_date'] = taskStartDate;
    if (clearProject)           body['project_id']      = null;
    else if (projectId != null) body['project_id']      = projectId;
    final res = await _client.put(
      _uri('/tasks/$id'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  // ─── Subtasks ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSubtasks(String taskId) async {
    final res = await _client
        .get(_uri('/tasks/$taskId/subtasks'), headers: _baseHeaders)
        .timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['subtasks'] ?? []);
  }

  Future<Map<String, dynamic>> addSubtask(String taskId, String content) async {
    final res = await _client.post(
      _uri('/tasks/$taskId/subtasks'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'content': content}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSubtask(String taskId, String subId,
      {bool? done, String? content}) async {
    final body = <String, dynamic>{};
    if (done    != null) body['done']    = done;
    if (content != null) body['content'] = content;
    final res = await _client.put(
      _uri('/tasks/$taskId/subtasks/$subId'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteSubtask(String taskId, String subId) async {
    await _client
        .delete(_uri('/tasks/$taskId/subtasks/$subId'), headers: _baseHeaders)
        .timeout(_timeout);
  }

  Future<Map<String, dynamic>> getStats() async {
    final res = await _client.get(_uri('/stats'), headers: _baseHeaders).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getTodayItems() async {
    final res = await _client.get(_uri('/tasks/today'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  // Smart Day Engine: scored, prioritized, load-aware day plan.
  Future<Map<String, dynamic>> getDashboardContext() async {
    // Send the user's city so the server fetches weather for the right place.
    // Passed as a query param (not a header) since city names are non-ASCII.
    final city = settings.city.trim();
    final path = city.isNotEmpty
        ? '/dashboard-context?city=${Uri.encodeQueryComponent(city)}'
        : '/dashboard-context';
    final res = await _client
        .get(_uri(path), headers: _baseHeaders)
        .timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDayPlan() async {
    final name = Uri.encodeQueryComponent(settings.userName);
    final res = await _client
        .get(_uri('/day-plan?userName=$name'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 45));
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getTaskSuggestions(String taskId) async {
    final res = await _client.post(
      _uri('/tasks/$taskId/suggest'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 25));
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['suggestions'] ?? []);
  }

  Future<Map<String, dynamic>> getTodayMessage() async {
    final res = await _client.get(_uri('/today-message'), headers: _baseHeaders).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMorningBrief() async {
    final res = await _client
        .get(_uri('/morning-briefing'), headers: _baseHeaders)
        .timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }


  Future<Map<String, dynamic>> askJarvis(
      String command, AppSettings settings, {String? intent}) async {
    final body = <String, dynamic>{
      'command': command,
      'settings': settings.toJson(),
    };
    if (intent != null && intent.isNotEmpty) body['intent'] = intent;
    final res = await _client
        .post(
          _uri('/ask-jarvis'),
          headers: _headers({'Content-Type': 'application/json'}),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  // ─── Reminders ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getReminders() async {
    final res = await _client.get(_uri('/reminders'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['reminders'] ?? []);
  }

  Future<Map<String, dynamic>> addReminder(
      String text, String scheduledTime, {String? recurrence, String? projectId}) async {
    final body = <String, dynamic>{
      'text': text,
      'scheduled_time': scheduledTime,
    };
    if (recurrence != null) body['recurrence'] = recurrence;
    if (projectId != null) body['project_id'] = projectId;
    final res = await _client.post(
      _uri('/reminders'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateReminder(String id,
      {String? text, String? scheduledTime, String? recurrence}) async {
    final body = <String, dynamic>{};
    if (text          != null) body['text']           = text;
    if (scheduledTime != null) body['scheduled_time'] = scheduledTime;
    if (recurrence    != null) body['recurrence']     = recurrence;
    final res = await _client.put(
      _uri('/reminders/$id'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteReminder(String id) async {
    await _client.delete(_uri('/reminders/$id'), headers: _baseHeaders).timeout(_timeout);
  }

  /// Returns fired (due) reminders and removes them from the server queue.
  Future<List<Map<String, dynamic>>> checkFiredReminders() async {
    final res = await _client.get(_uri('/check-reminders')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['reminders'] ?? []);
  }

  // ─── Contacts ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getContacts() async {
    final res = await _client.get(_uri('/contacts'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['contacts'] ?? []);
  }

  Future<Map<String, dynamic>> addContact(
      {required String name, String? phone, String? email}) async {
    final body = <String, dynamic>{'name': name};
    if (phone != null && phone.isNotEmpty) body['phone'] = phone;
    if (email != null && email.isNotEmpty) body['email'] = email;
    final res = await _client.post(
      _uri('/contacts'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateContact(String id,
      {String? name, String? phone, String? email}) async {
    final body = <String, dynamic>{};
    if (name  != null) body['name']  = name;
    if (phone != null) body['phone'] = phone;
    if (email != null) body['email'] = email;
    final res = await _client.put(
      _uri('/contacts/$id'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteContact(String id) async {
    await _client.delete(_uri('/contacts/$id'), headers: _baseHeaders).timeout(_timeout);
  }

  // ─── Shopping ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getShopping() async {
    final res = await _client.get(_uri('/shopping'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<Map<String, dynamic>> addShoppingItem(String item) async {
    final res = await _client.post(
      _uri('/shopping'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'item': item}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteShoppingItem(String id) async {
    await _client.delete(_uri('/shopping/$id'), headers: _baseHeaders).timeout(_timeout);
  }

  Future<Map<String, dynamic>> updateShoppingItem(String id,
      {bool? done, String? item}) async {
    final body = <String, dynamic>{};
    if (done != null) body['done'] = done;
    if (item != null) body['item'] = item;
    final res = await _client.patch(
      _uri('/shopping/$id'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  // ─── Notes ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNotes() async {
    final res = await _client.get(_uri('/notes'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['notes'] ?? []);
  }

  Future<Map<String, dynamic>> addNote(String content,
      {String title = ''}) async {
    final res = await _client.post(
      _uri('/notes'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'title': title, 'content': content}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteNote(String id) async {
    await _client.delete(_uri('/notes/$id'), headers: _baseHeaders).timeout(_timeout);
  }

  Future<Map<String, dynamic>> updateNote(String id,
      {String? title, String? content}) async {
    final body = <String, dynamic>{};
    if (title   != null) body['title']   = title;
    if (content != null) body['content'] = content;
    final res = await _client.put(
      _uri('/notes/$id'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  // ─── E2E Reports ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getE2eReports() async {
    final res = await _client.get(_uri('/e2e-reports')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['reports'] ?? []);
  }

  Future<Map<String, dynamic>> getE2eRun(String runId) async {
    final res = await _client.get(_uri('/e2e-reports/$runId')).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteE2eRun(String runId) async {
    await _client.delete(_uri('/e2e-reports/$runId')).timeout(_timeout);
  }

  Future<String> generatePromptForSelected(String runId, List<String> fingerprints) async {
    final res = await _client
        .post(_uri('/e2e-reports/$runId/prompt'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'fingerprints': fingerprints}))
        .timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return (data['claudePrompt'] as String?) ?? '';
  }

  Future<void> markFindingsDone(String runId, List<String> fingerprints) async {
    await _client
        .post(_uri('/e2e-reports/$runId/mark-done'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'fingerprints': fingerprints}))
        .timeout(_timeout);
  }


  // ─── Agents ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> healthCheck() async {
    final res = await _client.get(_uri('/health'), headers: _baseHeaders).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> triggerE2E() async {
    final res = await _client.post(
      _uri('/e2e/trigger'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({}),
    ).timeout(_timeout);
    _safeBody(res);
  }

  /// Enables/disables an agent. Pass [status] explicitly or omit to toggle.
  Future<Map<String, dynamic>> toggleAgent(String id, {String? status}) async {
    final res = await _client.post(
      _uri('/progress-map/agents/$id/toggle'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(status != null ? {'status': status} : {}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setAgentRisk(String id, String riskLevel) async {
    final res = await _client.post(
      _uri('/progress-map/agents/$id/risk'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'riskLevel': riskLevel}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  /// Live per-agent latency (avgMs/count) + intent-classification ratio.
  Future<Map<String, dynamic>> getAgentMetrics() async {
    final res = await _client.get(_uri('/progress-map/metrics'), headers: _baseHeaders).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getBacklog() async {
    final res = await _client.get(_uri('/dashboard/backlog'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res));
    if (data is List) return List<Map<String, dynamic>>.from(data);
    if (data is Map<String, dynamic>) {
      return List<Map<String, dynamic>>.from(data['items'] ?? data['backlog'] ?? []);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> generateBacklog() async {
    final res = await _client.post(
      _uri('/dashboard/backlog/generate'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 45));
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['proposals'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getAgents() async {
    final res = await _client
        .get(_uri('/progress-map/agents'))
        .timeout(_timeout);
    final data = jsonDecode(_safeBody(res));
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    if (data is Map<String, dynamic>) {
      return List<Map<String, dynamic>>.from(data['agents'] ?? []);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getSurveyCheck(String userName) async {
    final res = await _client
        .get(_uri('/survey-check?userName=${Uri.encodeComponent(userName)}'))
        .timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    final showSurvey = data['showSurvey'] as bool? ?? false;
    if (!showSurvey) return [];
    return List<Map<String, dynamic>>.from(data['questions'] ?? []);
  }

  // ─── User Profile ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getUserProfile() async {
    final res = await _client.get(_uri('/user-profile')).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    final profile = data['profile'];
    if (profile is Map<String, dynamic>) return profile;
    if (profile is Map) return Map<String, dynamic>.from(profile);
    return null;
  }

  Future<Map<String, dynamic>> saveUserProfile({
    String? speakingTone,
    List<String>? preferredHours,
    List<String>? interests,
    List<String>? recurringTasks,
    String? userName,
    String? assistantName,
    String? gender,
    String? personality,
  }) async {
    final body = <String, dynamic>{};
    if (speakingTone  != null) body['speaking_tone']   = speakingTone;
    if (preferredHours != null) body['preferred_hours'] = preferredHours;
    if (interests      != null) body['interests']       = interests;
    if (recurringTasks != null) body['recurring_tasks'] = recurringTasks;
    if (userName       != null) body['user_name']       = userName;
    if (assistantName  != null) body['assistant_name']  = assistantName;
    if (gender         != null) body['gender']          = gender;
    if (personality    != null) body['personality']     = personality;
    final res = await _client.post(
      _uri('/user-profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<void> deleteUserProfile() async {
    await _client.delete(_uri('/user-profile')).timeout(_timeout);
  }

  // ─── Projects ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getProjects() async {
    final res = await _client.get(_uri('/projects'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['projects'] ?? []);
  }

  Future<Map<String, dynamic>> createProject(Map<String, dynamic> body) async {
    final res = await _client.post(
      _uri('/projects'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['project'] as Map<String, dynamic>;
  }

  // Deterministic weekly briefing computed server-side (no LLM tokens).
  Future<String> getProjectBriefing() async {
    final res = await _client
        .get(_uri('/projects/briefing'), headers: _baseHeaders)
        .timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return (data['answer'] as String?)?.trim() ?? '';
  }

  Future<Map<String, dynamic>> getProjectDetail(String id) async {
    final res = await _client.get(_uri('/projects/$id'), headers: _baseHeaders).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProject(String id, Map<String, dynamic> body) async {
    final res = await _client.put(
      _uri('/projects/$id'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['project'] as Map<String, dynamic>;
  }

  Future<void> deleteProject(String id) async {
    await _client.delete(_uri('/projects/$id'), headers: _baseHeaders).timeout(_timeout);
  }

  Future<Map<String, dynamic>> createMilestone(
      String projectId, String title, {String? dueDate}) async {
    final res = await _client.post(
      _uri('/projects/$projectId/milestones'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'title': title, if (dueDate != null) 'due_date': dueDate}),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['milestone'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMilestone(
      String projectId, String milestoneId, Map<String, dynamic> body) async {
    final res = await _client.put(
      _uri('/projects/$projectId/milestones/$milestoneId'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['milestone'] as Map<String, dynamic>;
  }

  Future<void> deleteMilestone(String projectId, String milestoneId) async {
    await _client
        .delete(_uri('/projects/$projectId/milestones/$milestoneId'),
            headers: _baseHeaders)
        .timeout(_timeout);
  }

  Future<List<Map<String, dynamic>>> getProjectInsights(String projectId, String methodology) async {
    final res = await _client.post(
      _uri('/projects/$projectId/ai-insights'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'methodology': methodology}),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    final raw = data['insights'];
    if (raw is List) return raw.map((e) => {'text': e.toString()}).toList();
    return [];
  }

  // Cached server-side methodology recommendation (capped at 150 tokens).
  Future<Map<String, dynamic>> recommendMethodology(
      String name, String description) async {
    final res = await _client.post(
      _uri('/projects/recommend-methodology'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'name': name, 'description': description}),
    ).timeout(_timeout);
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  // ─── Sprints ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSprints(String projectId) async {
    final res = await _client.get(_uri('/projects/$projectId/sprints'), headers: _baseHeaders).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['sprints'] ?? []);
  }

  Future<Map<String, dynamic>> createSprint(String projectId, Map<String, dynamic> body) async {
    final res = await _client.post(
      _uri('/projects/$projectId/sprints'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['sprint'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSprint(String projectId, String sprintId, Map<String, dynamic> body) async {
    final res = await _client.put(
      _uri('/projects/$projectId/sprints/$sprintId'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode(body),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['sprint'] as Map<String, dynamic>;
  }

  Future<void> deleteSprint(String projectId, String sprintId) async {
    await _client.delete(_uri('/projects/$projectId/sprints/$sprintId'), headers: _baseHeaders).timeout(_timeout);
  }

  Future<Map<String, dynamic>> startSprint(String projectId, String sprintId) async {
    final res = await _client.post(
      _uri('/projects/$projectId/sprints/$sprintId/start'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({}),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['sprint'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> completeSprint(String projectId, String sprintId) async {
    final res = await _client.post(
      _uri('/projects/$projectId/sprints/$sprintId/complete'),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({}),
    ).timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return data['sprint'] as Map<String, dynamic>;
  }

  // ─── Task methodology fields ───────────────────────────────────────────────

  Future<void> updateTaskKanban(String taskId, String column) async {
    await updateTask(taskId, kanbanColumn: column);
  }

  Future<void> updateTaskEisenhower(String taskId, String? quad) async {
    await updateTask(taskId, eisenhowerQuad: quad);
  }

  Future<void> updateTaskSprint(String taskId, String? sprintId) async {
    await updateTask(taskId, sprintId: sprintId);
  }

  Future<void> updateTaskStoryPoints(String taskId, int? points) async {
    await updateTask(taskId, storyPoints: points);
  }
}
