# Thinking + Profile Tabs v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the חשיבה (Thinking) and פרופיל (Profile) tabs in `jarvis-brain.html` to the same interactivity level as Knowledge Tab v2 — expandable decision-trace entries, a trace search/filter bar, donut-driven cross-filtering, hover tooltips on every chart, and a new weekly-score card backed by a previously-unused endpoint.

**Architecture:** All changes are in a single file (`jarvis-brain.html`). No new server endpoints — `/stats/weekly-score?weeks=6` already exists (`server.js:1636`) but isn't called by this file yet. Existing JS functions (`renderTrace`, `renderProviders`, `renderProfile`, `renderDonut`, `renderAgentBars`, `renderPulse`, `drawRadar`, `drawClock`, `drawHeatmap`, `drawLearnTimeline`, `loadStats`) are extended in place. New functions added: `showChartTip`/`hideChartTip` (shared tooltip helper), `clearTraceFilter`, `renderWeeklyScore`, `renderDayFilterPill`, `clearDayFilter`.

**Tech Stack:** Vanilla JS, SVG, CSS grid, no external libraries. Single file edit only.

---

## File Map

| File | Change |
|------|--------|
| `jarvis-brain.html:143-148` | (reference only, unchanged) existing `.badge` classes reused for candidate chips |
| `jarvis-brain.html:169` | Modify `.profile-layout` — add third grid row for the new weekly-score card |
| `jarvis-brain.html:292-299` | Modify mobile `.profile-layout` block — add order for 5th `.pc` child |
| `jarvis-brain.html:~301` | Add new CSS block (chart tooltip, trace expand, trace search bar, filter pills, weekly-score card) |
| `jarvis-brain.html:660` | Add `.trace-search-bar` markup above `#traceList` |
| `jarvis-brain.html:653-656` | Add `data-key` attributes to `.prov-dot` elements |
| `jarvis-brain.html:723-724` | Add `#dayFilterPill` markup below `#streakRow` |
| `jarvis-brain.html:739` | Add new weekly-score `.pc.pc-wide` card after the heatmap card |
| `jarvis-brain.html:865` | Add `traceIntentFilter`, `profileDayFilter` to state object `S` |
| `jarvis-brain.html:~911` | Add `showChartTip()`, `hideChartTip()` shared helper |
| `jarvis-brain.html:958-966` | Extend `loadStats()` to also fetch `/stats/weekly-score?weeks=6` |
| `jarvis-brain.html:1171-1199` | Rewrite `renderTrace()` — candidates/ambiguous/route_mode, search filter, intent filter |
| `jarvis-brain.html:1201-1211` | Extend `renderProviders()` with hover tooltip |
| `jarvis-brain.html:1224-1232` | Extend `renderProfile()` to compute and pass `rawVals` to `drawRadar` |
| `jarvis-brain.html:1780-1811` | Extend `renderDonut()` — click cross-filter + hover tooltip |
| `jarvis-brain.html:1813-1836` | Extend `renderAgentBars()` with hover tooltip |
| `jarvis-brain.html:1838-1861` | Extend `renderPulse()` with hover tooltip |
| `jarvis-brain.html:1889-1905` | Extend `drawRadar()` with hover tooltip |
| `jarvis-brain.html:1907-1928` | Extend `drawClock()` with hover tooltip |
| `jarvis-brain.html:1930-1962` | Extend `drawHeatmap()` with hover tooltip + click day-filter |
| `jarvis-brain.html:1964-1975` | Extend `drawLearnTimeline()` with hover tooltip |

---

## Task 1: CSS — Add shared tooltip, trace expand, search bar, filter pills, weekly-score card styles

**Files:**
- Modify: `jarvis-brain.html:169` (`.profile-layout`)
- Modify: `jarvis-brain.html:292-299` (mobile `.profile-layout` block)
- Modify: `jarvis-brain.html` — add new CSS block after the mobile media query block

- [ ] **Step 1: Add a third grid row to `.profile-layout`**

Find this exact line (~169):
```css
.profile-layout{flex:1;display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;overflow:hidden}
```
Replace with:
```css
.profile-layout{flex:1;display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr auto;overflow:hidden}
```

- [ ] **Step 2: Add mobile order for the 5th `.pc` child**

Find these exact lines (~296-299):
```css
  .pc:nth-child(1){order:3}
  .pc:nth-child(2){order:1}
  .pc:nth-child(3){order:4}
  .pc:nth-child(4){order:2}
}
```
Replace with:
```css
  .pc:nth-child(1){order:3}
  .pc:nth-child(2){order:1}
  .pc:nth-child(3){order:4}
  .pc:nth-child(4){order:2}
  .pc:nth-child(5){order:5}
  .pc-wide{flex-direction:column;align-items:flex-start}
}
```

- [ ] **Step 3: Add new CSS rules**

Find the exact line:
```css
/* TAB BADGE */
```
Insert the following block immediately BEFORE that line:

```css
/* Thinking + Profile v2 — shared chart tooltip */
.chart-tip{position:fixed;z-index:200;background:var(--card);border:1px solid var(--border);border-radius:var(--r4);padding:5px 9px;font-size:var(--tx-xs);color:var(--text);pointer-events:none;white-space:pre-line;box-shadow:0 4px 12px rgba(0,0,0,.3);display:none}

/* Trace entry expand (candidates / ambiguous / route_mode) */
.trace-entry.expandable{cursor:pointer;max-height:54px;overflow:hidden;transition:max-height .2s ease}
.trace-entry.expandable.expanded{max-height:160px}
.te-detail{margin-top:6px;display:flex;gap:6px;flex-wrap:wrap;align-items:center}
.te-candidates{display:flex;gap:4px;flex-wrap:wrap;align-items:center;font-size:var(--tx-xs);color:var(--muted)}

/* Trace search bar + intent filter pill */
.trace-search-bar{display:flex;gap:8px;align-items:center;padding:6px 14px;border-bottom:1px solid var(--border);flex-shrink:0}
.trace-search-bar input{flex:1;background:none;border:none;color:var(--text);font-family:inherit;font-size:var(--tx-sm);outline:none}
.trace-filter-pill{display:none;cursor:pointer;font-size:var(--tx-xs);color:var(--amber);background:rgba(200,145,58,.1);border:1px solid rgba(200,145,58,.35);border-radius:20px;padding:3px 10px;white-space:nowrap}

/* Profile: weekly score card (5th, full-width row) */
.pc-wide{grid-column:1/-1;flex-direction:row;align-items:center;gap:18px}
.ws-score{font-size:1.6rem;font-weight:800;color:var(--accent2);font-variant-numeric:tabular-nums}
.ws-sub{font-size:var(--tx-xs);color:var(--muted)}

/* Profile: heatmap day-filter pill */
.day-filter-pill{display:none;margin-bottom:6px;cursor:pointer;font-size:var(--tx-xs);color:var(--amber);background:rgba(200,145,58,.1);border:1px solid rgba(200,145,58,.35);border-radius:var(--r4);padding:4px 9px}

```

