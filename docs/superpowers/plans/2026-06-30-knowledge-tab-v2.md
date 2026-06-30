# Knowledge Tab v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the ידע tab in `jarvis-brain.html` to a two-column smart layout with interactive cluster cards (mini sparklines), vertical expandable insight cards, timeline hover tooltip, memory sort controls, and a client-side duplicate-detection section.

**Architecture:** All changes are in a single file (`jarvis-brain.html`). No new server endpoints. Existing JS functions (`renderKnowledge`, `renderIdentityCard`, `renderClusters`, `renderInsights`, `drawKnowledgeTimeline`, `renderMmList`) are extended or replaced in-place. New functions added: `scanDuplicates`, `initTimelineHover`. Shared utility `HEB_STOP` (already in file at line ~1840) is reused for duplicate detection.

**Tech Stack:** Vanilla JS, SVG, CSS grid, no external libraries. Single file edit only.

---

## File Map

| File | Change |
|------|--------|
| `jarvis-brain.html:215` | Extend `.sec-head` with sticky positioning |
| `jarvis-brain.html:241-246` | Transform `.insights-scroll` / `.insight-card` to vertical height-based expand |
| `jarvis-brain.html:191-192` | Keep `.know-tab-layout` / `.know-scroll` as-is |
| `jarvis-brain.html:~367` | Add new CSS block before `</style>` |
| `jarvis-brain.html:722-806` | Restructure knowledge tab HTML to two-column layout |
| `jarvis-brain.html:812-817` | Add `mmSort: 'date'` to state object `S` |
| `jarvis-brain.html:1305-1326` | Extend `renderMmList()` with sort logic |
| `jarvis-brain.html:1404-1436` | Extend `renderIdentityCard()` with streak badge + avatar pulse |
| `jarvis-brain.html:1438-1453` | Replace `renderClusters()` with sparkline card version |
| `jarvis-brain.html:1558-1628` | Extend `drawKnowledgeTimeline()` to call `initTimelineHover()` |
| `jarvis-brain.html:~1630` | Add `initTimelineHover()`, `scanDuplicates()` functions |

---

## Task 1: CSS — Modify existing rules for vertical insights + sticky headers

**Files:**
- Modify: `jarvis-brain.html:215` (`.sec-head`)
- Modify: `jarvis-brain.html:241-246` (`.insights-scroll`, `.insight-card`, `.insight-card.expanded`)

- [ ] **Step 1: Make `.sec-head` sticky**

Find this exact line (~215):
```css
.sec-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px}
```
Replace with:
```css
.sec-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;position:sticky;top:0;z-index:5;background:var(--bg);padding:4px 0 6px;border-bottom:1px solid var(--border)}
```

- [ ] **Step 2: Convert insights from horizontal scroll to vertical stack**

Find these three lines (~241-243):
```css
.insights-scroll{display:flex;gap:7px;overflow-x:auto;padding-bottom:3px;margin-bottom:12px}
.insights-scroll::-webkit-scrollbar{height:2px}
.insights-scroll::-webkit-scrollbar-thumb{background:var(--border)}
```
Replace with:
```css
.insights-scroll{display:flex;flex-direction:column;gap:7px;margin-bottom:12px}
```

- [ ] **Step 3: Convert insight card to height-based expand**

Find (~244-246):
```css
.insight-card{flex-shrink:0;width:165px;background:var(--card);border:1px solid var(--border);border-radius:var(--r8);padding:11px 12px;cursor:pointer;transition:all .2s}
.insight-card:hover{border-color:rgba(200,145,58,.35);background:var(--surface)}
.insight-card.expanded{border-color:rgba(200,145,58,.5);background:var(--surface);width:255px}
```
Replace with:
```css
.insight-card{background:var(--card);border:1px solid var(--border);border-radius:var(--r8);padding:11px 12px;cursor:pointer;max-height:78px;overflow:hidden;transition:max-height .22s ease,border-color .15s}
.insight-card:hover{border-color:rgba(200,145,58,.35)}
.insight-card.expanded{max-height:320px;border-color:rgba(200,145,58,.5)}
```

- [ ] **Step 4: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

---

## Task 2: CSS — Add new rule block (two-column layout, cluster cards, duplicate section)

**Files:**
- Modify: `jarvis-brain.html` — add CSS block before `</style>`

- [ ] **Step 1: Add new CSS rules**

