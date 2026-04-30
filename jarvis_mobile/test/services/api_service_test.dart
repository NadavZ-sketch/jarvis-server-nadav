import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jarvis_mobile/app_settings.dart';
import 'package:jarvis_mobile/services/api_service.dart';

http.Response _json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

ApiService _makeService(MockClient client) =>
    ApiService(AppSettings(useLocalServer: false), client: client);

void main() {
  // ─── friendlyError ─────────────────────────────────────────────────────────

  group('ApiService.friendlyError', () {
    test('TimeoutException → timeout message', () {
      final msg = ApiService.friendlyError(TimeoutException('timed out'));
      expect(msg, contains('תם הזמן'));
    });

    test('SocketException → server unavailable', () {
      final msg = ApiService.friendlyError(const SocketException('refused'));
      expect(msg, contains('השרת לא זמין'));
    });

    test('string with "timeout" → timeout message', () {
      final msg = ApiService.friendlyError(Exception('connection timeout'));
      expect(msg, contains('תם הזמן'));
    });

    test('string with "ECONNREFUSED" → server unavailable', () {
      final msg = ApiService.friendlyError(Exception('ECONNREFUSED'));
      expect(msg, contains('השרת לא זמין'));
    });

    test('FormatException → invalid response', () {
      final msg = ApiService.friendlyError(const FormatException('bad json'));
      expect(msg, contains('תשובה לא תקינה'));
    });

    test('HTML cold-start error → passes through Hebrew message', () {
      final msg = ApiService.friendlyError(
          Exception('השרת אינו זמין כרגע — נסה שוב בעוד רגע'));
      expect(msg, contains('השרת אינו זמין כרגע'));
    });

    test('unknown error → generic retry message', () {
      final msg = ApiService.friendlyError(Exception('something weird'));
      expect(msg, contains('אירעה שגיאה'));
    });
  });

  // ─── HTML body detection ────────────────────────────────────────────────────

  group('HTML cold-start detection', () {
    test('DOCTYPE response → throws', () async {
      final client = MockClient((_) async => http.Response(
          '<!DOCTYPE html><html><body>Starting…</body></html>', 200));
      final svc = _makeService(client);
      expect(svc.getTasks(), throwsException);
    });

    test('<html> response → throws', () async {
      final client = MockClient((_) async => http.Response(
          '<html><body>cold start</body></html>', 200));
      final svc = _makeService(client);
      expect(svc.getReminders(), throwsException);
    });
  });

  // ─── Tasks ─────────────────────────────────────────────────────────────────

  group('getTasks', () {
    test('returns parsed task list', () async {
      final tasks = [
        {'id': '1', 'content': 'Buy milk', 'done': false},
        {'id': '2', 'content': 'Walk dog', 'done': true},
      ];
      final client =
          MockClient((_) async => _json({'tasks': tasks}));
      final result = await _makeService(client).getTasks();
      expect(result.length, 2);
      expect(result[0]['content'], 'Buy milk');
      expect(result[1]['done'], true);
    });

    test('returns empty list when tasks key missing', () async {
      final client = MockClient((_) async => _json({}));
      final result = await _makeService(client).getTasks();
      expect(result, isEmpty);
    });

    test('sends GET to /tasks', () async {
      Uri? captured;
      final client = MockClient((req) async {
        captured = req.url;
        return _json({'tasks': []});
      });
      await _makeService(client).getTasks();
      expect(captured?.path, '/tasks');
      expect(captured?.scheme, 'https');
    });
  });

  group('addTask', () {
    test('sends POST with content and returns response', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '42', 'content': 'Test', 'done': false});
      });
      final result = await _makeService(client).addTask('Test task');
      final decoded = jsonDecode(sentBody!);
      expect(decoded['content'], 'Test task');
      expect(result['id'], '42');
    });
  });

  group('deleteTask', () {
    test('sends DELETE to /tasks/:id', () async {
      Uri? captured;
      String? method;
      final client = MockClient((req) async {
        captured = req.url;
        method = req.method;
        return http.Response('', 204);
      });
      await _makeService(client).deleteTask('99');
      expect(method, 'DELETE');
      expect(captured?.path, '/tasks/99');
    });
  });

  group('updateTask', () {
    test('sends PUT with done=true', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '1', 'done': true});
      });
      await _makeService(client).updateTask('1', done: true);
      expect(jsonDecode(sentBody!)['done'], true);
    });

    test('omits null fields from body', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '1'});
      });
      await _makeService(client).updateTask('1', content: 'new');
      final body = jsonDecode(sentBody!);
      expect(body.containsKey('done'), false);
      expect(body['content'], 'new');
    });
  });

  // ─── Reminders ─────────────────────────────────────────────────────────────

  group('getReminders', () {
    test('returns reminder list', () async {
      final reminders = [
        {'id': '1', 'text': 'לשתות מים', 'scheduled_time': '2026-04-17T10:30:00+03:00'},
      ];
      final client = MockClient((_) async => _json({'reminders': reminders}));
      final result = await _makeService(client).getReminders();
      expect(result.length, 1);
      expect(result[0]['text'], 'לשתות מים');
    });
  });

  group('addReminder', () {
    test('sends text and scheduled_time', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '5'});
      });
      await _makeService(client)
          .addReminder('לשתות מים', '2026-04-17T10:30:00+03:00');
      final body = jsonDecode(sentBody!);
      expect(body['text'], 'לשתות מים');
      expect(body['scheduled_time'], '2026-04-17T10:30:00+03:00');
      expect(body.containsKey('recurrence'), false);
    });

    test('includes recurrence when provided', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '6'});
      });
      await _makeService(client).addReminder(
          'לשתות מים', '2026-04-17T10:30:00+03:00',
          recurrence: 'daily');
      expect(jsonDecode(sentBody!)['recurrence'], 'daily');
    });
  });

  group('deleteReminder', () {
    test('sends DELETE to /reminders/:id', () async {
      String? method;
      Uri? captured;
      final client = MockClient((req) async {
        method = req.method;
        captured = req.url;
        return http.Response('', 204);
      });
      await _makeService(client).deleteReminder('7');
      expect(method, 'DELETE');
      expect(captured?.path, '/reminders/7');
    });
  });

  group('checkFiredReminders', () {
    test('returns fired reminders list', () async {
      final client = MockClient((_) async => _json({
            'reminders': [
              {'id': '3', 'text': 'אימון'}
            ]
          }));
      final result = await _makeService(client).checkFiredReminders();
      expect(result.length, 1);
      expect(result[0]['text'], 'אימון');
    });
  });

  // ─── Contacts ─────────────────────────────────────────────────────────────

  group('getContacts', () {
    test('returns contact list', () async {
      final client = MockClient((_) async => _json({
            'contacts': [
              {'id': '1', 'name': 'דני', 'phone': '050-1234567'}
            ]
          }));
      final result = await _makeService(client).getContacts();
      expect(result[0]['name'], 'דני');
    });
  });

  group('addContact', () {
    test('sends name and optional phone/email', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '10'});
      });
      await _makeService(client)
          .addContact(name: 'שרה', phone: '052-9999999');
      final body = jsonDecode(sentBody!);
      expect(body['name'], 'שרה');
      expect(body['phone'], '052-9999999');
      expect(body.containsKey('email'), false);
    });

    test('omits empty phone and email', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '11'});
      });
      await _makeService(client)
          .addContact(name: 'רון', phone: '', email: '');
      final body = jsonDecode(sentBody!);
      expect(body.containsKey('phone'), false);
      expect(body.containsKey('email'), false);
    });
  });

  // ─── Shopping ─────────────────────────────────────────────────────────────

  group('getShopping', () {
    test('returns items list', () async {
      final client = MockClient((_) async => _json({
            'items': [
              {'id': '1', 'item': 'חלב', 'done': false}
            ]
          }));
      final result = await _makeService(client).getShopping();
      expect(result[0]['item'], 'חלב');
    });
  });

  group('updateShoppingItem', () {
    test('sends PATCH with done flag', () async {
      String? method;
      String? sentBody;
      final client = MockClient((req) async {
        method = req.method;
        sentBody = req.body;
        return _json({'id': '1', 'done': true});
      });
      await _makeService(client).updateShoppingItem('1', done: true);
      expect(method, 'PATCH');
      expect(jsonDecode(sentBody!)['done'], true);
    });
  });

  // ─── Notes ────────────────────────────────────────────────────────────────

  group('getNotes', () {
    test('returns notes list', () async {
      final client = MockClient((_) async => _json({
            'notes': [
              {'id': '1', 'title': 'רעיון', 'content': 'מעניין'}
            ]
          }));
      final result = await _makeService(client).getNotes();
      expect(result[0]['title'], 'רעיון');
    });
  });

  group('addNote', () {
    test('sends title and content', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '20'});
      });
      await _makeService(client).addNote('גוף ההערה', title: 'כותרת');
      final body = jsonDecode(sentBody!);
      expect(body['title'], 'כותרת');
      expect(body['content'], 'גוף ההערה');
    });

    test('defaults title to empty string', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return _json({'id': '21'});
      });
      await _makeService(client).addNote('just content');
      expect(jsonDecode(sentBody!)['title'], '');
    });
  });
}
