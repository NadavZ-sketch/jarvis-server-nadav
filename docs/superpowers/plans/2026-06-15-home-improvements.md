# Home Screen Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement three home-screen improvements: compact collapsible tasks card, AI-powered smart reminders zone, and environment card with news/sports/tech tabs.

**Architecture:** Backend tasks (1-3) extend `services/newsSource.js` and `server.js` with new helpers and endpoints. Flutter tasks (4-8) add state to `HomeController`, refactor three card widgets, and update one dialog. All tasks are independent of each other once their dependencies are done (Task 4 depends on Task 3; Task 5 depends on Task 4; Task 7 depends on Task 2).

**Tech Stack:** Node.js/Express (server), Dart/Flutter (mobile), Jest (JS tests), SharedPreferences (Flutter cache), `repos.chat`/`repos.tasks` (Supabase data access), `callGemma4` (LLM), Google News RSS (sports/tech headlines)

---

## Task 1: `getTopicHeadlines` in `services/newsSource.js`

**Files:**
- Modify: `services/newsSource.js`
- Modify: `tests/unit/newsSource.test.js`

### Context

`services/newsSource.js` already exports `getNewsSummary()` which fetches from `https://news.google.com/rss?hl=he&gl=IL&ceid=IL:he`. The existing `parseHeadlines(xml, limit)` helper parses RSS XML into a string array. The in-process cache uses `_cacheGet`/`_cacheSet`.

---

- [ ] **Step 1: Write the failing tests**

Add to the bottom of `tests/unit/newsSource.test.js`:

```javascript
describe('getTopicHeadlines', () => {
  it('fetches topic-specific feed and returns headlines', async () => {
    axios.get.mockResolvedValue({ data: SAMPLE_RSS });
    const mod = freshModule();
    const r = await mod.getTopicHeadlines('ספורט ישראל');
    expect(r).not.toBeNull();
    expect(r.headlines.length).toBeGreaterThan(0);
    expect(Array.isArray(r.headlines)).toBe(true);
  });

  it('uses correct search URL with encoded topic', async () => {
    axios.get.mockResolvedValue({ data: SAMPLE_RSS });
    const mod = freshModule();
    await mod.getTopicHeadlines('טכנולוגיה הייטק');
    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('%D7%98%D7%9B%D7%A0%D7%95%D7%9C%D7%95%D7%92%D7%99%D7%94'),
      expect.any(Object)
    );
  });

  it('returns null on network failure', async () => {
    axios.get.mockRejectedValue(new Error('timeout'));
    const mod = freshModule();
    const r = await mod.getTopicHeadlines('ספורט');
    expect(r).toBeNull();
  });

  it('respects custom maxItems', async () => {
    axios.get.mockResolvedValue({ data: SAMPLE_RSS });
    const mod = freshModule();
    const r = await mod.getTopicHeadlines('חדשות', 2);
    expect(r.headlines.length).toBeLessThanOrEqual(2);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx jest tests/unit/newsSource.test.js -t 'getTopicHeadlines' --no-coverage
```

Expected: FAIL — `getTopicHeadlines is not a function`

- [ ] **Step 3: Implement `getTopicHeadlines`**

Add this function to `services/newsSource.js` before `module.exports`, right after `getNewsSummary`:

```javascript
const TOPIC_RSS_BASE = 'https://news.google.com/rss/search';

/**
 * Fetches headlines for a specific topic using Google News RSS search.
 * @param {string} topic - Hebrew search string (e.g., 'ספורט ישראל')
 * @param {number} maxItems - max headlines to return (default 4)
 * @returns {{ headlines: string[] } | null}
 */
async function getTopicHeadlines(topic, maxItems = 4) {
    const cacheKey = `news:topic:${topic}`;
    const cached = _cacheGet(cacheKey);
    if (cached !== undefined) return cached;

    try {
        const url = `${TOPIC_RSS_BASE}?q=${encodeURIComponent(topic)}&hl=he&gl=IL&ceid=IL:he`;
        const res = await axios.get(url, {
            timeout: HTTP_TIMEOUT,
            headers: { 'User-Agent': 'Mozilla/5.0 (Jarvis/1.0)' },
            responseType: 'text',
        });
        const headlines = parseHeadlines(res.data, maxItems);
        if (headlines.length === 0) { _cacheSet(cacheKey, null, TTL_NEWS); return null; }
        const data = { headlines };
        _cacheSet(cacheKey, data, TTL_NEWS);
        return data;
    } catch (err) {
        console.warn(`⚠️ newsSource.getTopicHeadlines(${topic}) failed:`, err.message);
        return null;
    }
}
```

Update `module.exports` at the bottom:

```javascript
module.exports = { getNewsSummary, parseHeadlines, getTopicHeadlines };
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
npx jest tests/unit/newsSource.test.js --no-coverage
```

Expected: all tests PASS (existing + new)

- [ ] **Step 5: Commit**

```bash
git add services/newsSource.js tests/unit/newsSource.test.js
git commit -m "feat: add getTopicHeadlines to newsSource for sports/tech RSS feeds"
```

---

## Task 2: Extend `/dashboard-context` with sports and tech widgets

**Files:**
- Modify: `server.js` (lines ~1895–1946: the `/dashboard-context` handler)
- Modify: `tests/integration/dashboardContext.test.js`

### Context

The `/dashboard-context` handler at line 1878 of `server.js` runs a `Promise.all` over tasks, reminders, weather, and news. It then pushes widgets to an array. `getTopicHeadlines` is now exported from `services/newsSource.js`. The mock in `tests/integration/dashboardContext.test.js` stubs `../../services/newsSource` with `{ getNewsSummary: jest.fn()... }`.

---

- [ ] **Step 1: Write the failing test**

Add to `tests/integration/dashboardContext.test.js`, inside the `describe('GET /dashboard-context')` block:

