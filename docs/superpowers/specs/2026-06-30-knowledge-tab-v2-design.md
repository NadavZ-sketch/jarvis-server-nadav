# Knowledge Tab v2 — Design Spec
**Date:** 2026-06-30  
**File:** `jarvis-brain.html`  
**Scope:** ידע tab — layout refresh, interactive components, duplicate detection

---

## 1. Background

The knowledge tab currently renders as a single long scroll column:
Identity Card → topic cluster chips → insight cards → timeline → memory management.

This spec upgrades it to a smart two-column layout with richer interactivity and a new client-side duplicate-detection feature.

---

## 2. Layout

### 2.1 Desktop (≥768px) — two-column grid

```
┌──────────────────────────────────────────┐
│         Identity Card  (full width)       │
├──────────────────────┬───────────────────┤
│   LEFT column         │   RIGHT column    │
│  • Topic clusters     │  • Timeline       │
│  • Insight cards      │  • Learning curve │
├──────────────────────┴───────────────────┤
│      Memory Management  (full width)      │
│      pending queue + search + sort + list │
├──────────────────────────────────────────┤
│      Duplicate Detection  (full width)    │
└──────────────────────────────────────────┘
```

CSS class `.know-two-col` wraps the two columns: `display:grid; grid-template-columns:1fr 1fr; gap:0; border-bottom: 1px solid var(--border)`. Each column has `overflow-y:auto`.

### 2.2 Mobile (<768px)
Single column — left column stacks above right column, all sections flow top-to-bottom (same as today). Responsive via `@media(max-width:767px) { .know-two-col { grid-template-columns:1fr } }`.

### 2.3 Sticky section headers
Each section inside the scrollable `.know-scroll` gets `position:sticky; top:0; z-index:5; background:var(--bg); border-bottom:1px solid var(--border)` on its `.sec-head` so the section title stays visible while scrolling past long lists.

---

## 3. Identity Card — Minor Enhancements

### 3.1 Streak badge
Add a `.id-streak` span inside `.id-stats` showing consecutive active days. Computed client-side from `S.memories`: extract distinct `created_at` dates (yyyy-mm-dd), walk backwards from today counting consecutive days that have ≥1 memory until a gap. Format: `🔥 X ימים` alongside the existing stat blocks. If 0 or 1 day, show nothing.

### 3.2 Avatar pulse
`onclick` on `.id-avatar` triggers a 0.4s `@keyframes avatarPulse` (scale 1 → 1.12 → 1, glow ring). Purely visual; no navigation.

---

## 4. Topic Clusters — Chips → Cards

### 4.1 Current state
`.clusters-row`: 5-column grid of small colored chips (`cluster-chip`). Click opens `clusterExpand`.

### 4.2 Target state
Each category gets a **cluster card** (`.cc-card`):

```
┌──────────────────────┐
│ ● עבודה         12  │  ← color dot + name + count
│ ▇▇▆▃▁▄▇             │  ← 7-day mini sparkline (SVG)
│ "פגישה מחר עם..."   │  ← last memory preview (1 line, truncated)
└──────────────────────┘
```

Grid: `grid-template-columns: repeat(auto-fill, minmax(140px,1fr))`. On mobile: `repeat(2,1fr)`.