Find the exact line:
```css
@keyframes orphanPulse{0%,100%{opacity:.3}50%{opacity:.58}}
```
Insert the following block immediately AFTER that line (before `</style>`):

```css
/* Knowledge Tab v2 — two-column layout */
.know-two-col{display:grid;grid-template-columns:1fr 1fr;gap:0;margin-bottom:0}
.know-col{padding:14px;display:flex;flex-direction:column;gap:12px}
.know-col+.know-col{border-inline-start:1px solid var(--border)}
@media(max-width:767px){.know-two-col{grid-template-columns:1fr}.know-col+.know-col{border-inline-start:none;border-top:1px solid var(--border)}}

/* Cluster cards with sparklines */
.cc-cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:8px;margin-bottom:4px}
.cc-card{background:var(--card);border:1px solid var(--border);border-radius:var(--r8);padding:10px 12px;cursor:pointer;transition:transform .15s,border-color .15s;overflow:hidden;border-top:2px solid transparent;animation:cardIn .2s ease both}
.cc-card:hover{transform:translateY(-2px);border-color:rgba(200,145,58,.4)}
.cc-card-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:3px}
.cc-card-icon{font-size:14px}
.cc-card-count{font-size:.85rem;font-weight:800;font-variant-numeric:tabular-nums}
.cc-card-name{font-size:var(--tx-xs);font-weight:700;color:var(--text);margin-bottom:4px}
.cc-sparkline{margin:4px 0;display:block}
.cc-preview{font-size:.58rem;color:var(--muted);line-height:1.4;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
@keyframes cardIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}

/* Identity card — avatar pulse + streak */
.id-avatar{cursor:pointer;transition:transform .1s}
@keyframes avatarPulse{0%,100%{transform:scale(1);box-shadow:0 0 0 0 rgba(200,145,58,.4)}50%{transform:scale(1.1);box-shadow:0 0 0 8px rgba(200,145,58,0)}}
.id-avatar.pulse-anim{animation:avatarPulse .4s ease}

/* Sort controls */
.mm-sort-wrap{display:flex;gap:4px;margin-right:auto}
.mm-sort-btn{background:none;border:1px solid var(--border);border-radius:var(--r2);color:var(--muted);font-size:var(--tx-xs);padding:3px 9px;cursor:pointer;font-family:inherit;transition:all .15s;min-height:26px}
.mm-sort-btn.active,.mm-sort-btn:hover{border-color:rgba(200,145,58,.4);color:var(--accent2)}

/* Duplicate detection */
.dup-scan-btn{background:rgba(200,145,58,.1);border:1px solid rgba(200,145,58,.35);color:var(--amber);border-radius:var(--r2);padding:4px 12px;font-size:var(--tx-xs);cursor:pointer;font-family:inherit;transition:all .15s;min-height:28px}
.dup-scan-btn:hover{background:rgba(200,145,58,.2)}
.dup-pair{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;background:var(--card);border:1px solid var(--border);border-radius:var(--r8);padding:10px 12px;animation:expandIn .2s ease}
.dup-side{display:flex;flex-direction:column;gap:5px}
.dup-text{font-size:var(--tx-sm);color:var(--text);line-height:1.45;flex:1}
.dup-meta{font-size:.58rem;color:var(--muted)}
.dup-score{grid-column:1/-1;text-align:center;font-size:var(--tx-xs);color:var(--muted);border-top:1px solid var(--border);padding-top:6px;margin-top:2px}
```

- [ ] **Step 2: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 3: Commit CSS work**
```bash
git config user.email noreply@anthropic.com && git config user.name Claude
git add jarvis-brain.html
git commit -m "style(brain): knowledge tab v2 CSS — two-col layout, cluster cards, dup detection"
```

---

## Task 3: HTML — Restructure knowledge tab to two-column layout

**Files:**
- Modify: `jarvis-brain.html:722-806` (panel-knowledge content)

- [ ] **Step 1: Replace the entire knowledge tab HTML**

Find this block (starting at line ~722, ending at `</div>` that closes `panel-knowledge`):
```html
<div class="tab-panel" id="panel-knowledge">
  <div class="know-tab-layout">
    <div class="know-scroll">

      <!-- A: Identity Card -->
      <div class="identity-card">
```
(replace everything from `<div class="tab-panel" id="panel-knowledge">` through the closing `</div></div></div>` at line ~806)