- [ ] **Step 4: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 5: Commit**
```bash
git config user.email noreply@anthropic.com && git config user.name Claude
git add jarvis-brain.html
git commit -m "style(brain): thinking+profile tabs v2 CSS — chart tooltip, trace expand, search bar, weekly-score card"
```

---

## Task 2: JS — State fields + shared chart-tooltip helper

**Files:**
- Modify: `jarvis-brain.html:861-866` (state object `S`)
- Add: `showChartTip()`, `hideChartTip()` after `isToday()`

- [ ] **Step 1: Add `traceIntentFilter` and `profileDayFilter` to state object**

Find:
```js
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
};
```
Replace with:
```js
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
  traceIntentFilter: null, profileDayFilter: null,
};
```

- [ ] **Step 2: Add the shared tooltip helper**

Find:
```js
function isToday(iso) {
  if (!iso) return false;
  const d = new Date(iso), now = new Date();
  return d.toDateString() === now.toDateString();
}
```
Insert the following block immediately AFTER that function:
```js

// ── Shared Chart Tooltip ───────────────────────────────────────────────────
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

- [ ] **Step 3: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 4: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): shared chart-tooltip helper + trace/profile filter state"
```

---

## Task 3: HTML — Trace search bar + filter pill markup

**Files:**
- Modify: `jarvis-brain.html:653-660` (`panel-thinking`)

- [ ] **Step 1: Add `data-key` attributes to provider dots and the search bar above the trace list**

Find this exact block (~653-660):
```html
        <div class="prov-item"><div class="prov-dot off" id="prov-groq"></div>Groq</div>
        <div class="prov-item"><div class="prov-dot off" id="prov-deepseek"></div>DeepSeek</div>
        <div class="prov-item"><div class="prov-dot off" id="prov-gemini"></div>Gemini</div>
        <div class="prov-item"><div class="prov-dot off" id="prov-ollama"></div>Ollama</div>
        <div style="flex:1"></div>
        <span style="font-size:var(--tx-xs);color:var(--muted);display:flex;align-items:center;gap:5px">polling 8s <span class="live-dot"></span></span>
      </div>
      <div class="trace-list" id="traceList"><div class="mp-empty">טוען...</div></div>
```
Replace with:
```html
        <div class="prov-item"><div class="prov-dot off" id="prov-groq" data-key="groq"></div>Groq</div>
        <div class="prov-item"><div class="prov-dot off" id="prov-deepseek" data-key="deepseek"></div>DeepSeek</div>
        <div class="prov-item"><div class="prov-dot off" id="prov-gemini" data-key="gemini_google"></div>Gemini</div>
        <div class="prov-item"><div class="prov-dot off" id="prov-ollama" data-key="ollama"></div>Ollama</div>
        <div style="flex:1"></div>
        <span style="font-size:var(--tx-xs);color:var(--muted);display:flex;align-items:center;gap:5px">polling 8s <span class="live-dot"></span></span>
      </div>
      <div class="trace-search-bar">
        <svg class="icon icon-sm"><use href="#ic-search"/></svg>
        <input id="traceSearch" placeholder="חיפוש בהיסטוריית ניתוב..." oninput="renderTrace()">
        <span class="trace-filter-pill" id="traceFilterPill" onclick="clearTraceFilter()"></span>
      </div>
      <div class="trace-list" id="traceList"><div class="mp-empty">טוען...</div></div>
```

