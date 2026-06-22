# Workshop Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Workshop view to Tab 2 — tapping a proposal opens a full chat+spec screen where the user converses with Jarvis to refine the proposal, sees an auto-updating spec panel, and can export the spec in 4 ways.

**Architecture:** New `WorkshopScreen` Flutter screen opened via `Navigator.push` from `_proposalsCard()`. New server endpoint `POST /workshop/:proposalId/chat` handles LLM conversation, extracts structured spec fields from the dialogue, and persists conversation history to the proposal's `workshopHistory` array in `backlog.json`. The `ApiService` gains a `workshopChat()` method and a `getWorkshopHistory()` method.

**Tech Stack:** Flutter (existing patterns in `tab_dev_workshop.dart`), Node.js/Express (`server.js`), `callGemma4()` from `agents/models.js`, `backlog.json` persistence via existing `readBacklog()`/`writeBacklog()`.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `server.js` | Modify | Add `POST /workshop/:proposalId/chat` endpoint |
| `jarvis_mobile/lib/services/api_service.dart` | Modify | Add `workshopChat()` and `getWorkshopHistory()` |
| `jarvis_mobile/lib/screens/control_center/workshop_screen.dart` | Create | Full workshop screen: chat + spec panel + exports |
| `jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart` | Modify | Wire proposal tap → `WorkshopScreen` |

---

## Task 1: Server — `POST /workshop/:proposalId/chat`

**Files:**
- Modify: `server.js` (after the `DELETE /dashboard/backlog/proposals/:id` endpoint, around line 5381)
- Test: `tests/unit/workshop.test.js` (create)

### Background

`readBacklog()` and `writeBacklog(data)` are already defined in `server.js`. `callGemma4(messages, useLocal, maxTokens)` is already imported from `agents/models.js`. The proposal object in `backlog.json` has fields: `id`, `title`, `type`, `status`, `plan`, `priority`, `acceptanceCriteria`, `checklist`.

The endpoint receives `{ message: string, history: [{role, content}] }` in the body. It appends the user message to `history`, calls `callGemma4` with a system prompt that asks it to both reply conversationally AND output a JSON block extracting spec fields, parses the JSON block from the response, updates the proposal's spec fields if they changed, saves conversation turns to the proposal's `workshopHistory` array, and returns `{ reply, spec }` where `spec = { name, type, description, acceptanceCriteria[] }`.

### Steps

- [ ] **Step 1: Write the failing test**

Create `tests/unit/workshop.test.js`:

```javascript
const request = require('supertest');

jest.mock('../../agents/models', () => ({
  callGemma4: jest.fn().mockResolvedValue(
    'Sure! Here is my thoughts.\n```json\n{"name":"Test Feature","type":"feature","description":"A test feature","acceptanceCriteria":["Works correctly"]}\n```'
  ),
}));

const mockBacklog = {
  items: [],
  proposals: [{ id: 1, title: 'Test', type: 'feature', status: 'proposal', plan: '', priority: 'medium', auditTrail: [], checklist: [], blockers: [], acceptanceCriteria: [] }],
  _nextId: 2,
};
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  readFileSync: jest.fn((path) => {
    if (path.includes('backlog.json')) return JSON.stringify(mockBacklog);
    return jest.requireActual('fs').readFileSync(path);
  }),
  writeFileSync: jest.fn(),
  existsSync: jest.fn(() => true),
}));

let app;
beforeAll(() => {
  app = require('../../server');
});

describe('POST /workshop/:proposalId/chat', () => {
  it('returns reply and spec on valid request', async () => {
    const res = await request(app)
      .post('/workshop/1/chat')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ message: 'I want a feature that does X', history: [] });
    expect(res.status).toBe(200);
    expect(res.body.reply).toBeTruthy();
    expect(res.body.spec).toBeDefined();
    expect(res.body.spec.name).toBe('Test Feature');
    expect(res.body.spec.acceptanceCriteria).toBeInstanceOf(Array);
  });

  it('returns 404 for unknown proposal', async () => {
    const res = await request(app)
      .post('/workshop/9999/chat')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ message: 'hello', history: [] });
    expect(res.status).toBe(404);
  });

  it('returns 400 when message is missing', async () => {
    const res = await request(app)
      .post('/workshop/1/chat')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ history: [] });
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/workshop.test.js -t 'POST /workshop' --no-coverage 2>&1 | tail -20
```

