import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_settings.dart';

/// Thin HTTP client over /missions/* endpoints. Returns parsed JSON maps;
/// the screen layer is responsible for treating the JSON shape.
class MissionService {
  final AppSettings settings;
  final http.Client _client;
  static const _timeout = Duration(seconds: 90);

  MissionService(this.settings, {http.Client? client})
      : _client = client ?? http.Client();

  Uri _u(String p) => Uri.parse('${settings.serverUrl}$p');
  Map<String, String> get _headers =>
      {'Content-Type': 'application/json; charset=utf-8'};

  Map<String, dynamic> _settingsJson() => {
        'userName': settings.userName,
        'gender': settings.gender,
        'personality': settings.personality,
        'useLocalModel': settings.useLocalModel,
      };

  Future<List<Map<String, dynamic>>> listActive() async {
    final res = await _client.get(_u('/missions/active')).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('list_failed:${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = (body['missions'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> get(int id) async {
    final res = await _client.get(_u('/missions/$id')).timeout(_timeout);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('get_failed:${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['mission'] as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> sendMessage(int id, String text) async {
    final res = await _client
        .post(_u('/missions/$id/message'),
            headers: _headers,
            body: jsonEncode({'text': text, 'settings': _settingsJson()}))
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('msg_failed:${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> approve(int id) async {
    final res = await _client
        .post(_u('/missions/$id/approve'),
            headers: _headers, body: jsonEncode({'settings': _settingsJson()}))
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('approve_failed:${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['mission'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> regeneratePlan(int id, {String feedback = ''}) async {
    final res = await _client
        .post(_u('/missions/$id/regenerate-plan'),
            headers: _headers,
            body: jsonEncode({'feedback': feedback, 'settings': _settingsJson()}))
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('regen_failed:${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancel(int id) async {
    final res = await _client.post(_u('/missions/$id/cancel'),
        headers: _headers, body: '{}').timeout(_timeout);
    if (res.statusCode != 200) throw Exception('cancel_failed:${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['mission'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setStepStatus(
      int missionId, String stepId, String status) async {
    final res = await _client
        .patch(_u('/missions/$missionId/steps/$stepId'),
            headers: _headers, body: jsonEncode({'status': status}))
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('step_failed:${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['mission'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> activateManual(int backlogId) async {
    final res = await _client
        .post(_u('/dashboard/backlog/$backlogId/activate'),
            headers: _headers, body: jsonEncode({'settings': _settingsJson()}))
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('activate_failed:${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['mission'] as Map<String, dynamic>;
  }
}