- [ ] **Step 2: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 3: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): thinking tab — trace search bar + provider tooltip data hooks"
```

---

## Task 4: JS — `renderTrace()` rewrite (candidates / ambiguous / route_mode, search, intent filter)

**Files:**
- Modify: `jarvis-brain.html:1171-1199` (`renderTrace`)
- Add: `clearTraceFilter()` immediately after

- [ ] **Step 1: Replace `renderTrace()`**

Find the entire function:
```js
function renderTrace() {
  const el = document.getElementById('traceList');
  if (!S.trace.length && !S.log.length) { el.innerHTML = '<div class="mp-empty">אין נתוני חשיבה</div>'; return; }

  // Merge trace + log, deduplicate by closest time
  const entries = S.trace.map(t => ({
    time: fmtTime(t.created_at),
    input: t.input || '—',
    intent: t.intent,
    agent: t.agent,
    ms: S.log.find(l => l.agent === t.agent && Math.abs(new Date(l.created_at) - new Date(t.created_at)) < 5000)?.duration_ms || t.duration_ms,
  }));

  el.innerHTML = entries.slice(0, 50).map((e, i) => {
    const ms = e.ms || 0;
    const msCls = ms > 800 ? 'bad' : ms > 400 ? 'warn' : '';
    return `<div class="trace-entry${i === 0 ? ' new-entry sel' : ''}" onclick="this.classList.toggle('sel')">
      <div class="te-time">${esc(e.time)}</div>
      <div class="te-body">
        <div class="te-input">${esc(e.input)}</div>
        <div class="te-tags">
          ${e.intent ? `<span class="badge intent">${esc(e.intent)}</span><span class="te-arr">→</span>` : ''}
          ${e.agent ? `<span class="badge agent">${esc(e.agent)}</span>` : ''}
          ${ms ? `<span class="te-arr">→</span><span class="badge ms ${msCls}">${ms}ms</span>` : ''}
        </div>
      </div>
    </div>`;
  }).join('');
}
```
Replace with:
```js
function renderTrace() {
  const el = document.getElementById('traceList');
  if (!S.trace.length && !S.log.length) { el.innerHTML = '<div class="mp-empty">אין נתוני חשיבה</div>'; return; }

  const q = (document.getElementById('traceSearch')?.value || '').trim().toLowerCase();

  // Merge trace + log, deduplicate by closest time
  let entries = S.trace.map(t => {
    let candidates = [];
    try { candidates = JSON.parse(t.candidates || '[]'); } catch (e) { candidates = []; }
    return {
      time: fmtTime(t.created_at),
      input: t.input || '—',
      intent: t.intent,
      agent: t.agent,
      ms: S.log.find(l => l.agent === t.agent && Math.abs(new Date(l.created_at) - new Date(t.created_at)) < 5000)?.duration_ms || t.duration_ms,
      candidates,
      ambiguous: !!t.ambiguous,
      routeMode: t.route_mode || '',
    };
  });

  if (S.traceIntentFilter) entries = entries.filter(e => e.intent === S.traceIntentFilter);
  if (q) entries = entries.filter(e =>
    e.input.toLowerCase().includes(q) || (e.agent || '').toLowerCase().includes(q) || (e.intent || '').toLowerCase().includes(q)
  );

  const pill = document.getElementById('traceFilterPill');
  if (pill) {
    if (S.traceIntentFilter) {
      pill.style.display = 'inline-block';
      pill.textContent = `מציג: ${S.traceIntentFilter} — נקה ✕`;
    } else {
      pill.style.display = 'none';
    }
  }

  if (!entries.length) { el.innerHTML = '<div class="mp-empty">אין תוצאות</div>'; return; }

  el.innerHTML = entries.slice(0, 50).map((e, i) => {
    const ms = e.ms || 0;
    const msCls = ms > 800 ? 'bad' : ms > 400 ? 'warn' : '';
    const expandable = e.ambiguous || e.candidates.length > 1;
    const detail = expandable ? `
        <div class="te-detail">
          ${e.candidates.length > 1 ? `<div class="te-candidates">מועמדים: ${e.candidates.map(c => `<span class="badge intent">${esc(c)}</span>`).join(' ')}</div>` : ''}
          ${e.ambiguous ? `<span class="badge ms bad">⚠ עמום</span>` : ''}
          ${e.routeMode ? `<span class="badge ms">מצב ניתוב: ${esc(e.routeMode)}</span>` : ''}
        </div>` : '';
    return `<div class="trace-entry${expandable ? ' expandable' : ''}${i === 0 ? ' new-entry sel' : ''}" onclick="this.classList.toggle('sel');this.classList.toggle('expanded')">
      <div class="te-time">${esc(e.time)}</div>
      <div class="te-body">
        <div class="te-input">${esc(e.input)}</div>
        <div class="te-tags">
          ${e.intent ? `<span class="badge intent">${esc(e.intent)}</span><span class="te-arr">→</span>` : ''}
          ${e.agent ? `<span class="badge agent">${esc(e.agent)}</span>` : ''}
          ${ms ? `<span class="te-arr">→</span><span class="badge ms ${msCls}">${ms}ms</span>` : ''}
        </div>
        ${detail}
      </div>
    </div>`;
  }).join('');
}

function clearTraceFilter() {
  S.traceIntentFilter = null;
  renderDonut();
  renderTrace();
}
```

- [ ] **Step 2: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 3: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): thinking tab — expandable trace entries (candidates/ambiguous/route_mode) + search filter"
```

---

## Task 5: JS — `renderDonut()` rewrite (click cross-filter + hover tooltip)

**Files:**
- Modify: `jarvis-brain.html:1780-1811` (`renderDonut`)

- [ ] **Step 1: Replace `renderDonut()`**

