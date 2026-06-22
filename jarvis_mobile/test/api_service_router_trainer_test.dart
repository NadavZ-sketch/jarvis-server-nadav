import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:jarvis_mobile/services/api_service.dart';
import 'package:jarvis_mobile/app_settings.dart';

void main() {
  final settings = AppSettings(useLocalServer: true, localServerUrl: 'http://localhost:3000');

  group('fetchRouterTrainingEvents', () {
    test('returns list of events on success', () async {
      final client = MockClient((_) async => http.Response(
        jsonEncode({
          'events': [
            {'id': 'abc', 'message': 'שלח לאמא', 'created_at': '2026-06-22T10:00:00Z'},
          ]
        }),
        200,
      ));
      final api = ApiService(settings, client: client);
      final events = await api.fetchRouterTrainingEvents();
      expect(events.length, 1);
      expect(events[0]['message'], 'שלח לאמא');
    });

    test('returns empty list on server error', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final api = ApiService(settings, client: client);
      expect(await api.fetchRouterTrainingEvents(), isEmpty);
    });
  });

  group('fetchRouterKeywords', () {
    test('returns overrides on success', () async {
      final client = MockClient((_) async => http.Response(
        jsonEncode({
          'overrides': [
            {'keyword': 'חלב', 'intent': 'shopping'},
          ]
        }),
        200,
      ));
      final api = ApiService(settings, client: client);
      final overrides = await api.fetchRouterKeywords();
      expect(overrides.length, 1);
      expect(overrides[0]['keyword'], 'חלב');
    });

    test('returns empty list on error', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final api = ApiService(settings, client: client);
      expect(await api.fetchRouterKeywords(), isEmpty);
    });
  });

  group('addRouterKeyword', () {
    test('sends correct POST body and returns true on 200', () async {
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/router/keywords');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['keyword'], 'חלב');
        expect(body['intent'], 'shopping');
        return http.Response(jsonEncode({'ok': true, 'overrides': []}), 200);
      });
      final api = ApiService(settings, client: client);
      expect(await api.addRouterKeyword(keyword: 'חלב', intent: 'shopping'), isTrue);
    });

    test('returns false on server error', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final api = ApiService(settings, client: client);
      expect(await api.addRouterKeyword(keyword: 'חלב', intent: 'shopping'), isFalse);
    });
  });

  group('deleteRouterKeyword', () {
    test('sends correct DELETE body and returns true on 200', () async {
      final client = MockClient((req) async {
        expect(req.method, 'DELETE');
        expect(req.url.path, '/router/keywords');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['keyword'], 'חלב');
        expect(body['intent'], 'shopping');
        return http.Response(jsonEncode({'ok': true, 'overrides': []}), 200);
      });
      final api = ApiService(settings, client: client);
      expect(await api.deleteRouterKeyword(keyword: 'חלב', intent: 'shopping'), isTrue);
    });

    test('returns false on server error', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final api = ApiService(settings, client: client);
      expect(await api.deleteRouterKeyword(keyword: 'חלב', intent: 'shopping'), isFalse);
    });
  });
}