Replace the entire `panel-knowledge` div with:
```html
<div class="tab-panel" id="panel-knowledge">
  <div class="know-tab-layout">
    <div class="know-scroll">

      <!-- A: Identity Card — full width -->
      <div class="identity-card">
        <div class="id-top">
          <div class="id-avatar" id="idAvatar" onclick="pulseAvatar()">?</div>
          <div class="id-meta">
            <div class="id-name" id="idName">—</div>
            <div class="id-tagline" id="idTagline">טוען פרופיל...</div>
            <div class="id-badges" id="idBadges"></div>
          </div>
        </div>
        <div class="id-stats">
          <div class="id-stat"><div class="id-stat-n" id="ids-total">—</div><div class="id-stat-l">זיכרונות</div></div>
          <div class="id-stat"><div class="id-stat-n" id="ids-cats">—</div><div class="id-stat-l">קטגוריות</div></div>
          <div class="id-stat"><div class="id-stat-n" id="ids-days">—</div><div class="id-stat-l">ימי שימוש</div></div>
          <div class="id-stat"><div class="id-stat-n" id="ids-streak" style="color:var(--amber)">—</div><div class="id-stat-l">ימים ברצף 🔥</div></div>
          <div class="id-stat"><div class="id-stat-n" id="ids-pending">—</div><div class="id-stat-l">ממתינים</div></div>
        </div>
      </div>

      <!-- Two-column body -->
      <div class="know-two-col">

        <!-- LEFT: clusters + insights -->
        <div class="know-col">
          <div>
            <div class="sec-head">
              <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-tag"/></svg> נושאים</div>
            </div>
            <div class="cc-cards" id="clustersRow"></div>
            <div class="cluster-expand" id="clusterExpand" style="display:none">
              <div class="ce-head">
                <div class="ce-title" id="ceTitle"></div>
                <button class="ce-close" onclick="closeCluster()">✕</button>
              </div>
              <div class="ce-grid" id="ceGrid"></div>
            </div>
          </div>
          <div>
            <div class="sec-head">
              <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-light"/></svg> תובנות שג׳רוויס הסיק</div>
            </div>
            <div class="insights-scroll" id="insightsScroll"></div>
          </div>
        </div>

        <!-- RIGHT: timeline + learning curve -->
        <div class="know-col">
          <div>
            <div class="sec-head">
              <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-clock"/></svg> ציר ידע — מתי למד ג׳רוויס</div>
            </div>
            <div class="timeline-wrap">
              <div class="tl-chart" id="tlChart">
                <svg class="tl-svg" id="tlSvg"></svg>
                <div class="tl-tooltip" id="tlTip"></div>
              </div>
              <div class="tl-months" id="tlMonths"></div>
            </div>
          </div>
        </div>

      </div><!-- /.know-two-col -->

      <!-- E: Memory Management — full width -->
      <div style="margin-top:16px">
        <div class="sec-head">
          <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-check"/></svg> בדיקה ואימות זיכרונות</div>
          <div style="display:flex;align-items:center;gap:5px">
            <span class="mm-stat-badge approved" id="mm-stat-approved"></span>
            <span class="mm-stat-badge pending" id="mm-stat-pending" style="display:none"></span>
          </div>
        </div>

        <!-- Pending approval sub-section -->
        <div id="mm-pending-wrap" style="display:none;margin-bottom:10px">
          <div class="mm-pend-head">
            <span class="mm-pend-title"><svg class="icon icon-sm"><use href="#ic-clock"/></svg> ממתינים לאישורך</span>
            <button class="mm-approve-all-btn" onclick="mmApproveAll()">
              <svg class="icon icon-sm"><use href="#ic-check"/></svg> אשר הכל
            </button>
          </div>
          <div id="mm-pending-cards"></div>
        </div>

        <!-- Search + sort + full memory list -->
        <div class="mm-search">
          <svg class="icon icon-sm"><use href="#ic-search"/></svg>
          <input id="mmSearch" placeholder="חיפוש בזיכרונות..." oninput="renderMmList()">
          <div class="mm-sort-wrap">
            <button class="mm-sort-btn active" id="sortByDate" onclick="setMmSort('date')">↓ תאריך</button>
            <button class="mm-sort-btn" id="sortByCat" onclick="setMmSort('cat')">א-ת קטגוריה</button>
          </div>
        </div>
        <div id="mm-all-list"></div>
      </div>

      <!-- F: Duplicate Detection — full width, new -->
      <div style="margin-top:16px;padding-bottom:20px">
        <div class="sec-head">
          <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-search"/></svg> זיכרונות דומים</div>
          <button class="dup-scan-btn" id="dupScanBtn" onclick="scanDuplicates()">סרוק כפילויות</button>
        </div>
        <div id="dupResults"><div class="mm-empty">לחץ "סרוק כפילויות" לאיתור זיכרונות דומים</div></div>
      </div>

    </div><!-- /.know-scroll -->
  </div><!-- /.know-tab-layout -->
</div><!-- /#panel-knowledge -->
```