Find the entire function:
```js
function renderDonut() {
  const svg = document.getElementById('donutSvg');
  const legendEl = document.getElementById('donutLegend');
  if (!svg || !S.trace.length) return;

  const counts = {};
  S.trace.forEach(t => { counts[t.intent] = (counts[t.intent] || 0) + 1; });
  const total = S.trace.length;
  const intColors = ['#60a5fa', '#22c55e', '#f59e0b', '#C8913A', '#a78bfa'];
  const top = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 4);
  const data = top.map(([intent, v], i) => ({ v, c: intColors[i], label: intent }));
  const sum = data.reduce((s, d) => s + d.v, 0);

  const cx = 36, cy = 36, R = 28, r = 17;
  let angle = -Math.PI / 2, h = '';
  data.forEach(d => {
    const a = 2 * Math.PI * d.v / sum;
    const x1 = cx + R * Math.cos(angle), y1 = cy + R * Math.sin(angle);
    const x2 = cx + R * Math.cos(angle + a), y2 = cy + R * Math.sin(angle + a);
    const x3 = cx + r * Math.cos(angle + a), y3 = cy + r * Math.sin(angle + a);
    const x4 = cx + r * Math.cos(angle), y4 = cy + r * Math.sin(angle);
    const lg = a > Math.PI ? 1 : 0;
    h += `<path d="M${x1.toFixed(1)},${y1.toFixed(1)} A${R},${R} 0 ${lg},1 ${x2.toFixed(1)},${y2.toFixed(1)} L${x3.toFixed(1)},${y3.toFixed(1)} A${r},${r} 0 ${lg},0 ${x4.toFixed(1)},${y4.toFixed(1)} Z" fill="${d.c}" opacity=".88"/>`;
    angle += a;
  });
  if (top[0]) h += `<text x="${cx}" y="${cy+3}" text-anchor="middle" font-size="7.5" fill="rgba(224,212,190,.7)" font-family="Heebo" font-weight="700">${top[0][0]}</text>`;
  svg.innerHTML = h;

  legendEl.innerHTML = data.map(d =>
    `<div class="dl-row"><div class="dl-dot" style="background:${d.c}"></div><span class="dl-val">${Math.round(d.v / sum * 100)}%</span> ${esc(d.label)}</div>`
  ).join('');
}
```
Replace with:
```js
function renderDonut() {
  const svg = document.getElementById('donutSvg');
  const legendEl = document.getElementById('donutLegend');
  if (!svg || !S.trace.length) return;

  const counts = {};
  S.trace.forEach(t => { counts[t.intent] = (counts[t.intent] || 0) + 1; });
  const total = S.trace.length;
  const intColors = ['#60a5fa', '#22c55e', '#f59e0b', '#C8913A', '#a78bfa'];
  const top = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 4);
  const data = top.map(([intent, v], i) => ({ v, c: intColors[i], label: intent }));
  const sum = data.reduce((s, d) => s + d.v, 0);

  const cx = 36, cy = 36, R = 28, r = 17;
  let angle = -Math.PI / 2, h = '';
  data.forEach(d => {
    const a = 2 * Math.PI * d.v / sum;
    const x1 = cx + R * Math.cos(angle), y1 = cy + R * Math.sin(angle);
    const x2 = cx + R * Math.cos(angle + a), y2 = cy + R * Math.sin(angle + a);
    const x3 = cx + r * Math.cos(angle + a), y3 = cy + r * Math.sin(angle + a);
    const x4 = cx + r * Math.cos(angle), y4 = cy + r * Math.sin(angle);
    const lg = a > Math.PI ? 1 : 0;
    const pct = Math.round(d.v / sum * 100);
    const dimmed = S.traceIntentFilter && S.traceIntentFilter !== d.label;
    h += `<path data-intent="${esc(d.label)}" data-count="${d.v}" data-pct="${pct}" d="M${x1.toFixed(1)},${y1.toFixed(1)} A${R},${R} 0 ${lg},1 ${x2.toFixed(1)},${y2.toFixed(1)} L${x3.toFixed(1)},${y3.toFixed(1)} A${r},${r} 0 ${lg},0 ${x4.toFixed(1)},${y4.toFixed(1)} Z" fill="${d.c}" opacity="${dimmed ? .25 : .88}" style="cursor:pointer"/>`;
    angle += a;
  });
  if (top[0]) h += `<text x="${cx}" y="${cy+3}" text-anchor="middle" font-size="7.5" fill="rgba(224,212,190,.7)" font-family="Heebo" font-weight="700">${top[0][0]}</text>`;
  svg.innerHTML = h;

  svg.onclick = e => {
    const p = e.target.closest('[data-intent]');
    if (!p) return;
    const intent = p.dataset.intent;
    S.traceIntentFilter = S.traceIntentFilter === intent ? null : intent;
    renderDonut();
    renderTrace();
  };
  svg.onpointermove = e => {
    const p = e.target.closest('[data-intent]');
    if (!p) { hideChartTip(); return; }
    showChartTip(`${p.dataset.intent}\n${p.dataset.count} פעמים (${p.dataset.pct}%)`, e.clientX, e.clientY);
  };
  svg.onpointerleave = () => hideChartTip();

  legendEl.innerHTML = data.map(d =>
    `<div class="dl-row"><div class="dl-dot" style="background:${d.c}"></div><span class="dl-val">${Math.round(d.v / sum * 100)}%</span> ${esc(d.label)}</div>`
  ).join('');
}
```

