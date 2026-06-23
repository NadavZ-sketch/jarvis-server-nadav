# Router Trainer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add מאמן Router — a UI in the Dev Workshop tab that surfaces messages that defaulted to `chat` intent and lets the user add keyword overrides for immediate hot-reload routing.

**Architecture:** Backend: (1) `loadRouterOverrides()` in `agents/router.js` reads `config/router-overrides.json` with a 5s TTL cache; overrides are checked before KEYWORDS in both `classifyIntent` and `classifyIntentDetailed`; messages that default to chat are logged as `router_chat_default` events in `smart_telemetry_events`. (2) 4 new REST endpoints manage the overrides file and surface the telemetry events. Flutter: `_recorderCard()` in `tab_dev_workshop.dart` is replaced by `_routerTrainerCard()` — an accordion UI with two inner tabs.

**Tech Stack:** Node.js/Express, Supabase (`smart_telemetry_events`), Flutter/Dart, `http` package, Jest/Supertest

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `agents/router.js` | Modify | Add `loadRouterOverrides()`, `invalidateOverridesCache()`, override check in both classify functions, export both new functions |
| `tests/unit/router.test.js` | Modify | Add `describe('router overrides', ...)` block with 5 tests |
| `server.js` | Modify | (a) Log `router_chat_default` event after routing; (b) add `readRouterOverrides` / `writeRouterOverrides` helpers + 4 endpoints |
| `config/router-overrides.json` | Create | Empty overrides file: `{ "overrides": [] }` |
| `tests/unit/routerTrainer.test.js` | Create | Supertest tests for the 4 endpoints |
| `jarvis_mobile/lib/services/api_service.dart` | Modify | Add 4 new methods: `fetchRouterTrainingEvents`, `fetchRouterKeywords`, `addRouterKeyword`, `deleteRouterKeyword` |
| `jarvis_mobile/test/api_service_router_trainer_test.dart` | Create | MockClient tests for the 4 methods |
| `jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart` | Modify | Replace recorder state + `_recorderCard()` + `_startRecording/_stopRecording/_saveTestCase` with router trainer state + `_routerTrainerCard()` + load/save methods |

---

## Task 1: `loadRouterOverrides()` + override check in `agents/router.js`

**Files:**
- Modify: `agents/router.js`
- Modify: `tests/unit/router.test.js`

- [ ] **Step 1: Write failing tests**

Add at the **bottom** of `tests/unit/router.test.js` (after the last `describe` block):

```javascript
describe('router overrides', () => {
    // Re-import with fresh module state for each test block
    let classifyIntentFn, classifyIntentDetailedFn, invalidateOverridesCacheFn;
    const fs = require('fs');

    beforeEach(() => {
        jest.resetModules();
        jest.clearAllMocks();
        // classifyIntent is already imported at the top — use the module-level cache invalidation
        const router = require('../../agents/router');
        classifyIntentFn = router.classifyIntent;
        classifyIntentDetailedFn = router.classifyIntentDetailed;
        invalidateOverridesCacheFn = router.invalidateOverridesCache;
        if (invalidateOverridesCacheFn) invalidateOverridesCacheFn();
    });

    afterEach(() => jest.restoreAllMocks());

    test('override substring match fires before KEYWORDS (Hebrew)', () => {
        jest.spyOn(fs, 'readFileSync').mockImplementation((p) => {
            if (String(p).includes('router-overrides.json')) {
                return JSON.stringify({ overrides: [{ keyword: 'חלב', intent: 'shopping' }] });
            }
            return '[]';
        });
        expect(classifyIntentFn('אני צריך חלב מהסופר')).toBe('shopping');
    });

    test('override match is case-insensitive (English keyword)', () => {
        jest.spyOn(fs, 'readFileSync').mockImplementation((p) => {
            if (String(p).includes('router-overrides.json')) {
                return JSON.stringify({ overrides: [{ keyword: 'buy Milk', intent: 'shopping' }] });
            }
            return '[]';
        });
        expect(classifyIntentFn('I need to buy milk today')).toBe('shopping');
    });

    test('KEYWORDS still work when overrides array is empty', () => {
        jest.spyOn(fs, 'readFileSync').mockImplementation((p) => {
            if (String(p).includes('router-overrides.json')) {
                return JSON.stringify({ overrides: [] });
            }
            return '[]';
        });
        expect(classifyIntentFn('מה מזג האוויר')).toBe('weather');
    });

    test('missing overrides file falls back to KEYWORDS (ENOENT swallowed)', () => {
        jest.spyOn(fs, 'readFileSync').mockImplementation((p) => {
            if (String(p).includes('router-overrides.json')) throw new Error('ENOENT');
            return '[]';
        });
        expect(classifyIntentFn('מה מזג האוויר')).toBe('weather');
    });

    test('classifyIntentDetailed with override returns non-ambiguous single-match', () => {
        jest.spyOn(fs, 'readFileSync').mockImplementation((p) => {
            if (String(p).includes('router-overrides.json')) {
                return JSON.stringify({ overrides: [{ keyword: 'תשלח לאמא', intent: 'messaging' }] });
            }
            return '[]';
        });
        const result = classifyIntentDetailedFn('תשלח לאמא שאני בדרך הביתה');
        expect(result.intent).toBe('messaging');
        expect(result.ambiguous).toBe(false);
        expect(result.matches).toContain('messaging');
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx jest tests/unit/router.test.js --verbose 2>&1 | tail -20
```