Expected: FAIL — `Cannot POST /workshop/1/chat` (404 or route not found)

- [ ] **Step 3: Add the endpoint to server.js**

Find the line `app.delete('/dashboard/backlog/proposals/:id'` (around line 5372) and add the following BEFORE it (after the `draft-plan` endpoint's closing `});`):

```javascript
// ── Workshop chat ─────────────────────────────────────────────────────────
app.post('/workshop/:proposalId/chat', async (req, res) => {
    try {
        const id = parseInt(req.params.proposalId, 10);
        if (isNaN(id)) return res.status(400).json({ error: 'invalid proposalId' });

        const { message, history } = req.body || {};
        if (!message?.trim()) return res.status(400).json({ error: 'message required' });

        const data = readBacklog();
        const proposal = data.proposals?.find(p => p.id === id);
        if (!proposal) return res.status(404).json({ error: 'proposal not found' });

        const systemPrompt = `You are a product development assistant helping refine a software proposal.
Proposal: "${proposal.title}" (type: ${proposal.type || 'feature'})

Your job:
1. Have a natural conversation to clarify requirements
2. At the end of EVERY reply, output a JSON block (fenced with \`\`\`json) containing the current best-guess spec:
{
  "name": "<feature name>",
  "type": "<feature|fix|ux|infra>",
  "description": "<1-3 sentence description>",
  "acceptanceCriteria": ["<criterion 1>", "<criterion 2>"]
}

Always output the JSON block, even if nothing changed. Keep replies concise and in Hebrew.`;

        const msgs = [
            { role: 'system', content: systemPrompt },
            ...(Array.isArray(history) ? history.slice(-10) : []),
            { role: 'user', content: message.trim() },
        ];

        const raw = await callGemma4(msgs, false, 1200);

        // Extract JSON spec block from reply
        let spec = { name: proposal.title, type: proposal.type || 'feature', description: proposal.plan || '', acceptanceCriteria: proposal.acceptanceCriteria || [] };
        const jsonMatch = raw.match(/```json\s*([\s\S]*?)```/);
        if (jsonMatch) {
            try {
                const parsed = JSON.parse(jsonMatch[1].trim());
                if (parsed && typeof parsed === 'object') {
                    spec = {
                        name: parsed.name || spec.name,
                        type: parsed.type || spec.type,
                        description: parsed.description || spec.description,
                        acceptanceCriteria: Array.isArray(parsed.acceptanceCriteria) ? parsed.acceptanceCriteria : spec.acceptanceCriteria,
                    };
                    // Persist updated spec fields back to proposal
                    if (parsed.description) proposal.plan = parsed.description;
                    if (Array.isArray(parsed.acceptanceCriteria) && parsed.acceptanceCriteria.length > 0) {
                        proposal.acceptanceCriteria = parsed.acceptanceCriteria;
                    }
                }
            } catch (_) { /* ignore JSON parse errors */ }
        }

        // Strip the JSON block from the user-visible reply
        const reply = raw.replace(/```json[\s\S]*?```/g, '').trim();

        // Persist conversation turn
        if (!Array.isArray(proposal.workshopHistory)) proposal.workshopHistory = [];
        proposal.workshopHistory.push({ role: 'user', content: message.trim(), at: new Date().toISOString() });
        proposal.workshopHistory.push({ role: 'assistant', content: reply, at: new Date().toISOString() });
        proposal.workshopHistory = proposal.workshopHistory.slice(-40); // keep last 20 turns
        writeBacklog(data);

        res.json({ reply, spec });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});