- [ ] **Step 2: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 3: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): thinking tab — donut wedge click cross-filters trace list + hover tooltip"
```

---

## Task 6: JS — Agent bars, pulse, and provider-dot hover tooltips

**Files:**
- Modify: `jarvis-brain.html:1201-1211` (`renderProviders`)
- Modify: `jarvis-brain.html:1813-1836` (`renderAgentBars`)
- Modify: `jarvis-brain.html:1838-1861` (`renderPulse`)

- [ ] **Step 1: Add hover tooltip to `renderProviders()`**

Find the entire function:
```js
function renderProviders() {
  const map = {
    groq: 'prov-groq', deepseek: 'prov-deepseek',
    gemini_google: 'prov-gemini', ollama: 'prov-ollama',
  };
  for (const [key, elId] of Object.entries(map)) {
    const el = document.getElementById(elId);
    if (!el) continue;
    el.className = 'prov-dot ' + (S.providers[key] ? 'ok' : 'off');
  }
}
```
Replace with:
```js
function renderProviders() {
  const map = {
    groq: 'prov-groq', deepseek: 'prov-deepseek',
    gemini_google: 'prov-gemini', ollama: 'prov-ollama',
  };
  for (const [key, elId] of Object.entries(map)) {
    const el = document.getElementById(elId);
    if (!el) continue;
    el.className = 'prov-dot ' + (S.providers[key] ? 'ok' : 'off');
  }
  const bar = document.querySelector('.prov-bar');
  if (bar) {
    bar.onpointermove = e => {
      const dot = e.target.closest('[data-key]');
      if (!dot) { hideChartTip(); return; }
      showChartTip(S.providers[dot.dataset.key] || 'אין נתונים', e.clientX, e.clientY);
    };
    bar.onpointerleave = () => hideChartTip();
  }
}
```

- [ ] **Step 2: Add hover tooltip to `renderAgentBars()`**

Find the entire function:
```js
function renderAgentBars() {
  const el = document.getElementById('agentBars');
  if (!el || !S.log.length) return;
  const byAgent = {};
  S.log.forEach(l => {
    if (!l.agent) return;
    if (!byAgent[l.agent]) byAgent[l.agent] = { total: 0, count: 0 };
    byAgent[l.agent].total += l.duration_ms || 0;
    byAgent[l.agent].count++;
  });
  const rows = Object.entries(byAgent)
    .map(([agent, { total, count }]) => ({ agent: agent.replace('Agent', ''), avg: Math.round(total / count) }))
    .sort((a, b) => b.avg - a.avg).slice(0, 5);
  const maxMs = rows[0]?.avg || 1;
  const barColors = ['#ef4444', '#f59e0b', '#60a5fa', '#22c55e', '#C8913A'];
  el.innerHTML = rows.map((r, i) => {
    const pct = Math.round(r.avg / maxMs * 100);
    return `<div class="bar-row">
      <div class="bar-label">${esc(r.agent)}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${barColors[i]}"></div></div>
      <div class="bar-count">${r.avg}ms</div>
    </div>`;
  }).join('');
}
```
Replace with:
```js
function renderAgentBars() {
  const el = document.getElementById('agentBars');
  if (!el || !S.log.length) return;
  const byAgent = {};
  S.log.forEach(l => {
    if (!l.agent) return;
    if (!byAgent[l.agent]) byAgent[l.agent] = { total: 0, count: 0 };
    byAgent[l.agent].total += l.duration_ms || 0;
    byAgent[l.agent].count++;
  });
  const rows = Object.entries(byAgent)
    .map(([agent, { total, count }]) => ({ agent: agent.replace('Agent', ''), avg: Math.round(total / count), count }))
    .sort((a, b) => b.avg - a.avg).slice(0, 5);
  const maxMs = rows[0]?.avg || 1;
  const barColors = ['#ef4444', '#f59e0b', '#60a5fa', '#22c55e', '#C8913A'];
  el.innerHTML = rows.map((r, i) => {
    const pct = Math.round(r.avg / maxMs * 100);
    return `<div class="bar-row" data-agent="${esc(r.agent)}" data-avg="${r.avg}" data-count="${r.count}">
      <div class="bar-label">${esc(r.agent)}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${barColors[i]}"></div></div>
      <div class="bar-count">${r.avg}ms</div>
    </div>`;
  }).join('');

  el.onpointermove = e => {
    const row = e.target.closest('.bar-row');
    if (!row) { hideChartTip(); return; }
    showChartTip(`${row.dataset.agent}\nממוצע ${row.dataset.avg}ms, ${row.dataset.count} קריאות`, e.clientX, e.clientY);
  };
  el.onpointerleave = () => hideChartTip();
}
```

- [ ] **Step 3: Add hover tooltip to `renderPulse()`**

Find the last three lines of the function:
```js
  h += `<circle cx="${lx.toFixed(1)}" cy="${ly.toFixed(1)}" r="7" fill="none" stroke="#e0b86a" stroke-width=".8" opacity=".4"/>`;
  svg.innerHTML = h; svg.setAttribute('width', W); svg.setAttribute('height', H);
}
```
Replace with:
```js
  h += `<circle cx="${lx.toFixed(1)}" cy="${ly.toFixed(1)}" r="7" fill="none" stroke="#e0b86a" stroke-width=".8" opacity=".4"/>`;
  svg.innerHTML = h; svg.setAttribute('width', W); svg.setAttribute('height', H);

  svg.onpointermove = e => {
    const rect = svg.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const idx = Math.max(0, Math.min(data.length - 1, Math.round((mx - 10) / step)));
    const secondsAgo = (data.length - 1 - idx) * 3;
    showChartTip(`לפני ${secondsAgo}-${secondsAgo + 3} שנ'\n${data[idx]} פעולות`, e.clientX, e.clientY);
  };
  svg.onpointerleave = () => hideChartTip();
}
```

- [ ] **Step 4: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 5: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): thinking tab — hover tooltips for provider dots, agent bars, activity pulse"
```

---

## Task 7: HTML + JS — Weekly score profile card

**Files:**
- Modify: `jarvis-brain.html:739` (`panel-profile` — add 5th `.pc` card)
- Modify: `jarvis-brain.html:958-966` (`loadStats`)
- Add: `renderWeeklyScore()` function after `loadStats()`

- [ ] **Step 1: Add the weekly-score card markup**

Find this exact closing sequence (~735-741):
```html
      <div style="margin-top:9px">
        <div class="sc-head" style="margin-bottom:5px"><svg class="icon icon-sm"><use href="#ic-chart"/></svg> ציר למידה — זיכרונות לפי שבוע</div>
        <svg id="learnSvg" width="100%" height="48"></svg>
      </div>
    </div>
  </div>
</div>

<!-- ══ TAB 4: KNOWLEDGE ══ -->
```
Replace with:
```html
      <div style="margin-top:9px">
        <div class="sc-head" style="margin-bottom:5px"><svg class="icon icon-sm"><use href="#ic-chart"/></svg> ציר למידה — זיכרונות לפי שבוע</div>
        <svg id="learnSvg" width="100%" height="48"></svg>
      </div>
    </div>
    <div class="pc pc-wide" style="border-bottom:none;border-top:1px solid var(--border)">
      <div class="pc-head"><svg class="icon icon-sm"><use href="#ic-chart"/></svg> שיפור שבועי</div>
      <div>
        <div class="ws-score" id="wsScore">—</div>
        <div class="ws-sub" id="wsSub">—</div>
      </div>
      <svg id="wsSpark" width="120" height="34"></svg>
    </div>
  </div>
</div>

<!-- ══ TAB 4: KNOWLEDGE ══ -->
```

- [ ] **Step 2: Fetch weekly-score history in `loadStats()`**

Find:
```js
async function loadStats() {
  try {
    const [st, prof] = await Promise.all([api('/stats'), api('/user-profile').catch(() => ({}))]);
    S.stats = st || {};
    S.profile = prof || {};
    updateProfileKpi();
    renderProfile();
  } catch (e) { console.warn('stats:', e); }
}
```
Replace with:
```js
async function loadStats() {
  try {
    const [st, prof, ws] = await Promise.all([
      api('/stats'),
      api('/user-profile').catch(() => ({})),
      api('/stats/weekly-score?weeks=6').catch(() => ({ history: [] })),
    ]);
    S.stats = st || {};
    S.profile = prof || {};
    updateProfileKpi();
    renderProfile();
    renderWeeklyScore(ws.history || []);
  } catch (e) { console.warn('stats:', e); }
}
```

- [ ] **Step 3: Add `renderWeeklyScore()`**