**Mini sparkline:** 7 bars (last 7 days), counting memories per day in that category. Drawn as inline SVG `<rect>` elements, color = `CAT_COLOR[cat]` at 60% opacity (bars) / 100% opacity (today's bar).

**Click behavior:** unchanged — calls existing `openCluster(cat)` which renders `clusterExpand`. The expand panel appears below the clusters row at full column width.

**Entrance animation:** staggered `animation: cardIn 0.2s ease both`, `animation-delay: i * 40ms` (set inline via JS loop).

### 4.3 CSS
```css
.cc-card { background:var(--card); border:1px solid var(--border); border-radius:var(--r8);
  padding:10px 12px; cursor:pointer; transition:transform .15s, border-color .15s; }
.cc-card:hover { transform:translateY(-2px); border-color:rgba(200,145,58,.4); }
@keyframes cardIn { from { opacity:0; transform:translateY(8px) } to { opacity:1; transform:none } }
```

---

## 5. Insight Cards — Expandable

### 5.1 Current state
`.insights-scroll`: horizontal scroll of fixed-height cards.

### 5.2 Target state
Vertical stack of cards inside the left column. Each card:
- **Collapsed:** max 2 lines of text + category color dot + relative date ("3 ימים")
- **Expanded:** full text, `max-height` transition (200ms ease)
- Click anywhere on card to toggle expand
- `cursor:pointer`

```css
.insight-card { ... max-height:72px; overflow:hidden; transition:max-height .2s ease; cursor:pointer; }
.insight-card.expanded { max-height:300px; }
```

---

## 6. Timeline — Interactive Hover

### 6.1 Existing
`#tlSvg`: SVG bar chart drawn by `drawTimeline()`. `#tlTip`: tooltip div (already in HTML, style `display:none`).

### 6.2 Enhancement
Add `pointermove` listener on `#tlChart` in `drawTimeline()` (or `initTimelineHover()` called after draw):

```js
tlChart.addEventListener('pointermove', e => {
  // find bar under pointer from stored barRects[]
  // set tlTip textContent = `${month} ${year}\n${count} זיכרונות`
  // position tlTip near pointer, flip if near right edge
});
tlChart.addEventListener('pointerleave', () => { tlTip.style.display = 'none'; });
```

Hovered bar gets `fill-opacity:1` (others 0.55). No new data fetches.

---

## 7. Memory Management — Sort Controls

### 7.1 Addition
Two sort buttons added to the `.mm-search` row (right side):

| Button | Sort |
|--------|------|
| `↓ תאריך` | `created_at` descending (default) |
| `א-ת קטגוריה` | category name ascending |

`S.mmSort` state variable (`'date'` | `'cat'`). `renderMmList()` reads `S.mmSort` and sorts before rendering. No server calls.

---

## 8. Duplicate Detection — New Section

### 8.1 Placement
New `<div>` section below memory management, inside `.know-scroll`. Always rendered (empty state shown until scan runs).

### 8.2 UI structure
```html
<div class="sec-head">
  <div class="sec-title">🔍 זיכרונות דומים</div>
  <button id="dupScanBtn" onclick="scanDuplicates()">סרוק כפילויות</button>
</div>
<div id="dupResults"></div>
```

### 8.3 Algorithm (`scanDuplicates()`)
1. Take `S.memories` (all loaded memories)
2. Tokenize each memory's `content`: split on whitespace, keep words ≥3 chars, exclude `HEB_STOP`
3. For every pair (a, b): count shared tokens → `shared`
4. Compute score: `shared / Math.sqrt(tokensA.size * tokensB.size)` (Dice-like coefficient, 0–1)
5. Keep pairs where `score ≥ 0.35` OR `shared ≥ 3`
6. Sort descending by score, take top 15
7. Render into `#dupResults`

### 8.4 Pair card UI
```
┌──────────────────────┬────────────────────┐
│  זיכרון א             │  זיכרון ב           │
│  "תוכן...            │  "תוכן...           │
│   23 יוני 2026"      │   25 יוני 2026"     │
│  [מחק זה ✕]          │  [מחק זה ✕]         │
└──────────────────────┴────────────────────┘
     דמיון: 78% — 5 מילים משותפות
```

Delete calls existing `deleteMemory(id)` + re-renders pairs (removes pairs containing deleted id).

**Empty state:** `<div class="mm-empty">לא נמצאו זיכרונות דומים ✓</div>`

**Loading state:** "סורק..." text + spinner during the O(n²) scan (runs synchronously; for <200 memories this completes in <50ms; for larger sets, wrap in `setTimeout(..., 0)` to yield to browser).

### 8.5 CSS
```css
.dup-pair { display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-bottom:12px;
  border:1px solid var(--border); border-radius:var(--r8); padding:10px; }
.dup-side { display:flex; flex-direction:column; gap:6px; font-size:var(--tx-sm); }
.dup-score { text-align:center; font-size:var(--tx-xs); color:var(--muted);
  padding:4px 0; border-top:1px solid var(--border); margin-top:4px; }
.dup-scan-btn { background:rgba(200,145,58,.1); border:1px solid rgba(200,145,58,.35);
  color:var(--amber); border-radius:var(--r2); padding:4px 12px;
  font-size:var(--tx-xs); cursor:pointer; font-family:inherit; }
```

---

## 9. CSS Additions Summary

```css
/* Two-column layout */
.know-two-col { display:grid; grid-template-columns:1fr 1fr; }
.know-col { overflow-y:auto; }
.know-col + .know-col { border-inline-start:1px solid var(--border); } /* RTL-safe */

/* Sticky section heads */
.sec-head { position:sticky; top:0; z-index:5; background:var(--bg);
  border-bottom:1px solid var(--border); }

/* Cluster cards */
.cc-card { ... } /* see §4.3 */
@keyframes cardIn { ... }

/* Insight cards expandable */
.insight-card { max-height:72px; overflow:hidden; transition:max-height .2s ease; cursor:pointer; }
.insight-card.expanded { max-height:300px; }

/* Avatar pulse */
@keyframes avatarPulse { 0%,100%{transform:scale(1)} 50%{transform:scale(1.12)} }

/* Duplicate pairs */
.dup-pair { ... } /* see §8.5 */
.dup-side { ... }
.dup-score { ... }
.dup-scan-btn { ... }
```

---

## 10. What Does NOT Change

- `loadKnow()`, `renderMmList()`, `mmApproveAll()`, `mmDelete()`, `mmSaveEdit()`, `openCluster()`, `closeCluster()`, `drawTimeline()` — all intact (extended, not replaced)
- All server endpoints — zero new API calls
- Memory management approval workflow — untouched
- Thinking / Profile / Constellation tabs — untouched

---

## 11. File Impact

Single file: `jarvis-brain.html`

Estimated additions: ~280 lines (CSS + HTML restructure + JS: cluster cards, sparklines, insight expand, timeline hover, sort, duplicate scan)  
Estimated removals: ~25 lines (old chips layout, old insights-scroll horizontal)  
Net: ~+255 lines

---

## 12. Out of Scope

- Server-side semantic duplicate detection (LLM-based)
- Merge/combine duplicate memories (only delete one)
- Persisting duplicate scan results between sessions
- Thinking or Profile tab changes (separate specs)