```javascript
it('includes sports and tech widgets when sources return data', async () => {
    const { getNewsSummary, getTopicHeadlines } = require('../../services/newsSource');
    getNewsSummary.mockResolvedValue({ headlines: ['כותרת חדשות'], summary: '• כותרת חדשות' });
    getTopicHeadlines
        .mockResolvedValueOnce({ headlines: ['מכבי זכתה'] })   // sports
        .mockResolvedValueOnce({ headlines: ['אפל הכריזה'] }); // tech
    const res = await request(app).get('/dashboard-context');
    expect(res.status).toBe(200);
    const sports = res.body.widgets.find(w => w.type === 'sports');
    const tech   = res.body.widgets.find(w => w.type === 'tech');
    expect(sports).toBeDefined();
    expect(sports.data.headlines).toContain('מכבי זכתה');
    expect(tech).toBeDefined();
    expect(tech.data.headlines).toContain('אפל הכריזה');
});

it('omits sports/tech widgets when sources fail', async () => {
    const { getTopicHeadlines } = require('../../services/newsSource');
    getTopicHeadlines.mockResolvedValue(null);
    const res = await request(app).get('/dashboard-context');
    expect(res.status).toBe(200);
    const sports = res.body.widgets.find(w => w.type === 'sports');
    const tech   = res.body.widgets.find(w => w.type === 'tech');
    expect(sports).toBeUndefined();
    expect(tech).toBeUndefined();
});
```

Also update the existing mock at the top of the integration test file — add `getTopicHeadlines` to the `newsSource` mock:

```javascript
jest.mock('../../services/newsSource', () => ({
    getNewsSummary: jest.fn().mockResolvedValue({ summary: 'חדשות: ישראל בחדשות.', headlines: ['חדשות'] }),
    getTopicHeadlines: jest.fn().mockResolvedValue(null),
}));
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx jest tests/integration/dashboardContext.test.js --no-coverage
```

Expected: new tests FAIL — sports/tech widgets not present yet

- [ ] **Step 3: Extend `/dashboard-context` in `server.js`**

Find the line (around 1895):
```javascript
const [tasks, reminders, weatherData, newsData] = await Promise.all([
```

Replace the entire `Promise.all` call (through the closing `]);`) with:

```javascript
const [tasks, reminders, weatherData, newsData, sportsData, techData] = await Promise.all([
    repos.tasks.topByPriority(6),
    repos.reminders.dueBefore(threeHoursLater, 6),
    (async () => {
        const city = req.query.city || settings.userProfile?.city || '';
        const cacheKey = `dashboard:weather:${city || 'default'}`;
        const cached = cacheGet(cacheKey);
        if (cached) return cached;
        try {
            const { getWeatherSummary } = require('./services/weatherSource');
            const data = await getWeatherSummary(city);
            if (data) cacheSet(cacheKey, data, TTL_DASHBOARD_WEATHER);
            return data;
        } catch { return null; }
    })(),
    (async () => {
        const cacheKey = 'dashboard:news';
        const cached = cacheGet(cacheKey);
        if (cached) return cached;
        try {
            const { getNewsSummary } = require('./services/newsSource');
            const data = await getNewsSummary();
            if (data) cacheSet(cacheKey, data, TTL_DASHBOARD_NEWS);
            return data;
        } catch { return null; }
    })(),
    (async () => {
        const cacheKey = 'dashboard:sports';
        const cached = cacheGet(cacheKey);
        if (cached) return cached;
        try {
            const { getTopicHeadlines } = require('./services/newsSource');
            const data = await getTopicHeadlines('ספורט ישראל');
            if (data) cacheSet(cacheKey, data, TTL_DASHBOARD_NEWS);
            return data;
        } catch { return null; }
    })(),
    (async () => {
        const cacheKey = 'dashboard:tech';
        const cached = cacheGet(cacheKey);
        if (cached) return cached;
        try {
            const { getTopicHeadlines } = require('./services/newsSource');
            const data = await getTopicHeadlines('טכנולוגיה הייטק');
            if (data) cacheSet(cacheKey, data, TTL_DASHBOARD_NEWS);
            return data;
        } catch { return null; }
    })(),
]);
```

Then find the two lines that push weather/news widgets (around line 1945):
```javascript
if (weatherData) widgets.push({ type: 'weather', data: weatherData });
if (newsData)    widgets.push({ type: 'news',    data: newsData });
```

Add two more lines directly after them:
```javascript
if (sportsData) widgets.push({ type: 'sports', data: sportsData });
if (techData)   widgets.push({ type: 'tech',   data: techData });
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
npx jest tests/integration/dashboardContext.test.js --no-coverage
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add server.js tests/integration/dashboardContext.test.js
git commit -m "feat: add sports and tech topic widgets to /dashboard-context"
```

---

## Task 3: `GET /smart-suggestions` endpoint

**Files:**
- Modify: `server.js`
- Create: `tests/unit/smartSuggestions.test.js`

### Context

`repos.chat.recentForSearch(30)` returns `{ role, text, created_at }[]` (most-recent first). `repos.tasks.listOpenByCreated()` returns `{ id, content, done, due_date, priority, created_at }[]`. `callGemma4(prompt, useLocal, maxTokens)` calls the LLM and returns a string. `cacheGet`/`cacheSet`/`cacheInvalidate` manage in-process TTL cache. `_rl(10)` rate-limits to 10 req/min. The LLM response must be parsed as a JSON array; use `JSON.parse` inside a try/catch since `extractJSON` only handles objects, not arrays.

---

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/smartSuggestions.test.js`:

```javascript
'use strict';

jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({ createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn() }) }));
jest.mock('openai', () => ({ OpenAI: jest.fn().mockImplementation(() => ({ audio: { transcriptions: { create: jest.fn() } } })), toFile: jest.fn() }));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: '' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({ initSync: jest.fn(), fullSyncFromDb: jest.fn(), appendChatMessage: jest.fn(), syncAll: jest.fn() }));
jest.mock('../../services/weatherSource', () => ({ getWeatherSummary: jest.fn().mockResolvedValue(null) }));
jest.mock('../../services/newsSource', () => ({ getNewsSummary: jest.fn().mockResolvedValue(null), getTopicHeadlines: jest.fn().mockResolvedValue(null) }));
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGemma4Stream: jest.fn(),
}));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { callGemma4 } = require('../../agents/models');
const { app } = require('../../server');

function makeChain(data = []) {
    const chain = {
        select: jest.fn().mockReturnThis(),
        eq: jest.fn().mockReturnThis(),
        order: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
        then: (resolve) => resolve({ data, error: null }),
    };
    return chain;
}