- [ ] **Step 2: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 3: Commit**
```bash
git add jarvis-brain.html
git commit -m "refactor(brain): knowledge tab v2 HTML — two-column layout + duplicate section"
```

---

## Task 4: JS — Add `mmSort` state + sort controls logic

**Files:**
- Modify: `jarvis-brain.html:812-817` (state object)
- Modify: `jarvis-brain.html:~1305` (`renderMmList`)
- Add: `setMmSort()` function after `renderMmList`

- [ ] **Step 1: Add `mmSort` to state object**

Find:
```js
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null,
};
```
Replace with:
```js
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
};
```

- [ ] **Step 2: Add sort logic to `renderMmList()`**

Find the line inside `renderMmList()`:
```js
  const mems = q ? S.memories.filter(m => m.content.toLowerCase().includes(q)) : S.memories;
```
Replace with:
```js
  let mems = q ? S.memories.filter(m => m.content.toLowerCase().includes(q)) : [...S.memories];
  if (S.mmSort === 'cat') {
    mems.sort((a, b) => inferCat(a.content).localeCompare(inferCat(b.content), 'he'));
  } else {
    mems.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  }
```

- [ ] **Step 3: Add `setMmSort()` function**

Find the line immediately after `renderMmList()` closes (after the `}`):
```js
async function mmApprove(id) {
```
Insert before it:
```js
function setMmSort(mode) {
  S.mmSort = mode;
  document.querySelectorAll('.mm-sort-btn').forEach(b => b.classList.remove('active'));
  document.getElementById(mode === 'date' ? 'sortByDate' : 'sortByCat')?.classList.add('active');
  renderMmList();
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
git commit -m "feat(brain): knowledge tab — memory list sort controls (date / category)"
```

---

## Task 5: JS — Identity card streak badge + avatar pulse

**Files:**
- Modify: `jarvis-brain.html:~1404` (`renderIdentityCard`)

- [ ] **Step 1: Add streak computation and `ids-streak` update to `renderIdentityCard()`**

Find inside `renderIdentityCard()`:
```js
  const days = new Set(S.log.map(l => l.created_at ? new Date(l.created_at).toDateString() : null).filter(Boolean));

  const set = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
  set('idAvatar', initial);
  set('idName', name);
  set('idTagline', tagline);
  document.getElementById('idBadges').innerHTML = badges.map(b => `<span class="id-badge ${b.cls}">${b.label}</span>`).join('');
  set('ids-total', S.memories.length);
  set('ids-cats', Object.keys(cats).length);
  set('ids-days', days.size || '—');
  set('ids-pending', S.pending.length);
```
Replace with:
```js
  const days = new Set(S.log.map(l => l.created_at ? new Date(l.created_at).toDateString() : null).filter(Boolean));

  // Streak: consecutive days backwards from today with ≥1 memory
  const memDays = new Set(S.memories.map(m => m.created_at ? new Date(m.created_at).toDateString() : null).filter(Boolean));
  let streak = 0, streakD = new Date();
  while (memDays.has(streakD.toDateString())) { streak++; streakD.setDate(streakD.getDate() - 1); }

  const set = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
  set('idAvatar', initial);
  set('idName', name);
  set('idTagline', tagline);
  document.getElementById('idBadges').innerHTML = badges.map(b => `<span class="id-badge ${b.cls}">${b.label}</span>`).join('');
  set('ids-total', S.memories.length);
  set('ids-cats', Object.keys(cats).length);
  set('ids-days', days.size || '—');
  set('ids-streak', streak > 1 ? streak : '—');
  set('ids-pending', S.pending.length);
```

- [ ] **Step 2: Add `pulseAvatar()` function**