Expected: 5 failures in `router overrides` block — `invalidateOverridesCache is not a function` or `loadRouterOverrides` undefined.

- [ ] **Step 3: Implement `loadRouterOverrides` + override check in router.js**

In `agents/router.js`, after line 38 (`const REGISTRY_PATH = ...`), add:

```javascript
const OVERRIDES_PATH = path.join(__dirname, '..', 'config', 'router-overrides.json');

let _overridesCache = [], _overridesAt = 0;
function loadRouterOverrides() {
    if (Date.now() - _overridesAt < 5000) return _overridesCache;
    try {
        const parsed = JSON.parse(fs.readFileSync(OVERRIDES_PATH, 'utf8'));
        _overridesCache = Array.isArray(parsed.overrides) ? parsed.overrides : [];
    } catch {
        _overridesCache = [];
    }
    _overridesAt = Date.now();
    return _overridesCache;
}

function invalidateOverridesCache() { _overridesAt = 0; }
```

Replace the body of `classifyIntent` (lines 51–74) with:

```javascript
function classifyIntent(userMessage) {
    const msg = userMessage.toLowerCase();

    // User-defined substring overrides (hot-reload, checked first)
    const overrides = loadRouterOverrides();
    for (const { keyword, intent } of overrides) {
        if (keyword && intent && msg.includes(keyword.toLowerCase())) {
            console.log(`🧭 Router (override): "${intent}" ← "${userMessage.slice(0, 50)}"`);
            return intent;
        }
    }

    // Fast path: static keyword match
    for (const [intent, pattern] of Object.entries(KEYWORDS)) {
        if (pattern.test(userMessage)) {
            console.log(`🧭 Router (keyword): "${intent}" ← "${userMessage.slice(0, 50)}"`);
            return intent;
        }
    }

    // Dynamic custom agents (reads registry on every call — file is small)
    const customAgents = loadCustomRegistry();
    for (const agent of customAgents) {
        if (Array.isArray(agent.keywords) && agent.keywords.some(kw => msg.includes(kw.toLowerCase()))) {
            console.log(`🧭 Router (custom): "${agent.name}" ← "${userMessage.slice(0, 50)}"`);
            return agent.name;
        }
    }

    // Default
    console.log(`🧭 Router (default): "chat" ← "${userMessage.slice(0, 50)}"`);
    return 'chat';
}
```

Replace the body of `classifyIntentDetailed` (lines 81–108) with:

```javascript
function classifyIntentDetailed(userMessage) {
    const msg = userMessage.toLowerCase();

    // User-defined substring overrides — return immediately as non-ambiguous
    const overrides = loadRouterOverrides();
    for (const { keyword, intent } of overrides) {
        if (keyword && intent && msg.includes(keyword.toLowerCase())) {
            console.log(`🧭 Router (override): "${intent}" ← "${userMessage.slice(0, 50)}"`);
            return { intent, matches: [intent], ambiguous: false };
        }
    }

    const matches = [];
    for (const [intent, pattern] of Object.entries(KEYWORDS)) {
        if (pattern.test(userMessage)) matches.push(intent);
    }

    // Custom agents only considered when no built-in keyword matched.
    if (matches.length === 0) {
        const customAgents = loadCustomRegistry();
        for (const agent of customAgents) {
            if (Array.isArray(agent.keywords) && agent.keywords.some(kw => msg.includes(kw.toLowerCase()))) {
                matches.push(agent.name);
            }
        }
    }

    if (matches.length === 0) {
        return { intent: 'chat', matches: [], ambiguous: false };
    }
    if (matches.length === 1) {
        return { intent: matches[0], matches, ambiguous: false };
    }
    // Collision — multiple keyword intents matched the same message.
    console.log(`🧭 Router (ambiguous): [${matches.join(', ')}] ← "${userMessage.slice(0, 50)}"`);
    return { intent: matches[0], matches, ambiguous: true };
}
```