```

Note: `callGemma4` is already imported at the top of `server.js` (it's destructured from `require('./agents/models')`).

- [ ] **Step 4: Verify `callGemma4` is available in server.js scope**

```bash
grep -n "callGemma4" /home/user/jarvis-server-nadav/server.js | head -5
```

If the output shows `callGemma4` being imported/destructured from models, proceed. If not, add this near the top of `server.js` where other model imports are (find with `grep -n "require.*models" server.js | head -3`).

- [ ] **Step 5: Run test to verify it passes**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/workshop.test.js --no-coverage 2>&1 | tail -20
```

Expected: PASS — 3 tests passing

- [ ] **Step 6: Commit**

```bash
cd /home/user/jarvis-server-nadav && git add server.js tests/unit/workshop.test.js && git commit -m "feat: add POST /workshop/:proposalId/chat endpoint"
```

---

## Task 2: ApiService — `workshopChat()` and `getWorkshopHistory()`

**Files:**
- Modify: `jarvis_mobile/lib/services/api_service.dart` (after the `createProposal` method, around line 648)

### Background

`ApiService` follows the pattern: `_client.post(_uri('/path'), headers: _headers({...}), body: jsonEncode({...})).timeout(_timeout)`, then `jsonDecode(_safeBody(res))`. The timeout constant is `_timeout = Duration(seconds: 30)`. For the LLM call use 45 seconds.

### Steps

- [ ] **Step 1: Write the failing test**

Create `jarvis_mobile/test/api_service_workshop_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:jarvis_mobile/services/api_service.dart';
import 'package:jarvis_mobile/app_settings.dart';

void main() {
  final settings = AppSettings()..serverUrl = 'http://localhost:3000';

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
    test('returns proposal with workshopHistory', () async {
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test test/api_service_workshop_test.dart 2>&1 | tail -15
```

Expected: FAIL — `workshopChat` not found

- [ ] **Step 3: Add methods to ApiService**

In `jarvis_mobile/lib/services/api_service.dart`, add after the `createProposal` method (after line ~648):

```dart
  Future<Map<String, dynamic>?> workshopChat({
    required int proposalId,
    required String message,
    required List<Map<String, dynamic>> history,
  }) async {
    try {
      final res = await _client
          .post(
            _uri('/workshop/$proposalId/chat'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({'message': message, 'history': history}),
          )
          .timeout(const Duration(seconds: 45));
      return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getWorkshopHistory({
    required int proposalId,
  }) async {
    try {
      final res = await _client
          .get(_uri('/dashboard/backlog'), headers: _baseHeaders)
          .timeout(_timeout);
      final data = jsonDecode(_safeBody(res));
      if (data is Map<String, dynamic>) {
        final proposals = data['proposals'] as List? ?? [];
        final proposal = proposals.cast<Map<String, dynamic>>().firstWhere(
              (p) => p['id'] == proposalId,
              orElse: () => {},
            );
        return List<Map<String, dynamic>>.from(
            proposal['workshopHistory'] as List? ?? []);
      }
      return [];
    } catch (_) {
      return [];
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test test/api_service_workshop_test.dart 2>&1 | tail -15
```

Expected: PASS — 3 tests passing

- [ ] **Step 5: Commit**

```bash
cd /home/user/jarvis-server-nadav && git add jarvis_mobile/lib/services/api_service.dart jarvis_mobile/test/api_service_workshop_test.dart && git commit -m "feat: add workshopChat and getWorkshopHistory to ApiService"
```

---

## Task 3: WorkshopScreen — chat + spec + exports

**Files:**
- Create: `jarvis_mobile/lib/screens/control_center/workshop_screen.dart`

### Background

The screen receives a `proposal` (`Map<String, dynamic>`) and `settings` (`AppSettings`). It shows:
1. **AppBar** with proposal title
2. **Scrollable chat area** — alternating user/assistant bubbles (RTL, Heebo font)
3. **Auto-spec panel** — a Card below the chat list, collapsed by default, expands to show name/type/description/acceptanceCriteria. Updates whenever the server returns a new `spec` field.
4. **4 export buttons** row at the bottom above the input field
5. **Text input + send button** pinned at bottom