Find `function renderIdentityCard()` and insert the following immediately before it:
```js
function pulseAvatar() {
  const el = document.getElementById('idAvatar');
  if (!el) return;
  el.classList.remove('pulse-anim');
  void el.offsetWidth; // reflow to restart animation
  el.classList.add('pulse-anim');
  el.addEventListener('animationend', () => el.classList.remove('pulse-anim'), { once: true });
}

```

- [ ] **Step 3: Run lint and commit**
```bash
npm run lint
git add jarvis-brain.html
git commit -m "feat(brain): identity card streak badge + avatar pulse animation"
```

---

## Task 6: JS — Cluster cards with 7-day mini sparklines

**Files:**
- Modify: `jarvis-brain.html:~1438` (`renderClusters`)

- [ ] **Step 1: Replace `renderClusters()` with sparkline version**

Find the entire `renderClusters` function:
```js
function renderClusters() {
  const row = document.getElementById('clustersRow');
  const cats = {};
  S.memories.forEach(m => { const c = inferCat(m.content); (cats[c] = cats[c] || []).push(m); });

  row.innerHTML = Object.entries(CLUST_META).map(([name, meta]) => {
    const items = cats[name] || [];
    const preview = items[0]?.content?.slice(0, 60) || 'אין זיכרונות';
    return `<div class="cluster-tile" style="--tc:${meta.color};--tg:${meta.tg}" onclick="toggleCluster(this,'${name}')">
      <span class="ct-icon">${meta.icon}</span>
      <div class="ct-label">${name}</div>
      <div class="ct-count" style="color:${meta.color}">${items.length}</div>
      <div class="ct-preview">${esc(preview)}</div>
    </div>`;
  }).join('');
}
```
Replace with:
```js
function renderClusters() {
  const row = document.getElementById('clustersRow');
  const cats = {};
  S.memories.forEach(m => { const c = inferCat(m.content); (cats[c] = cats[c] || []).push(m); });

  row.innerHTML = Object.entries(CLUST_META).map(([name, meta], idx) => {
    const items = cats[name] || [];
    const preview = items[0]?.content?.slice(0, 40) || 'אין זיכרונות';

    // 7-day sparkline: count memories per day for this category
    const now = Date.now();
    const dayCounts = Array.from({ length: 7 }, (_, i) => {
      const dayStart = new Date(now - (6 - i) * 86400000);
      dayStart.setHours(0, 0, 0, 0);
      const dayEnd = new Date(dayStart.getTime() + 86400000);
      return items.filter(m => {
        const t = m.created_at ? new Date(m.created_at).getTime() : 0;
        return t >= dayStart.getTime() && t < dayEnd.getTime();
      }).length;
    });
    const maxDay = Math.max(...dayCounts, 1);
    const bW = 8, bGap = 2, svgW = 7 * (bW + bGap) - bGap, svgH = 20;
    const sparkBars = dayCounts.map((v, i) => {
      const h = Math.max(2, Math.round((v / maxDay) * svgH));
      const x = i * (bW + bGap);
      const opacity = i === 6 ? '1' : '0.55';
      return `<rect x="${x}" y="${svgH - h}" width="${bW}" height="${h}" rx="1" fill="${meta.color}" opacity="${opacity}"/>`;
    }).join('');
    const sparkSvg = `<svg class="cc-sparkline" width="${svgW}" height="${svgH}" viewBox="0 0 ${svgW} ${svgH}">${sparkBars}</svg>`;

    return `<div class="cc-card" style="border-top-color:${meta.color};animation-delay:${idx * 50}ms" onclick="toggleCluster(this,'${name}')">
      <div class="cc-card-head">
        <span class="cc-card-icon">${meta.icon}</span>
        <span class="cc-card-count" style="color:${meta.color}">${items.length}</span>
      </div>
      <div class="cc-card-name">${name}</div>
      ${sparkSvg}
      <div class="cc-preview">${esc(preview)}</div>
    </div>`;
  }).join('');
}
```

- [ ] **Step 2: Update `toggleCluster` — it receives the clicked `.cc-card` now (was `.cluster-tile`)**

The existing `toggleCluster` (line ~1455) receives `tile` but only uses it to `classList.add('active')` and `querySelectorAll('.cluster-tile')`. Update:

Find:
```js
window.toggleCluster = function(tile, name) {
  const exp = document.getElementById('clusterExpand');
  document.querySelectorAll('.cluster-tile').forEach(t => t.classList.remove('active'));
```
Replace with:
```js
window.toggleCluster = function(tile, name) {
  const exp = document.getElementById('clusterExpand');
  document.querySelectorAll('.cc-card').forEach(t => t.classList.remove('active'));
```

