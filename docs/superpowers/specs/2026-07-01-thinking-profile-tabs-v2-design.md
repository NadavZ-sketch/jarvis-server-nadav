# Thinking + Profile Tabs v2 — Design Spec
**Date:** 2026-07-01
**File:** `jarvis-brain.html`
**Scope:** חשיבה (Thinking) tab + פרופיל (Profile) tab — expandable trace entries, cross-filtering, hover tooltips on all charts, new weekly-score widget

---

## 1. Background

Both tabs currently render static SVG charts with zero interactivity — no hover feedback, no click-to-filter, no drill-down. Two data sources already returned by the API are unused in the web dashboard:

- `GET /decision-trace` returns `candidates` (JSON-string array of intent names), `ambiguous` (bool), and `route_mode` (`'keyword'` | `'llm'`) per entry — none of these are rendered; `renderTrace()` only shows time/input/intent/agent/ms.
- `GET /stats/weekly-score` (and `?weeks=N` for history) is called by the mobile control center but never by `jarvis-brain.html`.

This spec brings both tabs to the same interactivity level as Knowledge Tab v2: a shared hover-tooltip helper, click-driven cross-filtering, expandable detail rows, and one new card backed by previously-unused data.

This spec does **not** touch the constellation graph's physics/animation (separate spec, built after this one).

---

## 2. Shared Utility — Chart Tooltip Helper

A single reusable tooltip function used by every chart in both tabs (donut, agent bars, pulse, radar, clock, heatmap, learn curve), replacing the ad-hoc tooltip code already used once for the graph (`#graphTooltip`) and timeline (`#tlTip`):

```js
function showChartTip(text, clientX, clientY) {
  let tip = document.getElementById('chartTip');
  if (!tip) {
    tip = document.createElement('div');
    tip.id = 'chartTip';
    tip.className = 'chart-tip';
    document.body.appendChild(tip);
  }
  tip.textContent = text;
  tip.style.display = 'block';
  const pad = 12;
  let x = clientX + pad, y = clientY + pad;
  if (x + 160 > window.innerWidth) x = clientX - 160 - pad;
  tip.style.left = x + 'px';
  tip.style.top = y + 'px';
}
function hideChartTip() {
  const tip = document.getElementById('chartTip');
  if (tip) tip.style.display = 'none';
}
```

```css
.chart-tip { position:fixed; z-index:200; background:var(--card); border:1px solid var(--border);
  border-radius:var(--r6); padding:5px 9px; font-size:var(--tx-xs); color:var(--fg);
  pointer-events:none; white-space:pre-line; box-shadow:0 4px 12px rgba(0,0,0,.3); }
```

Each chart wires its own SVG element's `pointermove`/`pointerleave` to call `showChartTip(...)`/`hideChartTip()`. No new data fetches — every tooltip is computed from data already in `S`.

---

## 3. חשיבה Tab

### 3.1 Expandable trace entries

