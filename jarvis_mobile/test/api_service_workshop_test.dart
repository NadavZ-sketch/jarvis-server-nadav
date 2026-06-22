import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:jarvis_mobile/services/api_service.dart';
import 'package:jarvis_mobile/app_settings.dart';

void main() {
  final settings = AppSettings(useLocalServer: true, localServerUrl: 'http://localhost:3000');

  group('workshopChat', () {
    test('returns reply and spec on success', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/workshop/42/chat');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['message'], 'Hello');
        return http.Response(
          jsonEncode({'reply': 'Hi there', 'spec': {'name': 'Test', 'type': 'feature', 'description': 'Desc', 'acceptanceCriteria': ['AC1']}}),
          200,
        );
      });
      final api = ApiService(settings, client: client);
      final result = await api.workshopChat(proposalId: 42, message: 'Hello', history: []);
      expect(result?['reply'], 'Hi there');
      expect((result?['spec'] as Map)['name'], 'Test');
    });

    test('returns null on error', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final api = ApiService(settings, client: client);
      final result = await api.workshopChat(proposalId: 42, message: 'Hello', history: []);
      expect(result, isNull);
    });
  });

  group('getWorkshopHistory', () {
    test('returns proposal workshopHistory', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/dashboard/backlog');
        return http.Response(
          jsonEncode({'proposals': [{'id': 42, 'title': 'T', 'workshopHistory': [{'role': 'user', 'content': 'hi'}]}], 'items': []}),
          200,
        );
      });
      final api = ApiService(settings, client: client);
      final result = await api.getWorkshopHistory(proposalId: 42);
      expect(result.length, 1);
      expect(result.first['role'], 'user');
    });
  });
}