- [ ] **Step 3: Run lint and commit**
```bash
npm run lint
git add jarvis-brain.html
git commit -m "feat(brain): cluster cards with 7-day mini sparklines"
```

---

## Task 7: JS — Timeline hover tooltip via `pointermove`

**Files:**
- Modify: `jarvis-brain.html:~1608` (end of `drawKnowledgeTimeline`)

- [ ] **Step 1: Call `initTimelineHover()` at end of `drawKnowledgeTimeline()`**

Find the last two lines of `drawKnowledgeTimeline()`:
```js
  window._tlMonths = months;
}
```
Replace with:
```js
  window._tlMonths = months;
  initTimelineHover(months, colW, W);
}
```

- [ ] **Step 2: Add `initTimelineHover()` function**

Find the line:
```js
window.showKnowTip = function(idx, x) {
```
Insert the following immediately before it:
```js
function initTimelineHover(months, colW, W) {
  const chart = document.getElementById('tlChart');
  const tip = document.getElementById('tlTip');
  const svg = document.getElementById('tlSvg');
  if (!chart || !tip || !svg) return;

  // remove previous listener if any
  if (chart._hoverFn) chart.removeEventListener('pointermove', chart._hoverFn);
  if (chart._leaveFn) chart.removeEventListener('pointerleave', chart._leaveFn);

  chart._hoverFn = function(e) {
    const rect = chart.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const idx = Math.min(months.length - 1, Math.max(0, Math.floor(x / (W / months.length))));
    const m = months[idx];
    if (!m) return;
    tip.innerHTML = m.items.length
      ? `<strong>${m.label} — ${m.items.length} זיכרונות</strong><br>` +
        m.items.slice(0, 4).map(it => `<span style="color:${CAT_COLOR[it.cat] || '#C8913A'}">${it.cat}</span>: ${esc(it.text)}`).join('<br>')
      : `<strong>${m.label}</strong><br><span style="color:var(--muted)">אין זיכרונות</span>`;
    tip.style.opacity = '1';
    const tipW = tip.offsetWidth || 180;
    tip.style.left = Math.min(x + 8, rect.width - tipW - 4) + 'px';
    tip.style.top = '4px';
    // highlight hovered column in SVG
    document.querySelectorAll('.tl-hover-bar').forEach(el => el.remove());
    const cx = (idx * colW + colW / 2).toFixed(1);
    const bar = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    bar.setAttribute('class', 'tl-hover-bar');
    bar.setAttribute('x', (idx * colW).toFixed(1));
    bar.setAttribute('y', '0');
    bar.setAttribute('width', colW.toFixed(1));
    bar.setAttribute('height', '64');
    bar.setAttribute('fill', 'rgba(200,145,58,.08)');
    bar.setAttribute('rx', '3');
    bar.setAttribute('pointer-events', 'none');
    svg.insertBefore(bar, svg.firstChild);
  };

  chart._leaveFn = function() {
    tip.style.opacity = '0';
    document.querySelectorAll('.tl-hover-bar').forEach(el => el.remove());
  };

  chart.addEventListener('pointermove', chart._hoverFn);
  chart.addEventListener('pointerleave', chart._leaveFn);
}

```

- [ ] **Step 3: Run lint and commit**
```bash
npm run lint
git add jarvis-brain.html
git commit -m "feat(brain): timeline hover tooltip via pointermove"
```

---

## Task 8: JS — Duplicate detection (`scanDuplicates`)

**Files:**
- Modify: `jarvis-brain.html` — add `scanDuplicates()` and helpers

- [ ] **Step 1: Add `scanDuplicates()` function**

