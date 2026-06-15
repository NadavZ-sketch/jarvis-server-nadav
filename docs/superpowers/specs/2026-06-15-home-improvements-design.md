# Home Screen Improvements — Design Spec

## Goal

Three focused improvements to the home screen:
1. **Compact tasks card** — collapsed priority groups with inline task expansion
2. **Smart reminders zone** — AI-powered suggestion bar inside the reminders card
3. **Environment card upgrade** — tabs for news/sports/tech + weather pill always visible; Build Your Day brief refocused on agenda

---

## Feature 1: Tasks Card — Collapsed Groups + Inline Expand

### Summary

`TasksCard` currently shows all three priority groups fully open, each displaying up to 4 items. With many tasks the card grows very tall. The new design collapses all groups by default; tapping a group header expands it; tapping an individual task expands it inline to show full content and metadata.

### UI Structure (3 levels)

**Level 1 — Group row (always visible):**
- Color dot · group label (דחוף / מסומן חשוב / בתור) · count badge · chevron (› / ∨)
- Tap → AnimatedSwitcher toggles expanded state

**Level 2 — Task row (visible when group is open):**
- Completion circle (left, tappable) · content truncated to 1 line with ellipsis · expand chevron (›)
- Swipe start→end = complete; swipe end→start = postpone (Dismissible unchanged)

**Level 3 — Task detail (inline, visible when task is tapped):**
- Full content text (wrapping, no limit)
- Due date chip if `due_date` is set (formatted as `היום HH:mm` / `dd/MM`)
- Category badge if `category` is set
- Star button (mark important) if not already marked

### State

`TasksCard` becomes a `StatefulWidget`. Local state only — not persisted between sessions.

```dart
final Set<String> _openGroups = {};    // 'high' | 'starred' | 'queue'
final Set<String> _expandedTasks = {}; // task id strings
```

All groups start collapsed (`_openGroups` is empty on `initState`).

### Files

- **Modify:** `jarvis_mobile/lib/widgets/home/tasks_card.dart`
  - Convert `StatelessWidget` → `StatefulWidget`
  - Add `_openGroups` and `_expandedTasks` state
  - Replace `_group()` with `_collapsedGroupRow()` + `_expandedGroup()` pattern
  - Replace `_row()` with two-level `_taskRow()` that switches between compact and detail view
  - Keep all Dismissible logic, `tryCompleteTask`, `_swipeBg` unchanged

### No backend changes needed.

---

## Feature 2: Smart Reminders Zone

### Summary

A collapsible AI bar appears at the top of `RemindersCard`. By default it shows a single-line summary ("✦ 3 תובנות AI · חדש"). Tapping it expands to reveal up to 5 suggestions derived from: recent chat history, stale tasks, and future plans mentioned in conversations. Each suggestion offers 3 action buttons and a dismiss.

### Backend — `GET /smart-suggestions`

New endpoint in `server.js`.

**Algorithm:**
1. Fetch last 30 rows from `chat_history` (columns: `role`, `content`, `created_at`) ordered desc
2. Fetch stale open tasks: `tasks` where `done = false` and `created_at < NOW() - INTERVAL '3 days'`
3. Build LLM prompt (Hebrew) listing the chat excerpts and stale tasks; ask for up to 5 actionable suggestions
4. Parse the JSON array the LLM returns; validate structure
5. Return `{ suggestions: [{ id, text, sourceType, sourceLabel }] }`

**Suggestion object fields:**
- `id` — `string` (UUID or hash of text for dedup)
- `text` — `string` (Hebrew, ≤ 60 chars ideally)
- `sourceType` — `'chat' | 'task' | 'plan'`
- `sourceLabel` — `string` (e.g., `"לפני 2 ימים"`, `"פגת תוקף"`, `"מאתמול"`)

**LLM prompt template (to send via `callGemma4`):**
```
להלן היסטוריית שיחות אחרונה עם המשתמש (תמציות):
{chat_excerpts}

ולהלן משימות ישנות שלא טופלו:
{stale_tasks}

זהה עד 5 פריטים שהמשתמש אמר שצריך לטפל בהם, תכנן, או שכח.
החזר JSON בלבד, ללא הסברים:
[{"text":"...","sourceType":"chat|task|plan","sourceLabel":"..."}]
```