Find the line immediately after `loadStats()` closes:
```js
async function reload() {
```
Insert immediately before it:
```js
function renderWeeklyScore(history) {
  const svg = document.getElementById('wsSpark');
  const scoreEl = document.getElementById('wsScore');
  const subEl = document.getElementById('wsSub');
  if (!svg || !scoreEl || !subEl) return;
  if (!history.length) { scoreEl.textContent = '—'; subEl.textContent = 'אין נתונים'; svg.innerHTML = ''; return; }

  const last = history[history.length - 1];
  scoreEl.textContent = last.score === null ? 'אין נתונים' : last.score + '%';
  subEl.textContent = `${last.ups} 👍 / ${last.downs} 👎`;

  const W = 120, H = 34, pad = 4;
  const scoredVals = history.filter(h => h.score !== null).map(h => h.score);
  const maxV = Math.max(...scoredVals, 1), minV = Math.min(...scoredVals, 0);
  const range = Math.max(1, maxV - minV);
  const step = (W - pad * 2) / Math.max(1, history.length - 1);

  const segments = [];
  let current = [];
  history.forEach((pt, i) => {
    if (pt.score === null) {
      if (current.length) segments.push(current);
      current = [];
    } else {
      const x = pad + i * step;
      const y = H - pad - ((pt.score - minV) / range) * (H - pad * 2);
      current.push(`${x.toFixed(1)},${y.toFixed(1)}`);
    }
  });
  if (current.length) segments.push(current);

  svg.innerHTML = segments.map(seg =>
    `<polyline points="${seg.join(' ')}" fill="none" stroke="#C8913A" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`
  ).join('');

  svg.onpointermove = e => {
    const rect = svg.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const idx = Math.max(0, Math.min(history.length - 1, Math.round((x - pad) / step)));
    const pt = history[idx];
    showChartTip(`${pt.label}\nציון: ${pt.score === null ? '—' : pt.score + '%'}`, e.clientX, e.clientY);
  };
  svg.onpointerleave = () => hideChartTip();
}

```

- [ ] **Step 4: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 5: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): profile tab — weekly score card backed by /stats/weekly-score"
```

---

## Task 8: JS — Radar, clock, and learning-curve hover tooltips

**Files:**
- Modify: `jarvis-brain.html:1224-1232` (`renderProfile` — compute raw values)
- Modify: `jarvis-brain.html:1889-1905` (`drawRadar`)
- Modify: `jarvis-brain.html:1907-1928` (`drawClock`)
- Modify: `jarvis-brain.html:1964-1975` (`drawLearnTimeline`)

- [ ] **Step 1: Compute raw values in `renderProfile()` and pass them to `drawRadar`**

Find:
```js
  // Radar
  const usage = S.stats.agentUsage || {};
  const total = Math.max(1, S.stats.totalMessages || 1);
  const vals = [
    Math.min(1, S.memories.length / 50),
    Math.min(1, (usage.chatAgent || 0) / total * 4),
    Math.min(1, (usage.taskAgent || 0) / Math.max(1, (usage.taskAgent || 0) + 3)),
    Math.min(1, (usage.reminderAgent || 0) / Math.max(1, (usage.reminderAgent || 0) + 3)),
    Math.min(1, Object.keys(usage).length / 10),
    Math.min(1, S.log.length / 100),
  ];
  drawRadar(vals);
```
Replace with:
```js
  // Radar
  const usage = S.stats.agentUsage || {};
  const total = Math.max(1, S.stats.totalMessages || 1);
  const vals = [
    Math.min(1, S.memories.length / 50),
    Math.min(1, (usage.chatAgent || 0) / total * 4),
    Math.min(1, (usage.taskAgent || 0) / Math.max(1, (usage.taskAgent || 0) + 3)),
    Math.min(1, (usage.reminderAgent || 0) / Math.max(1, (usage.reminderAgent || 0) + 3)),
    Math.min(1, Object.keys(usage).length / 10),
    Math.min(1, S.log.length / 100),
  ];
  const rawVals = [
    S.memories.length,
    usage.chatAgent || 0,
    usage.taskAgent || 0,
    usage.reminderAgent || 0,
    Object.keys(usage).length,
    S.log.length,
  ];
  drawRadar(vals, rawVals);