`renderTrace()` (`jarvis-brain.html:1171`) currently builds `entries` from `S.trace` but drops `candidates`, `ambiguous`, `route_mode`. Extend the mapped entry to carry them through, and make each `.trace-entry` expandable (same `max-height` transition pattern as Knowledge's `.insight-card`):

```
┌─────────────────────────────────────────┐
│ 14:32:07   "תזכיר לי לקנות חלב"          │  ← collapsed (today)
│ [reminder] → [reminderAgent] → 180ms     │
├─────────────────────────────────────────┤
│ ▾ expanded adds:                         │
│   מועמדים: [reminder] [memory]           │
│   ⚠ עמום        מצב ניתוב: keyword       │
└─────────────────────────────────────────┘
```

- `candidates` is `JSON.parse(t.candidates || '[]')` → rendered as small badge chips (reuse `.badge intent` styling)
- `ambiguous === true` → red-tinted `⚠ עמום` badge
- `route_mode` → plain text tag (`keyword` or `llm`)
- If `candidates` has ≤1 entry and `ambiguous` is false, skip the expand affordance entirely (nothing new to show) — entry stays collapsed-only, no click cursor change
- Click behavior: keep the existing `onclick="this.classList.toggle('sel')"` but rename the toggled class usage to also flip `max-height` via `.trace-entry.expanded` (only added to entries that have expandable content)

```css
.trace-entry { max-height:52px; overflow:hidden; transition:max-height .2s ease; }
.trace-entry.expandable { cursor:pointer; }
.trace-entry.expanded { max-height:140px; }
```

### 3.2 Search/filter bar on trace list

New sticky `.sec-head` above `#traceList`:

```html
<div class="sec-head" style="display:flex;gap:8px;align-items:center;padding:6px 0">
  <input id="traceSearch" placeholder="חיפוש בהיסטוריית ניתוב..." oninput="renderTrace()">
  <span id="traceFilterPill" style="display:none" onclick="clearTraceFilter()"></span>
</div>
```

`renderTrace()` reads `document.getElementById('traceSearch').value.trim().toLowerCase()` and filters `entries` by substring match on `input`/`agent`/`intent` before slicing to 50. Pure client-side, no new API calls — `S.trace` and `S.log` are already loaded in full by `loadThinking()`.

### 3.3 Donut → trace list cross-filter

Clicking a `donutSvg` wedge sets `S.traceIntentFilter = intent` (toggle off if same intent clicked again) and calls `renderTrace()`, which additionally filters `entries` to `e.intent === S.traceIntentFilter` when set. A pill appears next to the search box: `מציג: reminder — נקה ✕` (`#traceFilterPill`), click clears the filter. This mirrors the existing `setHighlight`/focus-pill pattern already used in the constellation graph (`S.highlight` + `#focusPill`) — same interaction shape, new state variable.

Hovering a wedge (independent of click) shows a tooltip via `showChartTip()`: `"{intent}\n{count} פעמים ({pct}%)"`.

### 3.4 Agent bars + pulse — hover tooltips only

No filtering needed here (bars already show one agent each; pulse is a single time series). Add `pointermove` per `.bar-row` (tooltip: `"{agent}\nממוצע {avg}ms, {count} קריאות"`) and a hit-test on `#pulseSvg` polyline points (tooltip: `"{time-bucket}\n{count} פעולות"`).

### 3.5 Provider status tooltips

`/health/providers` returns a flat map of `providerName → statusString`, where `statusString` is `"ok"`, `"missing key"`, or an error detail (e.g. `"error 429: rate limited"`) — **not** a latency number. Hovering a `.prov-dot` shows that raw string via `showChartTip()`. No claim of numeric latency; this is a status detail, matching the "honesty over fake %" principle already applied to decision-trace confidence.

---

## 4. פרופיל Tab

### 4.1 New card: שיפור שבועי (Weekly Score)

A 5th `.pc` card, placed after the existing heatmap/learn-curve card, backed by `GET /stats/weekly-score?weeks=6`:

```
┌────────────────────────────┐
│ שיפור שבועי                │
│  87%              ▁▃▅▇▆█   │  ← current score + 6-week sparkline
│  23 👍 / 3 👎               │
└────────────────────────────┘
```

- Big number = current week's `score` (the last entry in `history`), or `"אין נתונים"` if `score === null` (zero feedback this week — do not show `0%`, which would misleadingly imply negative feedback)
- Sparkline: 6 points from `history[].score`, skipping/gap-rendering `null` weeks (draw as a break in the line, not a zero-height point) — same SVG sparkline technique as Knowledge tab's cluster cards
- Below: `{ups} 👍 / {downs} 👎` from the latest week's entry
- Fetched once in `loadProfile()` alongside the existing `Promise.all([api('/stats'), api('/user-profile')...])` calls — add `api('/stats/weekly-score?weeks=6')` to that batch

### 4.2 Hover tooltips

| Chart | Hover target | Tooltip content |
|---|---|---|
| Radar (`drawRadar`) | each vertex circle | axis label + raw underlying value (e.g. `"זיכרון\n32 זיכרונות"` — reuse the same raw counts already computed in `renderProfile()` before normalization to 0–1) |
| Clock (`drawClock`) | each hour wedge | `"{h}:00\n{count} פעולות"` |
| Heatmap (`drawHeatmap`) | each `.heat-cell` | `"{date}\n{count} פעולות"` (date formatted `DD/MM`) |
| Learn curve (`drawLearnTimeline`) | each point | `"שבוע {n}\n{count} זיכרונות"` |
| Weekly score sparkline | each point | `"{weekLabel}\nציון: {score ?? '—'}"` |

All hit-testing uses the same pointer-to-nearest-element approach as the constellation tooltip (`showGraphTooltip`) — store each element's screen coordinates in an array when drawing, then on `pointermove` find the nearest one within a threshold radius.

### 4.3 Heatmap cell click → day filter

Clicking a `.heat-cell` sets `S.profileDayFilter = dateKey` (toggle off on repeat click) and shows/hides a `.day-filter-pill` element placed below the heatmap: `"פעילות ב-{date}: 2 זיכרונות, 1 הודעה — נקה ✕"` (derived by filtering `S.memories`/`S.log` client-side to that date — no new fetch). Clicking the pill itself clears `S.profileDayFilter` and hides it. This is a lightweight in-tab detail reveal, not a cross-tab jump (heatmap and trace list live on different tabs).

---

## 5. CSS Additions Summary

```css
.chart-tip { position:fixed; z-index:200; background:var(--card); border:1px solid var(--border);
  border-radius:var(--r6); padding:5px 9px; font-size:var(--tx-xs); color:var(--fg);
  pointer-events:none; white-space:pre-line; box-shadow:0 4px 12px rgba(0,0,0,.3); }

.trace-entry { max-height:52px; overflow:hidden; transition:max-height .2s ease; }
.trace-entry.expandable { cursor:pointer; }
.trace-entry.expanded { max-height:140px; }

#traceFilterPill, .day-filter-pill { cursor:pointer; font-size:var(--tx-xs); color:var(--amber);
  background:rgba(200,145,58,.1); border:1px solid rgba(200,145,58,.35); border-radius:var(--r2);
  padding:2px 8px; }
```

---

## 6. What Does NOT Change

- `loadThinking()`, `loadProfile()`, `renderProviders()`, `drawRadar()`, `drawClock()`, `drawHeatmap()`, `drawLearnTimeline()`, `renderDonut()`, `renderAgentBars()`, `renderPulse()`, `renderSparklines()` — all extended in place, not replaced
- All existing server endpoints unchanged; one new endpoint call added (`/stats/weekly-score?weeks=6`, already implemented in `server.js:1636`)
- Constellation tab — untouched (separate spec for graph physics/animation)
- Knowledge tab — untouched (already shipped as v2)
- No changes to intent routing, decision-trace writing, or any backend logic

---

## 7. File Impact

Single file: `jarvis-brain.html`

Estimated additions: ~230 lines (shared tooltip helper, trace expand + candidates rendering, search/filter bar, donut cross-filter, provider tooltips, weekly-score card + fetch, 4 chart tooltip wire-ups, heatmap day-filter)
Estimated removals: ~0 lines (purely additive — no existing markup removed)
Net: ~+230 lines

---

## 8. Out of Scope

- Constellation graph physics/animation (momentum drag, real 3D node physics, click pulse, entrance animation) — separate spec, built next
- Cross-tab filtering (e.g. clicking a heatmap cell in פרופיל does not jump to or filter חשיבה's trace list)
- Persisting filter/search state across page reloads or tab switches
- New backend endpoints or schema changes — this spec only consumes existing APIs
- LLM-based analysis of trace patterns (e.g. "why was this ambiguous" explanations beyond the raw `candidates`/`route_mode` data)