Find the line:
```js
// ── 2D Graph ───────────────────────────────────────────────────────────────
```
Insert the following block immediately before it:
```js
// ── Duplicate Detection ────────────────────────────────────────────────────
function scanDuplicates() {
  const btn = document.getElementById('dupScanBtn');
  const results = document.getElementById('dupResults');
  if (!results) return;
  if (S.memories.length < 2) {
    results.innerHTML = '<div class="mm-empty">צריך לפחות 2 זיכרונות לסריקה</div>';
    return;
  }
  if (btn) btn.textContent = 'סורק...';
  results.innerHTML = '';

  // Tokenize each memory: words ≥3 chars, not in HEB_STOP
  const tokens = S.memories.map(m =>
    new Set((m.content || '').split(/\s+/).filter(w => w.length >= 3 && !HEB_STOP.has(w.toLowerCase())).map(w => w.toLowerCase()))
  );

  const pairs = [];
  for (let i = 0; i < S.memories.length; i++) {
    for (let j = i + 1; j < S.memories.length; j++) {
      let shared = 0;
      for (const t of tokens[i]) if (tokens[j].has(t)) shared++;
      if (shared === 0) continue;
      // Dice-like coefficient: 2*|intersection| / (|A| + |B|)
      const score = (2 * shared) / Math.max(1, tokens[i].size + tokens[j].size);
      if (score >= 0.35 || shared >= 3) {
        pairs.push({ i, j, shared, score });
      }
    }
  }

  pairs.sort((a, b) => b.score - a.score);
  const top = pairs.slice(0, 15);

  if (btn) btn.textContent = 'סרוק שוב';

  if (!top.length) {
    results.innerHTML = '<div class="mm-empty">לא נמצאו זיכרונות דומים ✓</div>';
    return;
  }

  results.innerHTML = top.map(({ i, j, shared, score }) => {
    const mA = S.memories[i], mB = S.memories[j];
    const pct = Math.round(score * 100);
    return `<div class="dup-pair" id="dup-${esc(mA.id)}-${esc(mB.id)}">
      <div class="dup-side">
        <div class="dup-text">${esc(mA.content)}</div>
        <div class="dup-meta">${relTime(mA.created_at)}</div>
        <button class="mm-icon-btn del" onclick="dupDelete('${esc(mA.id)}','${esc(mB.id)}')"><svg class="icon icon-sm"><use href="#ic-trash"/></svg> מחק זה</button>
      </div>
      <div class="dup-side">
        <div class="dup-text">${esc(mB.content)}</div>
        <div class="dup-meta">${relTime(mB.created_at)}</div>
        <button class="mm-icon-btn del" onclick="dupDelete('${esc(mB.id)}','${esc(mA.id)}')"><svg class="icon icon-sm"><use href="#ic-trash"/></svg> מחק זה</button>
      </div>
      <div class="dup-score">דמיון: ${pct}% — ${shared} מילים משותפות</div>
    </div>`;
  }).join('');
}

async function dupDelete(deleteId, keepId) {
  if (!confirm('למחוק זיכרון זה?')) return;
  try {
    await api(`/memories/${deleteId}`, { method: 'DELETE' });
    S.memories = S.memories.filter(m => m.id !== deleteId);
    renderMmList(); updateKnowBadge(); updateConstellationKpi(); startGraph2D();
    // Remove all dup-pair cards containing the deleted id
    document.querySelectorAll('.dup-pair').forEach(el => {
      if (el.id.includes(deleteId)) el.remove();
    });
    const results = document.getElementById('dupResults');
    if (results && !results.querySelector('.dup-pair')) {
      results.innerHTML = '<div class="mm-empty">לא נמצאו זיכרונות דומים ✓</div>';
    }
  } catch(e) { alert('שגיאה: ' + e.message); }
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
git commit -m "feat(brain): duplicate memory detection with Dice coefficient + delete"
```

---

## Task 9: Verify, push, PR

- [ ] **Step 1: Final lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for 444 files`

- [ ] **Step 2: Grep for old cluster-tile references**
```bash
grep -n "cluster-tile\|drawGraph()\|showNodePopup\|node-popup" jarvis-brain.html
```
Expected: no output (all cleaned up)

- [ ] **Step 3: Verify `renderKnowledge()` still calls all sub-renderers**

Confirm `renderKnowledge()` (line ~1255) still calls: `updateKnowledgeKpi()`, `renderIdentityCard()`, `renderClusters()`, `renderInsights()`, `drawKnowledgeTimeline()`, `renderMmSection()`. No changes needed — scanDuplicates is on-demand only.

- [ ] **Step 4: Push**
```bash
git push -u origin claude/control-center-tab-hz66rf
```

- [ ] **Step 5: Open PR if none exists**

Check for open PR on branch `claude/control-center-tab-hz66rf`. If none: create draft PR via GitHub MCP with title "feat(brain): knowledge tab v2 — two-column layout, sparklines, hover tooltip, sort, duplicate detection".