```

- [ ] **Step 2: Add hover tooltip to `drawRadar()`**

Find the entire function:
```js
function drawRadar(vals) {
  const svg = document.getElementById('radarSvg');
  if (!svg) return;
  const axes = ['זיכרון', 'שיחות', 'משימות', 'תזכורות', 'סוכנים', 'פעילות'];
  const cx = 82, cy = 82, R = 65, angle = i => (2 * Math.PI * i / 6) - Math.PI / 2;
  let h = '';
  [.25, .5, .75, 1].forEach(f => {
    const pts = axes.map((_, i) => `${(cx + R * f * Math.cos(angle(i))).toFixed(1)},${(cy + R * f * Math.sin(angle(i))).toFixed(1)}`).join(' ');
    h += `<polygon points="${pts}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="1"/>`;
  });
  axes.forEach((_, i) => { h += `<line x1="${cx}" y1="${cy}" x2="${(cx + R * Math.cos(angle(i))).toFixed(1)}" y2="${(cy + R * Math.sin(angle(i))).toFixed(1)}" stroke="rgba(255,255,255,.07)" stroke-width="1"/>`; });
  const dpts = vals.map((v, i) => `${(cx + R * v * Math.cos(angle(i))).toFixed(1)},${(cy + R * v * Math.sin(angle(i))).toFixed(1)}`).join(' ');
  h += `<polygon points="${dpts}" fill="rgba(200,145,58,.13)" stroke="#C8913A" stroke-width="1.8"/>`;
  vals.forEach((v, i) => { h += `<circle cx="${(cx + R * v * Math.cos(angle(i))).toFixed(1)}" cy="${(cy + R * v * Math.sin(angle(i))).toFixed(1)}" r="3" fill="#e0b86a"/>`; });
  axes.forEach((l, i) => { h += `<text x="${(cx + (R + 14) * Math.cos(angle(i))).toFixed(1)}" y="${(cy + (R + 14) * Math.sin(angle(i)) + 4).toFixed(1)}" text-anchor="middle" font-size="8.5" fill="#7a8fa6" font-family="Heebo">${l}</text>`; });
  svg.innerHTML = h;
}
```
Replace with:
```js
function drawRadar(vals, rawVals) {
  const svg = document.getElementById('radarSvg');
  if (!svg) return;
  const axes = ['זיכרון', 'שיחות', 'משימות', 'תזכורות', 'סוכנים', 'פעילות'];
  const axisUnits = ['זיכרונות', 'שיחות', 'משימות', 'תזכורות', 'סוכנים פעילים', 'פעולות'];
  const cx = 82, cy = 82, R = 65, angle = i => (2 * Math.PI * i / 6) - Math.PI / 2;
  let h = '';
  [.25, .5, .75, 1].forEach(f => {
    const pts = axes.map((_, i) => `${(cx + R * f * Math.cos(angle(i))).toFixed(1)},${(cy + R * f * Math.sin(angle(i))).toFixed(1)}`).join(' ');
    h += `<polygon points="${pts}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="1"/>`;
  });
  axes.forEach((_, i) => { h += `<line x1="${cx}" y1="${cy}" x2="${(cx + R * Math.cos(angle(i))).toFixed(1)}" y2="${(cy + R * Math.sin(angle(i))).toFixed(1)}" stroke="rgba(255,255,255,.07)" stroke-width="1"/>`; });
  const dpts = vals.map((v, i) => `${(cx + R * v * Math.cos(angle(i))).toFixed(1)},${(cy + R * v * Math.sin(angle(i))).toFixed(1)}`).join(' ');
  h += `<polygon points="${dpts}" fill="rgba(200,145,58,.13)" stroke="#C8913A" stroke-width="1.8"/>`;
  const pointCoords = [];
  vals.forEach((v, i) => {
    const px = cx + R * v * Math.cos(angle(i)), py = cy + R * v * Math.sin(angle(i));
    pointCoords.push({ x: px, y: py });
    h += `<circle cx="${px.toFixed(1)}" cy="${py.toFixed(1)}" r="3" fill="#e0b86a"/>`;
  });
  axes.forEach((l, i) => { h += `<text x="${(cx + (R + 14) * Math.cos(angle(i))).toFixed(1)}" y="${(cy + (R + 14) * Math.sin(angle(i)) + 4).toFixed(1)}" text-anchor="middle" font-size="8.5" fill="#7a8fa6" font-family="Heebo">${l}</text>`; });
  svg.innerHTML = h;

  svg.onpointermove = e => {
    const rect = svg.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    let best = -1, bestD = 12;
    pointCoords.forEach((p, i) => {
      const d = Math.hypot(p.x - mx, p.y - my);
      if (d < bestD) { bestD = d; best = i; }
    });
    if (best === -1 || !rawVals) { hideChartTip(); return; }
    showChartTip(`${axes[best]}\n${rawVals[best]} ${axisUnits[best]}`, e.clientX, e.clientY);
  };
  svg.onpointerleave = () => hideChartTip();
}
```

- [ ] **Step 3: Add hover tooltip to `drawClock()`**

Find the last two lines of the function:
```js
  h += `<text x="${cx}" y="${cy + 4}" text-anchor="middle" font-size="9" fill="#e0b86a" font-family="Heebo" font-weight="700">24H</text>`;
  svg.innerHTML = h;
}
```
Replace with:
```js
  h += `<text x="${cx}" y="${cy + 4}" text-anchor="middle" font-size="9" fill="#e0b86a" font-family="Heebo" font-weight="700">24H</text>`;
  svg.innerHTML = h;

  svg.onpointermove = e => {
    const rect = svg.getBoundingClientRect();
    const mx = e.clientX - rect.left - cx, my = e.clientY - rect.top - cy;
    const dist = Math.hypot(mx, my);
    if (dist < rIn - 4 || dist > rOut + 14) { hideChartTip(); return; }
    let a = Math.atan2(my, mx) + Math.PI / 2;
    if (a < 0) a += 2 * Math.PI;
    const hourIdx = Math.floor(a / sl) % 24;
    showChartTip(`${String(hourIdx).padStart(2,'0')}:00\n${hours[hourIdx]} פעולות`, e.clientX, e.clientY);
  };
  svg.onpointerleave = () => hideChartTip();
}
```

- [ ] **Step 4: Add hover tooltip to `drawLearnTimeline()`**

Find the last two lines of the function:
```js
  data.forEach((v, i) => { if (v === maxV) { const x = 6 + i * step, y = H - 6 - (v / maxV) * (H - 14); h += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="3" fill="#e0b86a"/>`; } });
  svg.innerHTML = h; svg.setAttribute('width', W); svg.setAttribute('height', H);
}
```
Replace with:
```js
  data.forEach((v, i) => { if (v === maxV) { const x = 6 + i * step, y = H - 6 - (v / maxV) * (H - 14); h += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="3" fill="#e0b86a"/>`; } });
  svg.innerHTML = h; svg.setAttribute('width', W); svg.setAttribute('height', H);

  svg.onpointermove = e => {
    const rect = svg.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const idx = Math.max(0, Math.min(data.length - 1, Math.round((x - 6) / step)));
    const weeksAgo = data.length - 1 - idx;
    const label = weeksAgo === 0 ? 'השבוע' : `לפני ${weeksAgo} שבועות`;
    showChartTip(`${label}\n${data[idx]} זיכרונות`, e.clientX, e.clientY);
  };
  svg.onpointerleave = () => hideChartTip();
}
```

- [ ] **Step 5: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 6: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): profile tab — hover tooltips for radar, 24h clock, learning curve"
```

---

## Task 9: HTML + JS — Heatmap hover tooltip + day-filter pill

**Files:**
- Modify: `jarvis-brain.html:723-724` (`panel-profile` — add day-filter pill placeholder)
- Modify: `jarvis-brain.html:1930-1962` (`drawHeatmap`)
- Add: `renderDayFilterPill()`, `clearDayFilter()` after `drawHeatmap`