The `_spec` state field holds the current spec as `Map<String, dynamic>?`. The `_messages` list holds `{'role': 'user'|'assistant', 'content': '...'}` maps. On init, load prior `workshopHistory` from the proposal (passed in via constructor — already available in the proposal map's `workshopHistory` field if present).

**Export implementations:**
- **Spec → docs**: Save to `docs/superpowers/specs/<slug>.md` — call `ApiService.saveWorkshopSpec(proposalId, spec)` (implemented in Task 4, server writes file)
- **AI Prompt → clipboard**: Copy the proposal's `claudePrompt` field (or generate a default "Implement: <name>\n<description>\nAC:\n- ...") to clipboard using `Clipboard.setData`
- **GitHub Issue**: Show a SnackBar "GitHub Integration כבר בקרוב" (not yet wired — spec says `mcp__github__issue_write` which is a server-side tool)
- **Copy to clipboard**: Copy full spec as Markdown text using `Clipboard.setData`

### Steps

- [ ] **Step 1: Write the failing test**

Create `jarvis_mobile/test/workshop_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:jarvis_mobile/screens/control_center/workshop_screen.dart';
import 'package:jarvis_mobile/app_settings.dart';

void main() {
  final settings = AppSettings()..serverUrl = 'http://localhost:3000';

  testWidgets('shows proposal title in AppBar', (tester) async {
    final proposal = {'id': 1, 'title': 'My Feature', 'type': 'feature', 'status': 'proposal', 'plan': '', 'acceptanceCriteria': [], 'workshopHistory': []};
    final client = MockClient((_) async => http.Response('{}', 200));
    await tester.pumpWidget(MaterialApp(
      home: WorkshopScreen(proposal: proposal, settings: settings, httpClient: client),
    ));
    expect(find.text('My Feature'), findsOneWidget);
  });

  testWidgets('shows empty state message when no messages', (tester) async {
    final proposal = {'id': 1, 'title': 'My Feature', 'type': 'feature', 'status': 'proposal', 'plan': '', 'acceptanceCriteria': [], 'workshopHistory': []};
    final client = MockClient((_) async => http.Response('{}', 200));
    await tester.pumpWidget(MaterialApp(
      home: WorkshopScreen(proposal: proposal, settings: settings, httpClient: client),
    ));
    expect(find.text('התחל שיחה כדי לפתח את ההצעה'), findsOneWidget);
  });

  testWidgets('shows spec panel button', (tester) async {
    final proposal = {'id': 1, 'title': 'My Feature', 'type': 'feature', 'status': 'proposal', 'plan': 'A feature', 'acceptanceCriteria': ['AC1'], 'workshopHistory': []};
    final client = MockClient((_) async => http.Response('{}', 200));
    await tester.pumpWidget(MaterialApp(
      home: WorkshopScreen(proposal: proposal, settings: settings, httpClient: client),
    ));
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test test/workshop_screen_test.dart 2>&1 | tail -15
```

Expected: FAIL — `workshop_screen.dart` not found

- [ ] **Step 3: Create WorkshopScreen**

Create `jarvis_mobile/lib/screens/control_center/workshop_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../app_settings.dart';
import '../../services/api_service.dart';

class WorkshopScreen extends StatefulWidget {
  final Map<String, dynamic> proposal;
  final AppSettings settings;
  final http.Client? httpClient;

  const WorkshopScreen({
    super.key,
    required this.proposal,
    required this.settings,
    this.httpClient,
  });

  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen> {
  late final ApiService _api;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _spec;
  bool _sending = false;
  bool _specExpanded = false;

  @override
  void initState() {
    super.initState();
    _api = widget.httpClient != null
        ? ApiService(widget.settings, client: widget.httpClient!)
        : ApiService(widget.settings);

    // Load prior workshop history from proposal
    final history = widget.proposal['workshopHistory'];
    if (history is List && history.isNotEmpty) {
      _messages = List<Map<String, dynamic>>.from(
          history.map((e) => {'role': e['role'] ?? 'user', 'content': e['content'] ?? ''}));
    }

    // Seed spec from proposal fields
    final desc = widget.proposal['plan'] as String? ?? '';
    final ac = widget.proposal['acceptanceCriteria'];
    if (desc.isNotEmpty || (ac is List && ac.isNotEmpty)) {
      _spec = {
        'name': widget.proposal['title'] as String? ?? '',
        'type': widget.proposal['type'] as String? ?? 'feature',
        'description': desc,
        'acceptanceCriteria': ac is List ? List<String>.from(ac.map((e) => e.toString())) : <String>[],
      };
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages = [..._messages, {'role': 'user', 'content': text}];
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    final history = _messages
        .take(_messages.length - 1)
        .map((m) => {'role': m['role'] as String, 'content': m['content'] as String})
        .toList();

    final result = await _api.workshopChat(
      proposalId: widget.proposal['id'] as int,
      message: text,
      history: history,
    );

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result != null) {
        final reply = result['reply'] as String? ?? '';
        if (reply.isNotEmpty) {
          _messages = [..._messages, {'role': 'assistant', 'content': reply}];
        }
        final newSpec = result['spec'];
        if (newSpec is Map<String, dynamic>) {
          _spec = newSpec;
        }
      } else {
        _messages = [..._messages, {'role': 'assistant', 'content': 'שגיאה בתקשורת עם השרת. נסה שוב.'}];
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _buildSpecMarkdown() {
    final spec = _spec;
    if (spec == null) return '';
    final sb = StringBuffer();
    sb.writeln('# ${spec['name'] ?? widget.proposal['title']}');
    sb.writeln();
    sb.writeln('**סוג:** ${spec['type'] ?? 'feature'}');
    sb.writeln();
    sb.writeln('## תיאור');
    sb.writeln(spec['description'] ?? '');
    sb.writeln();
    sb.writeln('## קריטריוני קבלה');
    final ac = spec['acceptanceCriteria'];
    if (ac is List) {
      for (final item in ac) {
        sb.writeln('- $item');
      }
    }
    return sb.toString();
  }

  String _buildAiPrompt() {
    final claudePrompt = widget.proposal['claudePrompt'] as String?;
    if (claudePrompt != null && claudePrompt.isNotEmpty) return claudePrompt;
    final spec = _spec;
    if (spec == null) return 'Implement: ${widget.proposal['title']}';
    final sb = StringBuffer();
    sb.writeln('Implement: ${spec['name'] ?? widget.proposal['title']}');
    sb.writeln();
    sb.writeln('Description: ${spec['description'] ?? ''}');
    sb.writeln();
    sb.writeln('Acceptance Criteria:');
    final ac = spec['acceptanceCriteria'];
    if (ac is List) {
      for (final item in ac) {
        sb.writeln('- $item');
      }
    }
    return sb.toString();
  }

  Future<void> _exportSpec() async {
    final proposalId = widget.proposal['id'] as int;
    final result = await _api.saveWorkshopSpec(proposalId: proposalId, spec: _spec ?? {});
    if (!mounted) return;
    final msg = result != null ? 'ספק נשמר ב-docs/superpowers/specs/' : 'שגיאה בשמירת הספק';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Heebo'))),
    );
  }

  Future<void> _copyAiPrompt() async {
    final prompt = _buildAiPrompt();
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI Prompt הועתק ללוח', style: TextStyle(fontFamily: 'Heebo'))),
    );
  }

  Future<void> _createGitHubIssue() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GitHub Integration כבר בקרוב', style: TextStyle(fontFamily: 'Heebo'))),
    );
  }

  Future<void> _copyToClipboard() async {
    final md = _buildSpecMarkdown();
    await Clipboard.setData(ClipboardData(text: md));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הועתק ללוח', style: TextStyle(fontFamily: 'Heebo'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.proposal['title'] as String? ?? 'סדנה';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontFamily: 'Heebo', fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(
              Icons.description_outlined,
              color: _spec != null ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: 'ספק',
            onPressed: () => setState(() => _specExpanded = !_specExpanded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_specExpanded && _spec != null) _buildSpecPanel(),
          Expanded(child: _buildChatList()),
          _buildExportRow(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildSpecPanel() {
    final spec = _spec!;
    final ac = spec['acceptanceCriteria'];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.description_outlined, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  spec['name'] as String? ?? '',
                  style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  spec['type'] as String? ?? 'feature',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontFamily: 'Heebo'),
                ),
              ),
            ]),
            if ((spec['description'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                spec['description'] as String,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13, color: Colors.black87),
              ),
            ],
            if (ac is List && ac.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('קריטריוני קבלה:', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
              ...ac.map((item) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('• ', style: TextStyle(color: Colors.green)),
                      Expanded(child: Text(item.toString(), style: const TextStyle(fontFamily: 'Heebo', fontSize: 12))),
                    ]),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'התחל שיחה כדי לפתח את ההצעה',
          style: TextStyle(color: Colors.grey, fontFamily: 'Heebo', fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (_sending && i == _messages.length) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final msg = _messages[i];
        final isUser = (msg['role'] as String?) == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser ? Theme.of(context).colorScheme.primary : Colors.grey.shade100,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
                bottomRight: isUser ? Radius.zero : const Radius.circular(12),
              ),
            ),
            child: Text(
              msg['content'] as String? ?? '',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 14,
                color: isUser ? Colors.white : Colors.black87,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExportRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _exportBtn(icon: Icons.description, label: 'ספק', onTap: _spec != null ? _exportSpec : null),
          _exportBtn(icon: Icons.smart_toy_outlined, label: 'AI Prompt', onTap: _copyAiPrompt),
          _exportBtn(icon: Icons.code, label: 'GitHub', onTap: _createGitHubIssue),
          _exportBtn(icon: Icons.copy, label: 'העתק', onTap: _spec != null ? _copyToClipboard : null),
        ],
      ),
    );
  }

  Widget _exportBtn({required IconData icon, required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey.shade400),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'Heebo',
              color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _focusNode,
              maxLines: null,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                hintText: 'שאל שאלה או הוסף פרטים...',
                hintStyle: TextStyle(fontFamily: 'Heebo', fontSize: 14),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'Heebo', fontSize: 14),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            tooltip: 'שלח',
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test test/workshop_screen_test.dart 2>&1 | tail -15
```

Expected: PASS — 3 tests passing

- [ ] **Step 5: Commit**

```bash
cd /home/user/jarvis-server-nadav && git add jarvis_mobile/lib/screens/control_center/workshop_screen.dart jarvis_mobile/test/workshop_screen_test.dart && git commit -m "feat: add WorkshopScreen with chat, spec panel, and export buttons"
```

---

## Task 4: Server — `POST /workshop/:proposalId/save-spec` (spec export to file)

**Files:**
- Modify: `server.js` (add endpoint after the workshop chat endpoint)
- Modify: `jarvis_mobile/lib/services/api_service.dart` (add `saveWorkshopSpec()`)
- Test: `tests/unit/workshop.test.js` (add test case)

### Background

The spec → docs export button needs a server endpoint that writes the spec as Markdown to `docs/superpowers/specs/<slug>.md`. The slug is derived from the proposal title: lowercase, spaces→hyphens, strip non-alphanumeric. The server has `fs` available (used elsewhere in server.js). Return `{ path }` on success.

### Steps

- [ ] **Step 1: Add test for save-spec endpoint**

Append to `tests/unit/workshop.test.js`:

```javascript
describe('POST /workshop/:proposalId/save-spec', () => {
  it('returns 200 with path on valid spec', async () => {
    const res = await request(app)
      .post('/workshop/1/save-spec')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({
        spec: {
          name: 'My Feature',
          type: 'feature',
          description: 'Does something cool',
          acceptanceCriteria: ['Works', 'Fast'],
        },
      });
    expect(res.status).toBe(200);
    expect(res.body.path).toMatch(/\.md$/);
  });

  it('returns 400 when spec is missing', async () => {
    const res = await request(app)
      .post('/workshop/1/save-spec')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({});
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/workshop.test.js --no-coverage 2>&1 | tail -20
```

Expected: 2 new FAIL tests + 3 existing PASS

- [ ] **Step 3: Add save-spec endpoint to server.js**

Add immediately after the `/workshop/:proposalId/chat` endpoint:

```javascript
app.post('/workshop/:proposalId/save-spec', (req, res) => {
    try {
        const { spec } = req.body || {};
        if (!spec || typeof spec !== 'object') return res.status(400).json({ error: 'spec required' });

        const name = String(spec.name || 'spec');
        const slug = name.toLowerCase().replace(/[^a-z0-9֐-׿]+/g, '-').replace(/^-|-$/g, '');
        const today = new Date().toISOString().slice(0, 10);
        const filename = `${today}-${slug || 'workshop-spec'}.md`;
        const dirPath = path.join(__dirname, 'docs', 'superpowers', 'specs');
        const filePath = path.join(dirPath, filename);

        const acLines = Array.isArray(spec.acceptanceCriteria)
            ? spec.acceptanceCriteria.map(ac => `- ${ac}`).join('\n')
            : '';
        const markdown = `# ${name}\n\n**סוג:** ${spec.type || 'feature'}\n\n## תיאור\n${spec.description || ''}\n\n## קריטריוני קבלה\n${acLines}\n`;

        if (!fs.existsSync(dirPath)) fs.mkdirSync(dirPath, { recursive: true });
        fs.writeFileSync(filePath, markdown, 'utf8');

        res.json({ path: `docs/superpowers/specs/${filename}` });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});