let supabaseClient;
beforeEach(() => {
    supabaseClient = createClient.mock.results[0]?.value || { from: jest.fn() };
    supabaseClient.from = jest.fn().mockImplementation(() => makeChain([]));
    jest.clearAllMocks();
    supabaseClient.from = jest.fn().mockImplementation(() => makeChain([]));
});

describe('GET /smart-suggestions', () => {
    it('returns 200 with suggestions array', async () => {
        callGemma4.mockResolvedValue(
            '[{"text":"לחזור לאביב לגבי ההצעה","sourceType":"chat","sourceLabel":"לפני 2 ימים"}]'
        );
        const res = await request(app).get('/smart-suggestions');
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('suggestions');
        expect(Array.isArray(res.body.suggestions)).toBe(true);
    });

    it('returns empty array when LLM returns invalid JSON', async () => {
        callGemma4.mockResolvedValue('לא הצלחתי לנתח');
        const res = await request(app).get('/smart-suggestions');
        expect(res.status).toBe(200);
        expect(res.body.suggestions).toEqual([]);
    });

    it('returns empty array when LLM call fails', async () => {
        callGemma4.mockRejectedValue(new Error('LLM down'));
        const res = await request(app).get('/smart-suggestions');
        expect(res.status).toBe(200);
        expect(res.body.suggestions).toEqual([]);
    });

    it('assigns an id to each suggestion', async () => {
        callGemma4.mockResolvedValue(
            '[{"text":"משימה לדוגמה","sourceType":"task","sourceLabel":"פגת תוקף"}]'
        );
        const res = await request(app).get('/smart-suggestions');
        expect(res.body.suggestions[0]).toHaveProperty('id');
        expect(typeof res.body.suggestions[0].id).toBe('string');
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx jest tests/unit/smartSuggestions.test.js --no-coverage
```

Expected: FAIL — `GET /smart-suggestions` returns 404

- [ ] **Step 3: Implement `GET /smart-suggestions` in `server.js`**

Add this handler somewhere after the `/dashboard-context` route (around line 1959). Add it as a new block:

```javascript
// ─── Smart Suggestions ────────────────────────────────────────────────────────

const TTL_SMART_SUGGESTIONS = 60 * 60 * 1000; // 1 h

app.get('/smart-suggestions', _rl(10), async (req, res) => {
    const cacheKey = 'smart-suggestions';
    const cached = cacheGet(cacheKey);
    if (cached !== undefined) return res.json(cached);

    try {
        const [chatRows, taskRows] = await Promise.all([
            repos.chat.recentForSearch(30),
            repos.tasks.listOpenByCreated(),
        ]);

        // Filter to tasks created more than 3 days ago (stale)
        const cutoff = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();
        const staleTasks = taskRows
            .filter(t => !t.done && t.created_at < cutoff)
            .slice(0, 10);

        // Build compact chat excerpt (user messages only, last 20)
        const chatExcerpts = chatRows
            .filter(r => r.role === 'user')
            .slice(0, 20)
            .map(r => `- ${(r.text || '').substring(0, 120)}`)
            .join('\n');

        const staleTaskLines = staleTasks
            .map(t => `- ${t.content}`)
            .join('\n');

        if (!chatExcerpts && !staleTaskLines) {
            const empty = { suggestions: [] };
            cacheSet(cacheKey, empty, TTL_SMART_SUGGESTIONS);
            return res.json(empty);
        }

        const prompt =
            'להלן הודעות אחרונות של המשתמש עם ג\'רוויס:\n' +
            (chatExcerpts || 'אין היסטוריה') +
            '\n\nמשימות ישנות שלא טופלו:\n' +
            (staleTaskLines || 'אין') +
            '\n\nזהה עד 5 פריטים שהמשתמש אמר שצריך לטפל בהם, תכנן לעתיד, ' +
            'או משימות ישנות שנשכחו. ' +
            'החזר JSON בלבד — מערך ללא הסברים:\n' +
            '[{"text":"...","sourceType":"chat|task|plan","sourceLabel":"..."}]';

        const raw = await callGemma4(prompt, false, 600);

        let suggestions = [];
        try {
            // Find JSON array in the response
            const match = raw.match(/\[[\s\S]*\]/);
            if (match) {
                const parsed = JSON.parse(match[0]);
                if (Array.isArray(parsed)) {
                    suggestions = parsed
                        .filter(s => s && typeof s.text === 'string' && s.text.trim())
                        .slice(0, 5)
                        .map((s, i) => ({
                            id: `sug-${Date.now()}-${i}`,
                            text: s.text.trim(),
                            sourceType: s.sourceType || 'chat',
                            sourceLabel: s.sourceLabel || '',
                        }));
                }
            }
        } catch (_) { /* malformed JSON — return empty */ }

        const result = { suggestions };
        cacheSet(cacheKey, result, TTL_SMART_SUGGESTIONS);
        res.json(result);
    } catch (err) {
        console.error('GET /smart-suggestions error:', err.message);
        res.json({ suggestions: [] }); // never 500 — UI must always render
    }
});
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
npx jest tests/unit/smartSuggestions.test.js --no-coverage
```

Expected: all 4 tests PASS

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
npm test --no-coverage 2>&1 | tail -20
```

Expected: no new failures

- [ ] **Step 6: Commit**

```bash
git add server.js tests/unit/smartSuggestions.test.js
git commit -m "feat: add GET /smart-suggestions endpoint with LLM-powered chat analysis"
```

---

## Task 4: Flutter — `ApiService.getSmartSuggestions` + `HomeController` additions

**Files:**
- Modify: `jarvis_mobile/lib/services/api_service.dart`
- Modify: `jarvis_mobile/lib/screens/home/home_controller.dart`

### Context

`ApiService` uses `_client.get(_uri('/path'), headers: _baseHeaders).timeout(_timeout)` then `jsonDecode(_safeBody(res))`. `HomeController._loadSecondary()` calls `_loadDashboardContext()`, `_loadWeekData()`, `_loadBriefingCache()`, `_loadAiRankCache()` — add `_loadSmartSuggestions()` after these. `notifyListeners()` must be called after state changes.

---

- [ ] **Step 1: Add `getSmartSuggestions()` to `ApiService`**

In `jarvis_mobile/lib/services/api_service.dart`, find `getDayPlan()` (around line 270) and add the new method right after it:

```dart
Future<List<Map<String, dynamic>>> getSmartSuggestions() async {
  final res = await _client
      .get(_uri('/smart-suggestions'), headers: _baseHeaders)
      .timeout(_timeout);
  final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['suggestions'] ?? []);
}
```

- [ ] **Step 2: Add smart suggestions state to `HomeController`**

In `jarvis_mobile/lib/screens/home/home_controller.dart`, find the `// ── Secondary data` comment block (around line 32) and add after the `dashboardLoading` line:

```dart
// ── Smart suggestions (AI bar in RemindersCard) ──
List<Map<String, dynamic>> smartSuggestions = [];
bool suggestionsLoading = false;
final Set<String> _dismissedSuggestions = {};

List<Map<String, dynamic>> get activeSuggestions =>
    smartSuggestions
        .where((s) => !_dismissedSuggestions.contains(s['id']?.toString()))
        .toList();

void dismissSuggestion(String id) {
  _dismissedSuggestions.add(id);
  notifyListeners();
}
```

- [ ] **Step 3: Add `_loadSmartSuggestions()` and wire it into `_loadSecondary()`**

Find `_loadSecondary()` in `home_controller.dart`:

```dart
void _loadSecondary() {
  _loadDashboardContext();
  _loadWeekData();
  _loadBriefingCache();
  _loadAiRankCache();
}
```

Replace it with:

```dart
void _loadSecondary() {
  _loadDashboardContext();
  _loadWeekData();
  _loadBriefingCache();
  _loadAiRankCache();
  _loadSmartSuggestions();
}
```

Then add the new method after `_fetchAiRank()` (end of the loading section, around line 318):

```dart
Future<void> _loadSmartSuggestions() async {
  if (suggestionsLoading) return;
  suggestionsLoading = true;
  notifyListeners();
  try {
    smartSuggestions = await api.getSmartSuggestions();
  } catch (_) {
    smartSuggestions = [];
  }
  suggestionsLoading = false;
  notifyListeners();
}
```

- [ ] **Step 4: Verify no analysis errors**

```bash
cd jarvis_mobile && flutter analyze lib/services/api_service.dart lib/screens/home/home_controller.dart 2>&1 | grep -E "error|warning" | head -20
```

Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add jarvis_mobile/lib/services/api_service.dart jarvis_mobile/lib/screens/home/home_controller.dart
git commit -m "feat: add smart suggestions state to HomeController and ApiService"
```

---

## Task 5: Flutter — `RemindersCard` AI suggestion bar

**Files:**
- Modify: `jarvis_mobile/lib/widgets/home/reminders_card.dart`
- Modify: `jarvis_mobile/lib/screens/home/home_dialogs.dart`

### Context

`RemindersCard` is currently a `StatelessWidget`. It needs to become a `StatefulWidget` to track `_suggestionsOpen`. The card's `build` method returns a `Container` with a `Column` child. The AI bar goes **above** the 7-day strip `Padding` (before the first `Divider`). `c.activeSuggestions` provides the list; `c.dismissSuggestion(id)` dismisses. `showAddReminderDialog` needs an optional `initialText` param.

---

- [ ] **Step 1: Add `initialText` to `showAddReminderDialog`**

In `jarvis_mobile/lib/screens/home/home_dialogs.dart`, find:

```dart
void showAddReminderDialog(BuildContext context, HomeController c) {
  final textController = TextEditingController();
```

Replace with:

```dart
void showAddReminderDialog(BuildContext context, HomeController c, {String? initialText}) {
  final textController = TextEditingController(text: initialText ?? '');
```

- [ ] **Step 2: Convert `RemindersCard` to `StatefulWidget` and add AI bar**

Replace the entire content of `jarvis_mobile/lib/widgets/home/reminders_card.dart` with:

```dart
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_dialogs.dart';
import '../../screens/home/home_helpers.dart';

/// Reminders with an inline 7-day strip on top and an AI suggestions bar.
class RemindersCard extends StatefulWidget {
  final HomeController c;
  const RemindersCard(this.c, {super.key});

  @override
  State<RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<RemindersCard> {
  bool _suggestionsOpen = false;

  HomeController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime.now();

    final sorted = c.reminders.where((r) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null || iso.isEmpty) return false;
      try {
        final dt = DateTime.parse(iso).toLocal();
        return !dt.isBefore(now.subtract(const Duration(minutes: 1)));
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => (a['scheduled_time'] as String? ?? '')
          .compareTo(b['scheduled_time'] as String? ?? ''));

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text('תזכורות (${sorted.length})',
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  )),
            ]),
          ),
          // ── AI suggestions bar ──
          if (c.activeSuggestions.isNotEmpty || c.suggestionsLoading)
            _buildAiBar(context),
          Divider(color: JC.border, height: 1),
          // ── 7-day strip ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                itemBuilder: (_, i) {
                  final offset = i - 3;
                  final day = today.add(Duration(days: offset));
                  final isToday = offset == 0;
                  final isSelected = offset == c.selectedDayOffset;
                  final remCount = c.reminderCountForDay(day);

                  return Semantics(
                    button: true,
                    label: '${hebrewDays[day.weekday % 7]} ${day.day}, $remCount תזכורות',
                    selected: isSelected,
                    child: GestureDetector(
                      onTap: () => c.selectDay(offset),
                      child: Container(
                        width: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? JC.blue500
                              : isToday
                                  ? JC.blue500.withValues(alpha: 0.15)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday && !isSelected
                              ? Border.all(
                                  color: JC.blue500.withValues(alpha: 0.5), width: 1)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(hebrewDays[day.weekday % 7],
                                style: TextStyle(
                                  color: isSelected ? JC.onAccent : JC.textMuted,
                                  fontSize: 10,
                                  fontFamily: 'Heebo',
                                )),
                            const SizedBox(height: 3),
                            Text('${day.day}',
                                style: TextStyle(
                                  color: isSelected ? JC.onAccent : JC.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Heebo',
                                )),
                            const SizedBox(height: 3),
                            if (remCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? JC.onAccent.withValues(alpha: 0.3)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text('$remCount',
                                    style: TextStyle(
                                      color: isSelected
                                          ? JC.onAccent
                                          : const Color(0xFFF59E0B),
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Heebo',
                                    )),
                              )
                            else
                              const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Divider(color: JC.border, height: 1),
          // ── Body: today → urgency grouping, other day → that day's list ──
          Padding(
            padding: const EdgeInsets.all(14),
            child: c.selectedDayOffset == 0
                ? _todayView(now, sorted)
                : _dayView(c.selectedDayOffset),
          ),
        ],
      ),
    );
  }

  // ── AI bar ──────────────────────────────────────────────────────────────────

  Widget _buildAiBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _suggestionsOpen = !_suggestionsOpen),
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.25), width: 0.8),
            ),
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFA78BFA),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.suggestionsLoading
                      ? '✦ טוען תובנות...'
                      : '✦ ${c.activeSuggestions.length} תובנות AI',
                  style: const TextStyle(
                    color: Color(0xFFA78BFA),
                    fontSize: 12,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!c.suggestionsLoading && c.activeSuggestions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('חדש',
                      style: TextStyle(
                          color: Color(0xFFA78BFA),
                          fontSize: 10,
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                _suggestionsOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: const Color(0xFF64748B),
                size: 18,
              ),
            ]),
          ),
        ),
        if (_suggestionsOpen && c.activeSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Column(
              children: c.activeSuggestions
                  .map((s) => _suggestionRow(context, s))
                  .toList(),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _suggestionRow(BuildContext context, Map<String, dynamic> s) {
    final id = s['id']?.toString() ?? '';
    final text = s['text']?.toString() ?? '';
    final sourceType = s['sourceType']?.toString() ?? 'chat';
    final sourceLabel = s['sourceLabel']?.toString() ?? '';

    final (srcEmoji, srcColor) = switch (sourceType) {
      'task' => ('📋', const Color(0xFFEF4444)),
      'plan' => ('🗓', const Color(0xFF22C55E)),
      _ => ('💬', const Color(0xFFA78BFA)),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2137),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(
            start: BorderSide(color: srcColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: srcColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$srcEmoji ${sourceType == 'task' ? 'משימה' : sourceType == 'plan' ? 'תכנון' : 'שיחה'}',
                  style: TextStyle(
                      color: srcColor,
                      fontSize: 10,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700)),
            ),
            if (sourceLabel.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(sourceLabel,
                  style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontFamily: 'Heebo')),
            ],
          ]),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            _actionBtn('📋 משימה', const Color(0xFF3B82F6),
                () => c.addTask(text)),
            const SizedBox(width: 6),
            _actionBtn('⏰ תזכורת', const Color(0xFFF59E0B),
                () => showAddReminderDialog(context, c, initialText: text)),
            const SizedBox(width: 6),
            _actionBtn('💬 שיחה', const Color(0xFFA78BFA),
                () => c.onNavigateToChat?.call(command: text)),
            const Spacer(),
            GestureDetector(
              onTap: () => c.dismissSuggestion(id),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF64748B), size: 16),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── Reminders body (unchanged from original) ─────────────────────────────────

  Widget _todayView(DateTime now, List<Map<String, dynamic>> sorted) {
    if (sorted.isEmpty) {
      return const EmptyState(message: 'אין תזכורות קרובות');
    }

    final urgent = sorted.where((r) {
      try {
        final diff = DateTime.parse(r['scheduled_time'] as String)
            .toLocal()
            .difference(now);
        return diff.inMinutes >= 0 && diff.inMinutes <= 120;
      } catch (_) {
        return false;
      }
    }).toList();

    final todayLater = sorted.where((r) {
      try {
        final dt = DateTime.parse(r['scheduled_time'] as String).toLocal();
        final diff = dt.difference(now);
        return diff.inMinutes > 120 &&
            dt.day == now.day &&
            dt.month == now.month &&
            dt.year == now.year;
      } catch (_) {
        return false;
      }
    }).toList();

    final upcoming = sorted.where((r) {
      try {
        final dt = DateTime.parse(r['scheduled_time'] as String).toLocal();
        return !(dt.day == now.day &&
            dt.month == now.month &&
            dt.year == now.year);
      } catch (_) {
        return false;
      }
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (urgent.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 0.8),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_rounded,
                color: Color(0xFFEF4444), size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                urgent.length == 1
                    ? 'תזכורת דחופה בתוך שעתיים'
                    : '${urgent.length} תזכורות דחופות בתוך שעתיים',
                style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        _groupHeader('בקרוב', const Color(0xFFEF4444)),
        const SizedBox(height: 6),
        ...urgent.map((r) => _row(r, const Color(0xFFEF4444))),
        if (todayLater.isNotEmpty || upcoming.isNotEmpty)
          const SizedBox(height: 10),
      ],
      if (todayLater.isNotEmpty) ...[
        _groupHeader('היום', const Color(0xFFF59E0B)),
        const SizedBox(height: 6),
        ...todayLater.map((r) => _row(r, const Color(0xFFF59E0B))),
        if (upcoming.isNotEmpty) const SizedBox(height: 10),
      ],
      if (upcoming.isNotEmpty) ...[
        _groupHeader('הבא', const Color(0xFF3B82F6)),
        const SizedBox(height: 6),
        ...upcoming.take(3).map((r) => _row(r, const Color(0xFF3B82F6))),
        if (upcoming.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+${upcoming.length - 3} נוספות',
                style: TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ),
      ],
    ]);
  }

  Widget _dayView(int offset) {
    final events = c.remindersForOffset(offset);
    if (events.isEmpty) {
      return const EmptyState(message: 'אין תזכורות ביום זה');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _groupHeader('אירועים ביום זה', const Color(0xFFF59E0B)),
      const SizedBox(height: 6),
      ...events.take(6).map((r) => _row(r, const Color(0xFFF59E0B))),
      if (events.length > 6)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+${events.length - 6} נוספות',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
        ),
    ]);
  }

  Widget _groupHeader(String label, Color color) {
    return Row(children: [
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _row(Map<String, dynamic> reminder, Color accent) {
    final text = reminder['text'] as String? ?? '—';
    final iso = reminder['scheduled_time'] as String?;
    final timeStr = timeOfDay(iso);
    final remaining = formatRemTime(iso);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(start: BorderSide(color: accent, width: 2)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(timeStr.isEmpty ? '—' : timeStr,
                style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600)),
            if (remaining.isNotEmpty)
              Text(remaining,
                  style: TextStyle(
                      color: accent, fontSize: 11, fontFamily: 'Heebo')),
          ]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 3: Verify no analysis errors**

```bash
cd jarvis_mobile && flutter analyze lib/widgets/home/reminders_card.dart lib/screens/home/home_dialogs.dart 2>&1 | grep -E "error" | head -20
```

Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add jarvis_mobile/lib/widgets/home/reminders_card.dart jarvis_mobile/lib/screens/home/home_dialogs.dart
git commit -m "feat: add AI suggestions bar to RemindersCard"
```

---

## Task 6: Flutter — `TasksCard` collapsed groups + inline task expand

**Files:**
- Modify: `jarvis_mobile/lib/widgets/home/tasks_card.dart`

### Context

`TasksCard` is currently a `StatelessWidget`. It uses `_group()` which renders a group header + rows unconditionally. `_row()` shows the task content in full. The `Dismissible` swipe logic, `tryCompleteTask`, and `_swipeBg` must be preserved unchanged. Due dates are in `task['due_date']` (ISO string or null). Category is in `task['category']` (string or null). `subtasksOf(task)` comes from `home_helpers.dart`.

---

- [ ] **Step 1: Convert `TasksCard` to `StatefulWidget` with collapsed groups and inline expand**

Replace the entire content of `jarvis_mobile/lib/widgets/home/tasks_card.dart` with:

```dart
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_dialogs.dart';
import '../../screens/home/home_helpers.dart';

class TasksCard extends StatefulWidget {
  final HomeController c;
  const TasksCard(this.c, {super.key});

  @override
  State<TasksCard> createState() => _TasksCardState();
}

class _TasksCardState extends State<TasksCard> {
  final Set<String> _openGroups = {};
  final Set<String> _expandedTasks = {};

  HomeController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    final done = c.doneTasks;
    final total = c.totalTasks;
    final open = c.openTasks;
    final progress = total == 0 ? 0.0 : done / total;

    bool isHigh(Map t) => (t['priority'] ?? '').toString().toLowerCase() == 'high';
    bool starred(Map t) => c.markedImportant.contains(t['id'].toString());

    final highTasks =
        c.tasks.where((t) => t['done'] != true && isHigh(t)).toList();
    final starredTasks = c.tasks
        .where((t) => t['done'] != true && !isHigh(t) && starred(t))
        .toList();
    final queueTasks = c.tasks
        .where((t) => t['done'] != true && !isHigh(t) && !starred(t))
        .toList();

    return SectionCard(
      title: 'משימות להיום ($open פתוחות)',
      icon: Icons.checklist_rounded,
      iconColor: const Color(0xFF3B82F6),
      headerTrailing: GestureDetector(
        onTap: () => showAddTaskDialog(context, c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.3), width: 0.8),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Color(0xFF3B82F6), size: 14),
            SizedBox(width: 3),
            Text('חדשה',
                style: TextStyle(
                    color: Color(0xFF3B82F6),
                    fontSize: 11,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(children: [
                Container(height: 5, color: JC.border),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(height: 5, color: JC.green500),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Text('$done/$total הושלמו',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
        ]),
        if (open == 0) ...[
          const SizedBox(height: 12),
          const EmptyState(message: 'כל המשימות הושלמו! 🎉'),
        ] else ...[
          const SizedBox(height: 12),
          if (highTasks.isNotEmpty)
            _group(context, 'high', 'דחוף', const Color(0xFFEF4444), highTasks),
          if (starredTasks.isNotEmpty)
            _group(context, 'starred', 'מסומן חשוב', const Color(0xFFF59E0B), starredTasks),
          if (queueTasks.isNotEmpty)
            _group(context, 'queue', 'בתור', const Color(0xFF3B82F6), queueTasks),
        ],
      ]),
    );
  }

  Widget _group(BuildContext context, String groupKey, String label, Color color,
      List<Map<String, dynamic>> tasks) {
    final isOpen = _openGroups.contains(groupKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Group header (always visible, tap to toggle) ──
        GestureDetector(
          onTap: () => setState(() {
            if (isOpen) {
              _openGroups.remove(groupKey);
            } else {
              _openGroups.add(groupKey);
            }
          }),
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo')),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${tasks.length}',
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo')),
              ),
              const Spacer(),
              Icon(
                isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: JC.textMuted,
                size: 16,
              ),
            ]),
          ),
        ),
        // ── Expanded task list ──
        if (isOpen) ...[
          const SizedBox(height: 4),
          ...tasks.map((t) => _row(context, t, color)),
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> task, Color accent) {
    final id = task['id'].toString();
    final content = task['content'] as String? ?? '—';
    final priority = task['priority'] as String?;
    final isHigh = (priority ?? '').toString().toLowerCase() == 'high';
    final isImportant = c.markedImportant.contains(id);
    final rowAccent = isHigh ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final subs = subtasksOf(task);
    final openSubs = subs.where((s) => s['done'] != true).length;
    final isExpanded = _expandedTasks.contains(id);

    // Due date formatting
    String dueLabel = '';
    final dueIso = task['due_date'] as String?;
    if (dueIso != null) {
      try {
        final dt = DateTime.parse(dueIso).toLocal();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dueDay = DateTime(dt.year, dt.month, dt.day);
        final hhmm =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        if (dueDay == today) {
          dueLabel = 'היום $hhmm';
        } else if (dueDay == today.subtract(const Duration(days: 1))) {
          dueLabel = 'אתמול';
        } else {
          dueLabel = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
        }
      } catch (_) {}
    }
    final category = task['category'] as String?;

    return Dismissible(
      key: ValueKey('task-$id'),
      background: _swipeBg(AlignmentDirectional.centerStart,
          const Color(0xFF22C55E), Icons.check_rounded, 'השלם'),
      secondaryBackground: _swipeBg(AlignmentDirectional.centerEnd,
          const Color(0xFF3B82F6), Icons.schedule_rounded, 'דחה'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await tryCompleteTask(context, c, task);
          return false;
        } else {
          c.postponeTask(task);
          return false;
        }
      },
      child: GestureDetector(
        onTap: () => setState(() {
          if (isExpanded) {
            _expandedTasks.remove(id);
          } else {
            _expandedTasks.add(id);
          }
        }),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: JC.jarvisBubble,
            borderRadius: BorderRadius.circular(10),
            border: BorderDirectional(start: BorderSide(color: rowAccent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Semantics(
                  button: true,
                  label: 'סיים משימה: $content',
                  child: GestureDetector(
                    onTap: () => tryCompleteTask(context, c, task),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.completing.contains(id)
                                  ? JC.green500
                                  : rowAccent,
                              width: 1.5,
                            ),
                            color: c.completing.contains(id)
                                ? JC.green500.withValues(alpha: 0.15)
                                : Colors.transparent,
                          ),
                          child: c.completing.contains(id)
                              ? Icon(Icons.check_rounded, size: 13, color: JC.green500)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    content,
                    maxLines: isExpanded ? null : 1,
                    overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 13,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: JC.textMuted,
                  size: 16,
                ),
                Semantics(
                  button: true,
                  label: isImportant ? 'מסומן חשוב' : 'סמן כחשוב',
                  child: GestureDetector(
                    onTap: isImportant ? null : () => c.markImportant(task),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(
                          isImportant ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: isImportant ? JC.amber400 : JC.textMuted,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
              // ── Expanded detail row ──
              if (isExpanded) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (dueLabel.isNotEmpty)
                    _detailChip(Icons.schedule_rounded, dueLabel, JC.blue400),
                  if (category != null && category.isNotEmpty)
                    _detailChip(Icons.label_outline_rounded, category, JC.textMuted),
                  if (subs.isNotEmpty)
                    _detailChip(Icons.checklist_rounded,
                        '${subs.length - openSubs}/${subs.length} תתי-משימות',
                        openSubs > 0 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E)),
                ]),
              ] else if (subs.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.checklist_rounded, size: 11, color: JC.textMuted),
                  const SizedBox(width: 3),
                  Text('${subs.length - openSubs}/${subs.length} תתי-משימות',
                      style: TextStyle(
                          color: openSubs > 0
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF22C55E),
                          fontSize: 10,
                          fontFamily: 'Heebo')),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Future<void> tryCompleteTask(
      BuildContext context, HomeController c, Map<String, dynamic> task) async {
    if (await guardComplete(context, task)) c.completeTask(task);
  }

  Widget _swipeBg(
      AlignmentDirectional align, Color color, IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: align,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
```

- [ ] **Step 2: Verify no analysis errors**

```bash
cd jarvis_mobile && flutter analyze lib/widgets/home/tasks_card.dart 2>&1 | grep -E "error" | head -20
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add jarvis_mobile/lib/widgets/home/tasks_card.dart
git commit -m "feat: TasksCard collapsed groups with inline task detail expand"
```

---

## Task 7: Flutter — `WeatherNewsCard` tab layout with sports and tech

**Files:**
- Modify: `jarvis_mobile/lib/widgets/home/weather_news_card.dart`

### Context

`WeatherNewsCard` reads from `c.dashboardContext?['widgets']` via `_widgetData(type)`. The server now returns widgets of type `'weather'`, `'news'`, `'sports'`, `'tech'`. Weather is always shown as a pill. The tab bar shows only tabs with data. News, sports, and tech all render as headline lists. `_buildWeather()` currently renders a large-format weather block; we extract a compact `_buildWeatherPill()` from it. The card uses `SectionCard` from `home_helpers.dart`. Add `SingleTickerProviderStateMixin`.

---

- [ ] **Step 1: Replace `WeatherNewsCard` with tab-based layout**

Replace the entire content of `jarvis_mobile/lib/widgets/home/weather_news_card.dart` with:

```dart
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

class _Topic {
  final String key;
  final String emoji;
  final String label;
  final Color color;
  const _Topic(this.key, this.emoji, this.label, this.color);
}

const _kTopics = [
  _Topic('news',   '📰', 'חדשות',      Color(0xFFF59E0B)),
  _Topic('sports', '⚽', 'ספורט',       Color(0xFF22C55E)),
  _Topic('tech',   '💻', 'טכנולוגיה',  Color(0xFFA78BFA)),
];

/// Weather pill always visible + tabbed news/sports/tech feed.
class WeatherNewsCard extends StatefulWidget {
  final HomeController c;
  const WeatherNewsCard(this.c, {super.key});

  @override
  State<WeatherNewsCard> createState() => _WeatherNewsCardState();
}

class _WeatherNewsCardState extends State<WeatherNewsCard>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<_Topic> _lastAvailable = [];

  HomeController get c => widget.c;

  Map<String, dynamic>? _widgetData(String type) {
    final widgets = c.dashboardContext?['widgets'] as List?;
    if (widgets == null) return null;
    for (final w in widgets) {
      if (w is Map && w['type'] == type) {
        final data = w['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    }
    return null;
  }

  List<_Topic> get _available =>
      _kTopics.where((t) => _widgetData(t.key) != null).toList();

  void _syncTabController(List<_Topic> available) {
    if (available.length != _lastAvailable.length) {
      _tabController?.dispose();
      _tabController = available.isEmpty
          ? null
          : TabController(length: available.length, vsync: this);
      _lastAvailable = List.from(available);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weatherData = _widgetData('weather');
    final available = _available;
    _syncTabController(available);

    Widget body;
    if (c.dashboardLoading && c.dashboardContext == null) {
      body = const CardSkeleton(lines: 4);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Weather pill (always visible) ──
          if (weatherData != null) ...[
            _buildWeatherPill(weatherData),
            const SizedBox(height: 10),
          ],
          // ── Tab bar + content ──
          if (available.isEmpty && weatherData == null)
            const EmptyState(message: 'אין מידע זמין כרגע')
          else if (available.isNotEmpty && _tabController != null) ...[
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Heebo', fontSize: 12),
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: JC.border,
              tabs: available
                  .map((t) => Tab(text: '${t.emoji} ${t.label}'))
                  .toList(),
              labelColor: JC.textPrimary,
              unselectedLabelColor: JC.textMuted,
              indicatorColor: JC.blue500,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 160,
              child: TabBarView(
                controller: _tabController,
                children: available.map((t) {
                  final data = _widgetData(t.key)!;
                  return _buildHeadlineList(data, t.color);
                }).toList(),
              ),
            ),
          ],
        ],
      );
    }

    return SectionCard(
      title: 'סביבה',
      icon: Icons.public_rounded,
      iconColor: const Color(0xFF60A5FA),
      child: body,
    );
  }

  /// Compact weather pill: emoji · temp · desc · chips row.
  Widget _buildWeatherPill(Map<String, dynamic> d) {
    final emoji = (d['emoji'] as String?) ?? '🌡';
    final temp  = d['temp']  as int?;
    final desc  = (d['desc'] as String?) ?? '';
    final max   = d['max']   as int?;
    final min   = d['min']   as int?;
    final rain  = d['rain']  as int?;
    final city  = (d['city'] as String?) ?? '';

    if (temp == null) {
      final summary = (d['summary'] as String?) ?? '';
      return Text(summary,
          style: TextStyle(
              color: JC.textSecondary,
              fontSize: 12.5,
              height: 1.5,
              fontFamily: 'Heebo'));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.18), width: 0.8),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$temp°',
                  style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                      height: 1.0)),
              if (city.isNotEmpty) ...[
                const Spacer(),
                Text(city,
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 11,
                        fontFamily: 'Heebo')),
              ],
            ]),
            if (desc.isNotEmpty)
              Text(desc,
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 11,
                      fontFamily: 'Heebo')),
            const SizedBox(height: 4),
            Wrap(spacing: 5, children: [
              if (max != null && min != null)
                _wChip('↑$max° ↓$min°', const Color(0xFF60A5FA)),
              if (rain != null && rain > 0)
                _wChip('$rain% גשם', const Color(0xFF818CF8)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _wChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.7),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600)),
    );
  }

  /// Renders a headline list (news, sports, or tech — same structure).
  Widget _buildHeadlineList(Map<String, dynamic> d, Color dotColor) {
    final rawHeadlines = d['headlines'];
    final headlines = rawHeadlines is List
        ? rawHeadlines.cast<String>()
        : (d['summary'] as String? ?? '')
            .split('\n')
            .map((l) => l.replaceFirst(RegExp(r'^[•·]\s*'), ''))
            .where((l) => l.isNotEmpty)
            .toList();

    if (headlines.isEmpty) return const EmptyState(message: 'אין כותרות');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (int i = 0; i < headlines.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(headlines[i],
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                      fontFamily: 'Heebo')),
            ),
          ]),
        ],
      ],
    );
  }
}
```

- [ ] **Step 2: Verify no analysis errors**

```bash
cd jarvis_mobile && flutter analyze lib/widgets/home/weather_news_card.dart 2>&1 | grep -E "error" | head -20
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add jarvis_mobile/lib/widgets/home/weather_news_card.dart
git commit -m "feat: WeatherNewsCard tab layout with weather pill + news/sports/tech tabs"
```

---

## Task 8: Flutter — Build Your Day brief refocused on agenda

**Files:**
- Modify: `jarvis_mobile/lib/screens/home/home_dialogs.dart`

### Context

`_BuildDaySheetState._fetchBrief()` (around line 230) calls `c.api.askJarvis(prompt, c.settings)` with a general motivation prompt. Change it to pass the user's open tasks so the LLM focuses on agenda planning.

---

- [ ] **Step 1: Update `_fetchBrief` prompt in `home_dialogs.dart`**

Find `_fetchBrief()` in `_BuildDaySheetState`. Replace the entire method body with:

```dart
Future<void> _fetchBrief() async {
  setState(() => _briefLoading = true);
  try {
    final openCount = c.openTasks;
    final topTasks = c.tasks
        .where((t) => t['done'] != true)
        .take(5)
        .map((t) => '- ${(t['content'] ?? '').toString()}')
        .join('\n');
    final prompt =
        'בנה לי תוכנית יום קצרה בעברית (3-4 משפטים). '
        'יש לי $openCount משימות פתוחות. '
        '${topTasks.isNotEmpty ? 'המשימות הבולטות:\n$topTasks\n\n' : ''}'
        'מה כדאי לטפל בו ראשון ולמה? איך לארגן את היום בצורה יעילה? '
        'תן עצה קצרה ומעשית, בלי כותרות מודגשות.';
    final r = await c.api.askJarvis(prompt, c.settings);
    if (mounted) setState(() => _brief = r['answer'] as String? ?? '');
  } catch (_) {
    if (mounted) setState(() => _brief = '');
  }
  if (mounted) setState(() => _briefLoading = false);
}
```

- [ ] **Step 2: Verify no analysis errors**

```bash
cd jarvis_mobile && flutter analyze lib/screens/home/home_dialogs.dart 2>&1 | grep -E "error" | head -20
```

Expected: no errors

- [ ] **Step 3: Run all JS tests to check for regressions**

```bash
cd /home/user/jarvis-server-nadav && npm test --no-coverage 2>&1 | tail -15
```

Expected: all existing tests still pass

- [ ] **Step 4: Commit**

```bash
git add jarvis_mobile/lib/screens/home/home_dialogs.dart
git commit -m "feat: Build Your Day brief focused on agenda planning instead of trivia"
```

- [ ] **Step 5: Push all changes**

```bash
git push -u origin claude/plugins-installation-ka1skx
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Covered by |
|---|---|
| `getTopicHeadlines` in newsSource.js | Task 1 |
| Sports + tech in /dashboard-context | Task 2 |
| GET /smart-suggestions endpoint | Task 3 |
| ApiService.getSmartSuggestions | Task 4 |
| HomeController smart suggestions state | Task 4 |
| RemindersCard AI bar (collapsed/expanded) | Task 5 |
| showAddReminderDialog initialText | Task 5 |
| TasksCard collapsed groups | Task 6 |
| TasksCard inline task expand | Task 6 |
| WeatherNewsCard weather pill always visible | Task 7 |
| WeatherNewsCard tab bar (news/sports/tech) | Task 7 |
| Build Your Day agenda-focused brief | Task 8 |

All spec requirements covered. No gaps.

### Type consistency check

- `getTopicHeadlines` returns `{ headlines: string[] } | null` — matches how Task 2 uses it: `if (sportsData) widgets.push({ type: 'sports', data: sportsData })`
- `getSmartSuggestions()` returns `List<Map<String, dynamic>>` — matches `smartSuggestions` field type in HomeController
- `c.activeSuggestions` returns `List<Map<String, dynamic>>` — matches how Task 5 iterates it with `_suggestionRow(context, s)`
- `s['id']`, `s['text']`, `s['sourceType']`, `s['sourceLabel']` — set in Task 3 `id: \`sug-...\`` etc., consumed in Task 5 ✓
- `_tabController` is `TabController?`, synced via `_syncTabController` before use — checked `!= null` before `TabBarView` ✓