- [ ] **Step 1: Add the day-filter pill placeholder**

Find:
```html
      <div id="heatGrid" class="heatgrid" style="margin-bottom:7px"></div>
      <div id="streakRow" class="streak-row" style="margin-bottom:5px"></div>
```
Replace with:
```html
      <div id="heatGrid" class="heatgrid" style="margin-bottom:7px"></div>
      <div id="streakRow" class="streak-row" style="margin-bottom:5px"></div>
      <div id="dayFilterPill" class="day-filter-pill" onclick="clearDayFilter()"></div>
```

- [ ] **Step 2: Replace `drawHeatmap()` with hover + click support**

Find the entire function:
```js
function drawHeatmap(actByDate) {
  const g = document.getElementById('heatGrid');
  const sr = document.getElementById('streakRow');
  if (!g) return;
  g.innerHTML = ''; sr.innerHTML = '';
  const vals = [];
  for (let col = 41; col >= 0; col--) {
    for (let row = 0; row < 7; row++) {
      const d = new Date();
      d.setDate(d.getDate() - (col * 7 + row));
      const key = d.toISOString().slice(0, 10);
      vals.push(actByDate[key] || 0);
    }
  }
  const maxV = Math.max(...vals, 1);
  vals.forEach(v => {
    const alpha = v === 0 ? .04 : (.14 + .8 * v / maxV).toFixed(2);
    const el = document.createElement('div');
    el.className = 'heat-cell';
    el.style.background = `rgba(200,145,58,${alpha})`;
    g.appendChild(el);
  });
  // Last 30 days streak
  for (let i = 29; i >= 0; i--) {
    const d = new Date(); d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    const active = (actByDate[key] || 0) > 0;
    const el = document.createElement('div');
    el.className = 'streak-day';
    el.style.background = active ? 'rgba(200,145,58,.55)' : 'rgba(255,255,255,.06)';
    sr.appendChild(el);
  }
}
```
Replace with:
```js
function drawHeatmap(actByDate) {
  const g = document.getElementById('heatGrid');
  const sr = document.getElementById('streakRow');
  if (!g) return;
  g.innerHTML = ''; sr.innerHTML = '';
  const vals = [];
  for (let col = 41; col >= 0; col--) {
    for (let row = 0; row < 7; row++) {
      const d = new Date();
      d.setDate(d.getDate() - (col * 7 + row));
      const key = d.toISOString().slice(0, 10);
      vals.push({ key, v: actByDate[key] || 0 });
    }
  }
  const maxV = Math.max(...vals.map(x => x.v), 1);
  vals.forEach(({ key, v }) => {
    const alpha = v === 0 ? .04 : (.14 + .8 * v / maxV).toFixed(2);
    const el = document.createElement('div');
    el.className = 'heat-cell';
    el.style.background = `rgba(200,145,58,${alpha})`;
    el.dataset.date = key;
    el.dataset.count = v;
    g.appendChild(el);
  });
  // Last 30 days streak
  for (let i = 29; i >= 0; i--) {
    const d = new Date(); d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    const active = (actByDate[key] || 0) > 0;
    const el = document.createElement('div');
    el.className = 'streak-day';
    el.style.background = active ? 'rgba(200,145,58,.55)' : 'rgba(255,255,255,.06)';
    sr.appendChild(el);
  }

  g.onpointermove = e => {
    const cell = e.target.closest('.heat-cell');
    if (!cell) { hideChartTip(); return; }
    const label = new Date(cell.dataset.date).toLocaleDateString('he-IL', { day: 'numeric', month: 'numeric' });
    showChartTip(`${label}\n${cell.dataset.count} פעולות`, e.clientX, e.clientY);
  };
  g.onpointerleave = () => hideChartTip();
  g.onclick = e => {
    const cell = e.target.closest('.heat-cell');
    if (!cell) return;
    const key = cell.dataset.date;
    S.profileDayFilter = S.profileDayFilter === key ? null : key;
    renderDayFilterPill();
  };
}

function renderDayFilterPill() {
  const pill = document.getElementById('dayFilterPill');
  if (!pill) return;
  if (!S.profileDayFilter) { pill.style.display = 'none'; return; }
  const key = S.profileDayFilter;
  const memCount = S.memories.filter(m => m.created_at && new Date(m.created_at).toISOString().slice(0, 10) === key).length;
  const logCount = S.log.filter(l => l.created_at && new Date(l.created_at).toISOString().slice(0, 10) === key).length;
  const label = new Date(key).toLocaleDateString('he-IL', { day: 'numeric', month: 'numeric' });
  pill.textContent = `פעילות ב-${label}: ${memCount} זיכרונות, ${logCount} הודעות — נקה ✕`;
  pill.style.display = 'block';
}

function clearDayFilter() {
  S.profileDayFilter = null;
  renderDayFilterPill();
}
```

- [ ] **Step 3: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 4: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): profile tab — heatmap hover tooltip + day-filter pill"
```

---

## Task 10: Verify, push, PR

- [ ] **Step 1: Final lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 2: Grep for leftover references to confirm no dangling old code**
```bash
grep -n "drawRadar(vals)\`" jarvis-brain.html
```
Expected: no output (old single-argument call site was replaced with `drawRadar(vals, rawVals)`)

- [ ] **Step 3: Verify `loadTrace()` still calls all sub-renderers**

Confirm `loadTrace()` (~line 937) still calls: `renderTrace()`, `updateThinkingKpi()`, `renderDonut()`, `renderAgentBars()`, `renderSparklines()`, `renderPulse()`. No changes needed there — all extended functions keep the same signature except `drawRadar`, which is only called from `renderProfile()`.

- [ ] **Step 4: Push**
```bash
git push -u origin claude/control-center-tab-hz66rf
```

- [ ] **Step 5: Open PR if none exists**

Check for open PR on branch `claude/control-center-tab-hz66rf` (note: the previous PR #436 on this branch was already merged, so this will be a new PR). If none open: create draft PR via GitHub MCP with title "feat(brain): thinking + profile tabs v2 — expandable trace, cross-filtering, chart tooltips, weekly score".