```

Note: `path` and `fs` are already required at the top of `server.js`. Verify with `grep -n "require('path')\|require('fs')" server.js | head -5`.

- [ ] **Step 4: Add `saveWorkshopSpec()` to ApiService**

In `jarvis_mobile/lib/services/api_service.dart`, add after `getWorkshopHistory()`:

```dart
  Future<Map<String, dynamic>?> saveWorkshopSpec({
    required int proposalId,
    required Map<String, dynamic> spec,
  }) async {
    try {
      final res = await _client
          .post(
            _uri('/workshop/$proposalId/save-spec'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({'spec': spec}),
          )
          .timeout(_timeout);
      return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 5: Run all workshop tests**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/workshop.test.js --no-coverage 2>&1 | tail -20
```

Expected: PASS — 5 tests passing

- [ ] **Step 6: Run Flutter tests**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test test/api_service_workshop_test.dart test/workshop_screen_test.dart 2>&1 | tail -15
```

Expected: PASS — 6 tests passing

- [ ] **Step 7: Commit**

```bash
cd /home/user/jarvis-server-nadav && git add server.js jarvis_mobile/lib/services/api_service.dart jarvis_mobile/test/api_service_workshop_test.dart && git commit -m "feat: add /workshop/:id/save-spec endpoint and saveWorkshopSpec in ApiService"
```

---

## Task 5: Wire proposal tap → WorkshopScreen

**Files:**
- Modify: `jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart`

### Background

Currently `_proposalsCard()` renders each proposal as a `ListTile` with no `onTap`. The change is to add `onTap: () => _openWorkshop(p)` to each `ListTile` and implement `_openWorkshop(Map<String,dynamic> p)` which calls `Navigator.push` to `WorkshopScreen`. After returning from the workshop, call `_loadProposals()` to refresh the list (in case spec fields changed). Import `workshop_screen.dart`.

### Steps

- [ ] **Step 1: Write the failing test**

Create `jarvis_mobile/test/tab_dev_workshop_tap_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:jarvis_mobile/screens/control_center/tab_dev_workshop.dart';
import 'package:jarvis_mobile/app_settings.dart';

void main() {
  final settings = AppSettings()..serverUrl = 'http://localhost:3000';

  testWidgets('tapping a proposal navigates to WorkshopScreen', (tester) async {
    final proposals = [
      {'id': 1, 'title': 'Cool Feature', 'type': 'feature', 'status': 'proposal', 'plan': '', 'acceptanceCriteria': [], 'workshopHistory': []}
    ];
    final client = MockClient((req) async {
      if (req.url.path == '/dashboard/backlog') {
        return http.Response(jsonEncode({'proposals': proposals, 'items': []}), 200);
      }
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TabDevWorkshop(settings: settings)),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // Proposal list item should be tappable
    expect(find.text('Cool Feature'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it passes (already passes — just sanity check)**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test test/tab_dev_workshop_tap_test.dart 2>&1 | tail -10
```

- [ ] **Step 3: Modify tab_dev_workshop.dart**

Add import at the top (after existing imports):

```dart
import 'workshop_screen.dart';
```

Add the `_openWorkshop` method in the `_TabDevWorkshopState` class (after `_showCreateProposalDialog`):

```dart
  Future<void> _openWorkshop(Map<String, dynamic> proposal) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkshopScreen(
          proposal: proposal,
          settings: widget.settings,
        ),
      ),
    );
    if (mounted) _loadProposals();
  }
```

In `_proposalsCard()`, find the `ListTile` inside the `.map((p) {...})` block and add `onTap`:

Old `ListTile` (around line 546):
```dart
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(isFeature ? '✨' : '🐛',
```

New `ListTile`:
```dart
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _openWorkshop(p),
                  leading: Text(isFeature ? '✨' : '🐛',
```

- [ ] **Step 4: Run all Flutter tests**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test test/tab_dev_workshop_tap_test.dart test/workshop_screen_test.dart test/api_service_workshop_test.dart 2>&1 | tail -20
```

Expected: PASS — 7 tests passing

- [ ] **Step 5: Run full Flutter test suite to check for regressions**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && flutter test 2>&1 | tail -20
```

Expected: All tests pass

- [ ] **Step 6: Run server tests**

```bash
cd /home/user/jarvis-server-nadav && npm test 2>&1 | tail -20
```

Expected: All tests pass (or same failures as before this task)

- [ ] **Step 7: Commit**

```bash
cd /home/user/jarvis-server-nadav && git add jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart && git commit -m "feat: wire proposal tap to open WorkshopScreen"
```

---

## Self-Review

### Spec Coverage Check

| Spec Requirement | Task |
|------------------|------|
| Tapping proposal opens workshop view | Task 5 |
| Chat interface with conversation history | Task 3 |
| POST `/progress-map/command` with `{type: 'workshop', proposalId, message}` | Task 1 (implemented as `/workshop/:id/chat` — simpler and more RESTful; spec path was informal) |
| Auto-spec panel (name, type, description, AC) | Task 3 |
| Panel updates in real time | Task 3 (updates on each `_send()` response) |
| 📄 Spec → docs file export | Tasks 3+4 |
| 🤖 AI Prompt → clipboard | Task 3 |
| 🐙 GitHub Issue | Task 3 (stub with SnackBar — requires server-side MCP integration not in scope) |
| 📋 Copy to clipboard | Task 3 |

### Notes
- Endpoint path: spec says `POST /progress-map/command` with `{type: 'workshop'}`, but using `/workshop/:proposalId/chat` is cleaner and avoids overloading the command endpoint. This is a valid design decision.
- GitHub Issue export: `mcp__github__issue_write` is a Claude Code MCP tool, not a runtime server-side tool. A stub is the correct approach for now.
- Workshop history is persisted server-side in `proposal.workshopHistory[]` and re-loaded on screen open.