Replace the last line of `agents/router.js`:

```javascript
module.exports = { classifyIntent, classifyIntentDetailed, classifyIntentWithLLM, invalidateRouterCache, loadCustomRegistry, detectComplexTask, loadRouterOverrides, invalidateOverridesCache };
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
npx jest tests/unit/router.test.js --verbose 2>&1 | tail -20
```

Expected: All tests PASS (existing + 5 new override tests).

- [ ] **Step 5: Commit**

```bash
git add agents/router.js tests/unit/router.test.js
git commit -m "feat: add loadRouterOverrides() + override check in classifyIntent/classifyIntentDetailed"
```

---

## Task 2: Log `router_chat_default` events in `server.js`

**Files:**
- Modify: `server.js` (around line 958)

- [ ] **Step 1: Locate the routing block in server.js**

Find the block around line 935 in `server.js`. It looks like:

```javascript
const routed = classifyIntentDetailed(userMessage);
agentName = routed.intent;

if (routed.ambiguous) {
    // ...LLM disambiguation...
    feedbackStore.recordEvent(repos, {
        eventName: 'route_ambiguous',
        // ...
    }).catch(() => {});
}
// Removed: the former `else if (agentName === 'chat' && length > 12)`
```

- [ ] **Step 2: Add event logging after the ambiguous block**

Add these lines immediately after the closing `}` of the `if (routed.ambiguous)` block (right before the `// Removed:` comment or the next statement):

```javascript
            // Router Trainer: record messages that default to chat for user review
            if (agentName === 'chat' && routed.matches.length === 0) {
                feedbackStore.recordEvent(repos, {
                    eventName: 'router_chat_default',
                    value: 1,
                    metadata: { message: String(userMessage).slice(0, 500) },
                }).catch(() => {});
            }
```

- [ ] **Step 3: Run existing tests to confirm no regression**

```bash
npx jest tests/unit/workshop.test.js tests/unit/router.test.js --verbose 2>&1 | tail -20
```

Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add server.js
git commit -m "feat: log router_chat_default telemetry event when intent defaults to chat"
```

---

## Task 3: Router Trainer endpoints + `config/router-overrides.json`

**Files:**
- Create: `config/router-overrides.json`
- Modify: `server.js`
- Create: `tests/unit/routerTrainer.test.js`

- [ ] **Step 1: Create the overrides config file**

```bash
echo '{ "overrides": [] }' > /home/user/jarvis-server-nadav/config/router-overrides.json
```

- [ ] **Step 2: Write failing endpoint tests**

Create `tests/unit/routerTrainer.test.js`:

```javascript
'use strict';

jest.mock('openai', () => ({
  OpenAI: jest.fn().mockImplementation(() => ({
    audio: { transcriptions: { create: jest.fn().mockResolvedValue({ text: '' }) } },
  })),
  toFile: jest.fn().mockResolvedValue({}),
}));
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({
  createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn().mockResolvedValue({ messageId: 'm' }) }),
}));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: 'bW9jaw==' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({
  initSync: jest.fn().mockResolvedValue(undefined),
  fullSyncFromDb: jest.fn().mockResolvedValue(undefined),
  appendChatMessage: jest.fn().mockResolvedValue(undefined),
  syncAll: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../agents/models', () => ({
  callGemma4: jest.fn().mockResolvedValue('{}'),
  callGeminiVision: jest.fn(),
  callGeminiWithSearch: jest.fn(),
  callGemma4Stream: jest.fn(),
}));

const mockBacklog = { items: [], proposals: [], _nextId: 1 };
let mockOverrides = [];

jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  readFileSync: jest.fn((filePath) => {
    if (String(filePath).includes('backlog.json')) return JSON.stringify(mockBacklog);
    if (String(filePath).includes('router-overrides.json')) {
      return JSON.stringify({ overrides: mockOverrides });
    }
    return jest.requireActual('fs').readFileSync(filePath);
  }),
  writeFileSync: jest.fn((filePath, content) => {
    if (String(filePath).includes('router-overrides.json')) {
      mockOverrides = JSON.parse(content).overrides;
    }
  }),
  existsSync: jest.fn(() => true),
}));

const request = require('supertest');

let app;
beforeAll(() => {
  ({ app } = require('../../server'));
});

beforeEach(() => {
  mockOverrides = [];
  jest.clearAllMocks();
  // Re-mock readFileSync after clearAllMocks
  const fs = require('fs');
  fs.readFileSync.mockImplementation((filePath) => {
    if (String(filePath).includes('backlog.json')) return JSON.stringify(mockBacklog);
    if (String(filePath).includes('router-overrides.json')) return JSON.stringify({ overrides: mockOverrides });
    return jest.requireActual('fs').readFileSync(filePath);
  });
  fs.writeFileSync.mockImplementation((filePath, content) => {
    if (String(filePath).includes('router-overrides.json')) {
      mockOverrides = JSON.parse(content).overrides;
    }
  });
  // Reset overrides cache so endpoints read fresh
  const router = require('../../agents/router');
  if (router.invalidateOverridesCache) router.invalidateOverridesCache();
});

describe('GET /router/keywords', () => {
  it('returns empty overrides when file is empty', async () => {
    const res = await request(app)
      .get('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');
    expect(res.status).toBe(200);
    expect(res.body.overrides).toEqual([]);
  });

  it('returns existing overrides', async () => {
    mockOverrides = [{ keyword: 'חלב', intent: 'shopping' }];
    const res = await request(app)
      .get('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');
    expect(res.status).toBe(200);
    expect(res.body.overrides).toHaveLength(1);
    expect(res.body.overrides[0].keyword).toBe('חלב');
  });
});