**Caching:** In-process TTL cache, key `smart-suggestions`, TTL 60 minutes. No explicit cache invalidation needed — TTL is sufficient for a personal assistant context.

**Rate limit:** Reuse existing `_rl(10)` middleware (10 req/min).

**Error handling:** Return `{ suggestions: [] }` on any failure — never 500 on this endpoint, never block the UI.

**Files:**
- **Modify:** `server.js` — add `GET /smart-suggestions` handler (~40 lines); add `cacheDelete('smart-suggestions')` calls in `POST /tasks` and `POST /reminders` handlers
- **New:** `tests/unit/smartSuggestions.test.js` — unit test the LLM prompt builder and response parser (mock `callGemma4`)

### Flutter — `HomeController` additions

```dart
// in home_controller.dart
List<Map<String, dynamic>> smartSuggestions = [];
bool suggestionsLoading = false;
final Set<String> _dismissedSuggestions = {};

List<Map<String, dynamic>> get activeSuggestions =>
    smartSuggestions.where((s) => !_dismissedSuggestions.contains(s['id'])).toList();

void dismissSuggestion(String id) {
  _dismissedSuggestions.add(id);
  notifyListeners();
}
```

`_loadSecondary()` calls `_loadSmartSuggestions()` (after existing calls, non-blocking).

```dart
Future<void> _loadSmartSuggestions() async {
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

**Files:**
- **Modify:** `jarvis_mobile/lib/screens/home/home_controller.dart`
- **Modify:** `jarvis_mobile/lib/services/api_service.dart` — add `getSmartSuggestions()` → `GET /smart-suggestions`

### Flutter — `RemindersCard` UI

`RemindersCard` becomes a `StatefulWidget`. Adds `bool _suggestionsOpen = false` state.

The card body gains an AI bar **above the 7-day strip divider**:

**Collapsed state (default):**
```
[purple dot]  ✦ {N} תובנות AI    [חדש badge]  ›
```
- Tapping the bar sets `_suggestionsOpen = true`
- Hidden entirely if `c.activeSuggestions.isEmpty` and not `c.suggestionsLoading`

**Expanded state:**
- Each suggestion row:
  ```
  [source badge: 💬 שיחה | 📋 משימה | 🗓 תכנון]  [sourceLabel]
  [suggestion text — full width]
  [📋 משימה]  [⏰ תזכורת]  [💬 שיחה]  [✕]
  ```
- Action buttons:
  - **📋 משימה** → `c.addTask(suggestion['text'])`
  - **⏰ תזכורת** → `showAddReminderDialog(context, c)` pre-filled with suggestion text (pass optional `initialText` param to dialog)
  - **💬 שיחה** → `c.onNavigateToChat(command: suggestion['text'])`
  - **✕** → `c.dismissSuggestion(suggestion['id'])`

**Files:**
- **Modify:** `jarvis_mobile/lib/widgets/home/reminders_card.dart`
- **Modify:** `jarvis_mobile/lib/screens/home/home_dialogs.dart` — add optional `initialText` parameter to `showAddReminderDialog`

---

## Feature 3: Environment Card — Tabs + Weather Pill

### Summary

`WeatherNewsCard` is refactored from a chip-filter layout to a tab-bar layout. Weather is always visible as a compact pill at the top. A `TabBar` with 4 tabs — ☁ מזג / 📰 חדשות / ⚽ ספורט / 💻 טק — appears below the pill. Tabs for which no data is available are hidden. The `/dashboard-context` backend is extended with sports and tech widgets.

### Backend — `services/newsSource.js`

Add a new export:

```javascript
/**
 * Fetches headlines for a specific topic using Google News RSS search.
 * topic: Hebrew search string (e.g., 'ספורט ישראל', 'טכנולוגיה הייטק')
 */
async function getTopicHeadlines(topic, maxItems = 4) { ... }
```

Uses URL: `https://news.google.com/rss/search?q={encodeURIComponent(topic)}&hl=he&gl=IL&ceid=IL:he`