describe('POST /router/keywords', () => {
  it('adds a new override', async () => {
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'תשלח לאמא', intent: 'messaging' });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.overrides).toHaveLength(1);
    expect(res.body.overrides[0]).toEqual({ keyword: 'תשלח לאמא', intent: 'messaging' });
  });

  it('does not add duplicate keyword+intent pair', async () => {
    mockOverrides = [{ keyword: 'חלב', intent: 'shopping' }];
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב', intent: 'shopping' });
    expect(res.status).toBe(200);
    expect(res.body.overrides).toHaveLength(1);
  });

  it('returns 400 when keyword is missing', async () => {
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ intent: 'shopping' });
    expect(res.status).toBe(400);
  });

  it('returns 400 when intent is missing', async () => {
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב' });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /router/keywords', () => {
  it('removes the matching override', async () => {
    mockOverrides = [
      { keyword: 'חלב', intent: 'shopping' },
      { keyword: 'תשלח לאמא', intent: 'messaging' },
    ];
    const res = await request(app)
      .delete('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב', intent: 'shopping' });
    expect(res.status).toBe(200);
    expect(res.body.overrides).toHaveLength(1);
    expect(res.body.overrides[0].keyword).toBe('תשלח לאמא');
  });

  it('returns 400 when keyword or intent missing', async () => {
    const res = await request(app)
      .delete('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב' });
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
npx jest tests/unit/routerTrainer.test.js --verbose 2>&1 | tail -25
```

Expected: All tests fail with 404 (endpoints don't exist yet).

- [ ] **Step 4: Add 4 Router Trainer endpoints to server.js**

Update the import on line 46 in server.js to include `invalidateOverridesCache`:

```javascript
const { classifyIntent, classifyIntentDetailed, classifyIntentWithLLM, loadCustomRegistry, invalidateOverridesCache } = require('./agents/router');
```

Then find a good insertion point (e.g., after the `/dashboard/smart-telemetry` DELETE endpoint around line 1910). Add:

```javascript
// ── Router Trainer ────────────────────────────────────────────────────────────

const ROUTER_OVERRIDES_PATH = path.join(__dirname, 'config', 'router-overrides.json');

function readRouterOverrides() {
    try {
        const parsed = JSON.parse(fs.readFileSync(ROUTER_OVERRIDES_PATH, 'utf8'));
        return Array.isArray(parsed.overrides) ? parsed.overrides : [];
    } catch {
        return [];
    }
}

function writeRouterOverrides(overrides) {
    fs.writeFileSync(ROUTER_OVERRIDES_PATH, JSON.stringify({ overrides }, null, 2), 'utf8');
    invalidateOverridesCache();
}

app.get('/router/training-events', _rl(30), async (req, res) => {
    try {
        const limit = Math.min(Number(req.query.limit) || 50, 100);
        const { data, error } = await supabase
            .from('smart_telemetry_events')
            .select('id, metadata, created_at')
            .eq('event_name', 'router_chat_default')
            .order('created_at', { ascending: false })
            .limit(limit);
        if (error) throw error;
        const events = (data || []).map(row => ({
            id: row.id,
            message: (row.metadata && row.metadata.message) ? row.metadata.message : '',
            created_at: row.created_at,
        }));
        res.json({ events });
    } catch (err) {
        console.error('GET /router/training-events error:', err.message);
        res.status(500).json({ error: 'failed to fetch training events' });
    }
});

app.get('/router/keywords', _rl(30), (req, res) => {
    try {
        const overrides = readRouterOverrides();
        res.json({ overrides });
    } catch (err) {
        res.status(500).json({ error: 'failed to read overrides' });
    }
});

app.post('/router/keywords', _rl(20), (req, res) => {
    try {
        const { keyword, intent } = req.body || {};
        if (!keyword || typeof keyword !== 'string' || !intent || typeof intent !== 'string') {
            return res.status(400).json({ error: 'keyword and intent are required strings' });
        }
        const kw = keyword.trim();
        if (!kw) return res.status(400).json({ error: 'keyword must not be empty' });
        const overrides = readRouterOverrides();
        const deduped = overrides.filter(o => !(o.keyword === kw && o.intent === intent));
        deduped.push({ keyword: kw, intent });
        writeRouterOverrides(deduped);
        res.json({ ok: true, overrides: deduped });
    } catch (err) {
        console.error('POST /router/keywords error:', err.message);
        res.status(500).json({ error: 'failed to save override' });
    }
});

app.delete('/router/keywords', _rl(20), (req, res) => {
    try {
        const { keyword, intent } = req.body || {};
        if (!keyword || !intent) {
            return res.status(400).json({ error: 'keyword and intent are required' });
        }
        const overrides = readRouterOverrides();
        const updated = overrides.filter(o => !(o.keyword === keyword && o.intent === intent));
        writeRouterOverrides(updated);
        res.json({ ok: true, overrides: updated });
    } catch (err) {
        console.error('DELETE /router/keywords error:', err.message);
        res.status(500).json({ error: 'failed to delete override' });
    }
});
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
npx jest tests/unit/routerTrainer.test.js --verbose 2>&1 | tail -25
```

Expected: All tests PASS.

- [ ] **Step 6: Run full test suite to check for regressions**

```bash
npm test 2>&1 | tail -20
```

Expected: All tests pass (or same failures as before this task).

- [ ] **Step 7: Commit**

```bash
git add config/router-overrides.json server.js tests/unit/routerTrainer.test.js
git commit -m "feat: add Router Trainer endpoints (GET/POST/DELETE /router/keywords, GET /router/training-events)"
```

---

## Task 4: ApiService Flutter — 4 new methods

**Files:**
- Modify: `jarvis_mobile/lib/services/api_service.dart`
- Create: `jarvis_mobile/test/api_service_router_trainer_test.dart`

- [ ] **Step 1: Write failing Flutter tests**

Create `jarvis_mobile/test/api_service_router_trainer_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd jarvis_mobile && flutter test test/api_service_router_trainer_test.dart 2>&1 | tail -15
```

Expected: Compile errors — methods don't exist yet.

- [ ] **Step 3: Add the 4 methods to `api_service.dart`**

Find the end of the `generateChangelog` method (around line 1196 in `api_service.dart`). After the closing `}` of that method, add:

```dart
  Future<List<Map<String, dynamic>>> fetchRouterTrainingEvents() async {
    try {
      final res = await _client
          .get(_uri('/router/training-events'), headers: _headers())
          .timeout(_timeout);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
      final events = data['events'];
      if (events is List) {
        return events.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchRouterKeywords() async {
    try {
      final res = await _client
          .get(_uri('/router/keywords'), headers: _headers())
          .timeout(_timeout);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
      final overrides = data['overrides'];
      if (overrides is List) {
        return overrides.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> addRouterKeyword({
    required String keyword,
    required String intent,
  }) async {
    try {
      final res = await _client
          .post(
            _uri('/router/keywords'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({'keyword': keyword, 'intent': intent}),
          )
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteRouterKeyword({
    required String keyword,
    required String intent,
  }) async {
    try {
      final request = http.Request('DELETE', _uri('/router/keywords'));
      request.headers.addAll(_headers({'Content-Type': 'application/json'}));
      request.body = jsonEncode({'keyword': keyword, 'intent': intent});
      final streamedRes = await _client.send(request).timeout(_timeout);
      return streamedRes.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd jarvis_mobile && flutter test test/api_service_router_trainer_test.dart 2>&1 | tail -15
```

Expected: All 8 tests PASS.

- [ ] **Step 5: Run all Flutter tests to check for regressions**

```bash
cd jarvis_mobile && flutter test 2>&1 | tail -15
```

Expected: Same pass/fail count as before.

- [ ] **Step 6: Commit**

```bash
cd /home/user/jarvis-server-nadav
git add jarvis_mobile/lib/services/api_service.dart jarvis_mobile/test/api_service_router_trainer_test.dart
git commit -m "feat: add fetchRouterTrainingEvents, fetchRouterKeywords, addRouterKeyword, deleteRouterKeyword to ApiService"
```

---

## Task 5: Flutter UI — Replace `_recorderCard()` with `_routerTrainerCard()`

**Files:**
- Modify: `jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart`

- [ ] **Step 1: Replace state fields for the recorder**

In `_TabDevWorkshopState`, find the recorder state block (lines 25–28):

```dart
  // Section 2 — Test Recorder
  bool _recording = false;
  List<dynamic> _recordedTurns = [];
  final TextEditingController _saveNameCtrl = TextEditingController();
```

Replace it with:

```dart
  // Section 2 — Router Trainer
  List<Map<String, dynamic>> _trainingEvents = [];
  List<Map<String, dynamic>> _routerKeywords = [];
  bool _routerLoading = false;
  int? _openRowIndex;
  final Set<String> _handledEventIds = {};
  String? _selectedIntent;
  final TextEditingController _kwCtrl = TextEditingController();
  int _routerTabIndex = 0;
```

- [ ] **Step 2: Update `initState` to load router data**

In `initState`, replace the call to `_loadPrompts()` and `_loadProposals()` block:

```dart
  @override
  void initState() {
    super.initState();
    _loadPrompts();
    _loadRouterData();
    _loadProposals();
  }
```

- [ ] **Step 3: Update `dispose` to dispose the new controller**

Replace `_saveNameCtrl.dispose();` with `_kwCtrl.dispose();`.

- [ ] **Step 4: Remove the recorder methods, add router methods**

Remove these methods entirely (they are no longer needed):
- `_startRecording()`
- `_stopRecording()`
- `_saveTestCase()`

Add the router trainer load method after `_loadPrompts()`:

```dart
  Future<void> _loadRouterData() async {
    if (!mounted) return;
    setState(() => _routerLoading = true);
    final results = await Future.wait([
      _api.fetchRouterTrainingEvents().catchError((_) => <Map<String, dynamic>>[]),
      _api.fetchRouterKeywords().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _trainingEvents = results[0] as List<Map<String, dynamic>>;
      _routerKeywords = results[1] as List<Map<String, dynamic>>;
      _routerLoading = false;
    });
  }

  Future<void> _saveRouterKeyword(int rowIndex) async {
    final kw = _kwCtrl.text.trim();
    final intent = _selectedIntent;
    if (kw.isEmpty || intent == null) return;
    final event = _trainingEvents[rowIndex];
    final ok = await _api
        .addRouterKeyword(keyword: kw, intent: intent)
        .catchError((_) => false);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _handledEventIds.add(event['id']?.toString() ?? '');
        _routerKeywords = [
          ..._routerKeywords,
          {'keyword': kw, 'intent': intent},
        ];
        _openRowIndex = null;
        _selectedIntent = null;
        _kwCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ "$kw" ← $intent — פעיל מיד',
              style: const TextStyle(fontFamily: 'Heebo')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteRouterKeyword(Map<String, dynamic> kw) async {
    final ok = await _api
        .deleteRouterKeyword(
          keyword: kw['keyword'] as String,
          intent: kw['intent'] as String,
        )
        .catchError((_) => false);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _routerKeywords = _routerKeywords
            .where((k) => !(k['keyword'] == kw['keyword'] && k['intent'] == kw['intent']))
            .toList();
      });
    }
  }
```

- [ ] **Step 5: Update `build()` to call `_routerTrainerCard()`**

In the `build()` method, replace `_recorderCard()` with `_routerTrainerCard()`:

```dart
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _promptLibraryCard(),
        const SizedBox(height: 16),
        _routerTrainerCard(),      // was _recorderCard()
        const SizedBox(height: 16),
        _changelogCard(),
        const SizedBox(height: 16),
        _proposalsCard(),
        const SizedBox(height: 32),
      ],
    );
```

- [ ] **Step 6: Replace `_recorderCard()` with `_routerTrainerCard()`**

Remove the `_recorderCard()` method entirely and add the following `_routerTrainerCard()` and its helpers in the same location:

```dart
  static const _intentChips = [
    ('📅', 'reminder'), ('✅', 'task'),       ('📈', 'stocks'),
    ('🛒', 'shopping'), ('💬', 'messaging'),  ('⚽', 'sports'),
    ('🌤', 'weather'),  ('📰', 'news'),       ('🌍', 'translate'),
    ('🎵', 'music'),    ('📝', 'notes'),      ('🧠', 'memory'),
  ];

  Widget _routerTrainerCard() {
    final unhandled = _trainingEvents
        .where((e) => !_handledEventIds.contains(e['id']?.toString() ?? ''))
        .toList();
    final unhandledCount = unhandled.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(children: [
              const Expanded(
                child: Text('🧠 מאמן Router',
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
              ),
              if (unhandledCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$unhandledCount פתוחות',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Heebo'),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadRouterData,
                tooltip: 'רענן',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ]),
            const SizedBox(height: 8),
            // Inner tab row
            Row(children: [
              _routerTab('הודעות', 0),
              const SizedBox(width: 8),
              _routerTab('Keywords שלי', 1),
            ]),
            const Divider(height: 16),
            // Content
            if (_routerLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else if (_routerTabIndex == 0)
              _messagesTabContent(unhandled)
            else
              _keywordsTabContent(),
          ],
        ),
      ),
    );
  }

  Widget _routerTab(String label, int index) {
    final active = _routerTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _routerTabIndex = index;
        _openRowIndex = null;
        _selectedIntent = null;
        _kwCtrl.clear();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _messagesTabContent(List<Map<String, dynamic>> unhandled) {
    if (unhandled.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('אין הודעות לטיפול',
            style: TextStyle(color: Colors.grey, fontFamily: 'Heebo', fontSize: 13),
            textAlign: TextAlign.center),
      );
    }
    return Column(
      children: List.generate(unhandled.length, (i) {
        final event = unhandled[i];
        final isOpen = _openRowIndex == i;
        final msg = event['message'] as String? ?? '';
        return _messageRow(event: event, index: i, isOpen: isOpen, msg: msg);
      }),
    );
  }

  Widget _messageRow({
    required Map<String, dynamic> event,
    required int index,
    required bool isOpen,
    required String msg,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (_openRowIndex == index) {
                _openRowIndex = null;
                _selectedIntent = null;
                _kwCtrl.clear();
              } else {
                _openRowIndex = index;
                _selectedIntent = null;
                // Pre-fill keyword from first 3 words
                final words = msg.split(' ').take(3).join(' ');
                _kwCtrl.text = words;
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOpen
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    color: isOpen ? null : Colors.grey.shade600,
                  ),
                  maxLines: isOpen ? null : 1,
                  overflow: isOpen ? null : TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
        if (isOpen) _expandedPanel(index),
        if (index < _trainingEvents.length - 1)
          const Divider(height: 1),
      ],
    );
  }

  Widget _expandedPanel(int rowIndex) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Intent chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _intentChips.map(((emoji, name)) {
              final selected = _selectedIntent == name;
              return GestureDetector(
                onTap: () => setState(() => _selectedIntent = name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                    ),
                    color: selected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                        : null,
                  ),
                  child: Text(
                    '$emoji $name',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Heebo',
                      color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade600,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Keyword input + save
          Row(children: [
            Expanded(
              child: TextField(
                controller: _kwCtrl,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'keyword לזיהוי...',
                  hintStyle: TextStyle(fontFamily: 'Heebo', fontSize: 13),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_selectedIntent != null && _kwCtrl.text.trim().isNotEmpty)
                  ? () => _saveRouterKeyword(rowIndex)
                  : null,
              child: const Text('שמור', style: TextStyle(fontFamily: 'Heebo')),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _keywordsTabContent() {
    if (_routerKeywords.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('עדיין לא הוספת keywords',
            style: TextStyle(color: Colors.grey, fontFamily: 'Heebo', fontSize: 13),
            textAlign: TextAlign.center),
      );
    }
    return Column(
      children: _routerKeywords.map((kw) {
        final keyword = kw['keyword'] as String? ?? '';
        final intent = kw['intent'] as String? ?? '';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(intent,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Heebo',
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
          ),
          title: Text(keyword,
              style: const TextStyle(fontFamily: 'Heebo', fontSize: 13)),
          subtitle: const Text('←', style: TextStyle(color: Colors.grey)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
            onPressed: () => _deleteRouterKeyword(kw),
            tooltip: 'מחק',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        );
      }).toList(),
    );
  }
```

- [ ] **Step 7: Run Flutter analyze to verify no compile errors**

```bash
cd jarvis_mobile && flutter analyze 2>&1 | grep -E "error|warning" | head -20
```

Expected: No errors. Warnings about unused elements are acceptable.

- [ ] **Step 8: Run Flutter tests**

```bash
cd jarvis_mobile && flutter test 2>&1 | tail -15
```

Expected: Same pass count as before (no new failures).

- [ ] **Step 9: Commit**

```bash
cd /home/user/jarvis-server-nadav
git add jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart
git commit -m "feat: replace recorder card with Router Trainer accordion UI in Dev Workshop tab"
```

---

## Self-Review Checklist

### Spec Coverage

| Requirement | Task |
|-------------|------|
| Overrides checked before KEYWORDS | Task 1 — `classifyIntent` + `classifyIntentDetailed` |
| Substring match, case-insensitive | Task 1 — `msg.includes(keyword.toLowerCase())` |
| Hot-reload: 5s TTL cache | Task 1 — `_overridesAt` timestamp check |
| `router_chat_default` events logged | Task 2 — server.js after routing |
| GET /router/training-events | Task 3 |
| GET /router/keywords | Task 3 |
| POST /router/keywords (dedup) | Task 3 |
| DELETE /router/keywords | Task 3 |
| `config/router-overrides.json` auto-created empty | Task 3 — created in step 1 |
| `writeRouterOverrides` calls `invalidateOverridesCache()` | Task 3 |
| 4 Flutter API methods | Task 4 |
| Flutter: accordion messages tab | Task 5 |
| Flutter: keywords tab with delete | Task 5 |
| Flutter: one row open at a time | Task 5 — `_openRowIndex` state |
| Flutter: keyword pre-filled from first 3 words | Task 5 — `_expandedPanel` |
| Flutter: save button disabled until both inputs valid | Task 5 — `onPressed` conditional |
| Flutter: toast on save | Task 5 — `ScaffoldMessenger.showSnackBar` |
| Flutter: count badge decrements after save | Task 5 — `_handledEventIds` tracks handled rows |
| Flutter: state replacing recorder state | Task 5 — Step 1 |

### Placeholder Scan
✅ No TBD, TODO, or vague instructions.

### Type Consistency
- `loadRouterOverrides()` returns `Array<{keyword: string, intent: string}>` — used correctly in both classify functions and endpoints.
- `readRouterOverrides()` and `writeRouterOverrides()` in server.js use the same shape.
- `invalidateOverridesCache()` called after every write — ✅ consistent.
- Flutter `_trainingEvents`: `List<Map<String, dynamic>>` — matches `fetchRouterTrainingEvents` return type ✅.
- Flutter `_routerKeywords`: `List<Map<String, dynamic>>` — matches `fetchRouterKeywords` return type ✅.
- `_intentChips` uses Dart record syntax `(String, String)` — matches `(emoji, name)` destructuring ✅.