Reuses the existing `parseHeadlines()` and `_decodeEntities()` helpers.

Cache key: `news:topic:{topic}`, TTL 1 hour (same as main news).

Returns `{ headlines: string[] }` or `null` on error.

**Files:**
- **Modify:** `services/newsSource.js` — add `getTopicHeadlines`, add to `module.exports`
- **Modify:** `tests/unit/newsSource.test.js` — add tests for `getTopicHeadlines` with mocked axios

### Backend — `server.js` `/dashboard-context`

In the parallel `Promise.all`, add two more fetches:

```javascript
const [tasks, reminders, weatherData, newsData, sportsData, techData] = await Promise.all([
  // ... existing ...
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

Add to widgets array:
```javascript
if (sportsData) widgets.push({ type: 'sports', data: sportsData });
if (techData)   widgets.push({ type: 'tech',   data: techData });
```

**Files:**
- **Modify:** `server.js` — extend `/dashboard-context` parallel fetch and widget push

### Flutter — `WeatherNewsCard`

Replace the existing `_kTopics` constant and chip-filter design with a tab-bar approach.

**New `_kTopics`:**
```dart
const _kTopics = [
  _Topic('news',   '📰', 'חדשות',       Color(0xFFF59E0B)),
  _Topic('sports', '⚽', 'ספורט',        Color(0xFF22C55E)),
  _Topic('tech',   '💻', 'טכנולוגיה',   Color(0xFFA78BFA)),
];
```

**Layout:**
1. **Weather pill** (always rendered, regardless of selected tab) — extract `_buildWeatherPill(data)` from the existing `_buildWeather()`, showing: emoji, temp, desc, and max/min/rain chips in a compact `Container` with blue tint border.
2. **`TabBar`** with tabs built from `_available` topics only (those with data). If no tab data: show weather pill only.
3. **`TabBarView`** — each view calls `_buildNews(data)` (same renderer for news, sports, tech — all are headline lists).

Weather tab is removed (weather is always the pill). If `_available` is empty after the server returns, show just the pill.

`WeatherNewsCard` uses `SingleTickerProviderStateMixin` with a `TabController`.

**Files:**
- **Modify:** `jarvis_mobile/lib/widgets/home/weather_news_card.dart`

### Build Your Day Brief — Agenda Focus

The `_fetchBrief()` prompt in `home_dialogs.dart` is changed from motivation+trivia to agenda focus:

**Old prompt:**
```
פתח לי את היום: שורה אחת מוטיבציה אישית, פסקה קצרה "הידעת?" עם עובדה מעניינת,
וציון תאריכים או אירועים מיוחדים של היום אם יש. בעברית, קצר וקולח, בלי כותרות מודגשות.
```

**New prompt (pass task list + count):**
```dart
final openCount = c.openTasks;
final topTasks = c.tasks
    .where((t) => t['done'] != true)
    .take(5)
    .map((t) => '- ${t['content'] ?? ''}')
    .join('\n');
final prompt =
  'בנה לי תוכנית יום קצרה בעברית (3-4 משפטים). '
  'יש לי $openCount משימות פתוחות. '
  'המשימות הבולטות: $topTasks. '
  'מה כדאי לטפל בו ראשון ולמה? איך לארגן את היום בצורה יעילה? '
  'תן עצה קצרה ומעשית, בלי כותרות מודגשות.';
```

**Files:**
- **Modify:** `jarvis_mobile/lib/screens/home/home_dialogs.dart` — `_BuildDaySheetState._fetchBrief()`

---

## Testing Plan

- `tests/unit/smartSuggestions.test.js` — test prompt builder, JSON parser, empty/malformed LLM responses
- `tests/unit/newsSource.test.js` — extend with `getTopicHeadlines` topic search tests
- `tests/integration/dashboardContext.test.js` — add test asserting sports+tech widgets appear when source returns data
- Flutter widget tests: TasksCard collapses groups; SmartReminders bar hidden with empty suggestions

---

## Non-Goals

- No persistent expand/collapse state between app launches
- No server-side suggestion deduplication (client dismisses locally per session)
- No push notifications for smart suggestions
- Sports/tech data does NOT use a paid API — Google News RSS only
