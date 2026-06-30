# Brain Graph v2 — Design Spec
**Date:** 2026-06-30  
**File:** `jarvis-brain.html`  
**Scope:** Constellation tab — KPI strip, 2D SVG graph, 3D Canvas graph

---

## 1. Background

The current constellation tab has two issues:
- KPI strip cards show icons only (labels were removed in an earlier mobile pass)
- The graph looks static and boring: random fake connections, uniform bubbles, no animation, no interactivity

This spec defines a full upgrade to both the KPI strip and both graph views (2D + 3D), adding physics simulation, semantic intelligence, and a unified smart interaction model.

---

## 2. KPI Strip — Interactive Labels

### Current state
Each `.kpi` card contains only `kpi-head` (icon) + `kpi-val` (number). No text label is visible.

### Target state
Every card gets: **icon + text label + value**, displayed consistently with the knowledge tab style.

| KPI ID | Label | Click action |
|--------|-------|-------------|
| `kc-total` | סה״כ זיכרונות | Scroll mem-panel to list, highlight search input |
| `kc-cat` | קטגוריה מובילה | Call `setFilter(topCat)` — filters graph to that category |
| `kc-pending` | ממתינים לאישור | Call `mpTab('pending')` — opens pending tab in panel |
| `kc-last` | אחרון שנשמר | Highlights the matching node in the graph with a glow pulse for 2s |

### Interaction style
- `cursor: pointer` on every card
- Hover: `border-color` transitions to `var(--amber)` with a 0.15s ease, subtle `scale(1.02)`
- Active: brief `scale(0.98)` flash

---

## 3. Graph 2D — SVG Live Physics

### 3.1 Rendering loop
Replace one-shot `drawGraph()` with a `startGraph2D()` that:
1. Builds nodes + edges once (on data change)
2. Starts a `requestAnimationFrame` loop that updates positions and re-renders SVG innerHTML each frame
3. Stops via `stopGraph2D()` when switching to 3D view or leaving constellation tab

### 3.2 Node sizing
```
recency score  = days since created_at → today=1.0, 7d=0.7, 30d=0.5, older=0.3
strength score = semantic connection count / max connections (0–1)
radius = BASE_R + recency * 4 + strength * 4          # hub nodes: BASE_R * 2
BASE_R = isMob ? 8 : 6
```

### 3.3 Semantic connections
For every pair of nodes (a, b):
1. Tokenize both `content` strings: words with 3+ chars, excluding stop-words
2. Count shared tokens → `sharedCount`
3. If `sharedCount >= 1` → add edge with `weight = sharedCount`

Cap total edges at 80 (keep highest-weight edges). Edge opacity = `0.08 + weight * 0.06`, clamped to 0.28.

**Stop-words (Hebrew):** של, את, הוא, היא, הם, הן, אני, אתה, את, זה, זו, לא, כן, עם, על, אל, מה, שם, כל, עוד

### 3.4 Physics simulation (per frame)
```
For each frame:
  // repulsion between all node pairs
  for each (a, b) pair:
    f = REPEL² / dist * damping
    apply f along (b-a) vector

  // spring attraction along edges
  for each edge (a, b):
    natural_len = 80
    f = (dist - natural_len) * 0.005
    apply f toward each other

  // center gravity
  n.vx += (W/2 - n.x) * 0.003
  n.vy += (H/2 - n.y) * 0.003

  // damping + clamp
  n.vx *= 0.85; n.vy *= 0.85
  n.x = clamp(n.x + n.vx, margin, W-margin)
  n.y = clamp(n.y + n.vy, margin, H-margin)
```

When no node is dragged and velocities all < 0.1, reduce rAF to every 4th frame to save battery.

### 3.5 Memory Strength visualization
- **Well-connected** (3+ edges): radius += 3, add SVG `<circle>` glow ring (same color, opacity 0.15, r+6)
- **Orphan** (0 edges): reduced opacity (0.4), dashed ring, slow pulse animation via `stroke-dashoffset` in CSS `@keyframes`

### 3.6 Drag (mouse + touch)
```
mousedown / touchstart on node hit area:
  S.dragging = node id
  capture pointer (setPointerCapture)

mousemove / touchmove:
  if S.dragging:
    node.x = eventX; node.y = eventY
    node.vx = 0; node.vy = 0   // zero velocity while held

mouseup / touchend:
  S.dragging = null
```

### 3.7 Hub click — category highlight
- First click on hub: set `S.highlight = category`
  - Non-matching nodes: opacity → 0.2
  - Hub ring: brightens
- Second click on same hub (or click on background): clear `S.highlight`
- Hub state persists across rAF frames via `S.highlight`

### 3.8 Tooltip on graph
Replaced bottom-sheet popup on mobile and `selectMem()` on desktop with a unified `showGraphTooltip(id, screenX, screenY)`:

```html
<div id="graphTooltip" class="g-tooltip" style="display:none">
  <div class="g-tt-cat"></div>
  <div class="g-tt-text"></div>
  <div class="g-tt-time"></div>
  <div class="g-tt-actions">
    <button onclick="ttEdit()">✎ ערוך</button>
    <button onclick="ttDelete()">✕ מחק</button>
  </div>
</div>
```

Positioning: placed at `(screenX + 12, screenY - 12)`, flipped left/down if near edge. Closed on click outside or Escape.

### 3.9 Focus Neighborhood Mode
Triggered by **double-click** (or double-tap) on a non-hub node:
1. Find all nodes within 1-2 hops (direct edge neighbors + their neighbors)
2. Set `S.focus = nodeId`
3. Non-neighborhood nodes: opacity → 0.08, physics still runs but center-gravity pulls them further out
4. Neighborhood nodes: spread out, stronger spring to hovered node
5. Show small pill "מצב מיקוד — לחץ להחזרה" above graph toolbar
6. Double-click again or pill click → clear `S.focus`

### 3.10 Live Search Highlight
`memSearch` input `oninput` fires `renderMemList()` (existing) **and** `applySearchHighlight(q)`:
- `q` empty → clear all highlights
- For each node: if `content.toLowerCase().includes(q)` → node glows (add yellow ring), others → opacity 0.2
- Highlight updates every frame from `S.searchQ` state variable (set by input handler)

---

## 4. Graph 3D — Canvas with Intelligence

### 4.1 Node data
Replace placeholder index-based nodes with real memory data:
```js
nodes3d = S.memories.slice(0, 60).map((m, i) => ({
  mem: m,
  c: CAT_COLOR[inferCat(m.content)] || '#C8913A',
  r: recencyRadius(m.created_at),   // same formula as 2D
  strength: 0,                        // filled after edge computation
  ox, oy, oz,                         // fibonacci sphere positions
}))
```

Hub nodes for each category placed at poles/equator of the sphere.

### 4.2 Semantic connections (3D)
Same algorithm as 2D. Stored as `edges3d = [{a, b, weight}]`.  
`strength` on each node = count of its edges.

Rendered as lines between projected 2D positions, opacity = `weight * 0.08`.

### 4.3 Orbit drag
```
pointerdown on canvas (not on node):
  S.orbit = { startX, startY, startAngle }

pointermove:
  if S.orbit:
    deltaX = e.clientX - S.orbit.startX
    angle += deltaX * 0.005
    tiltAngle += deltaY * 0.003

pointerup: S.orbit = null
```

### 4.4 Click on node (hit test)
After projection, store `projected[i].screenX/Y`.  
On click: find node with `dist(click, projected[i]) < r*2 + 8`.  
If found:
- Pause auto-rotation (`S.paused = true`)
- Call `showGraphTooltip(mem.id, screenX, screenY)` — same component as 2D
- Show "▶ המשך סיבוב" pill

### 4.5 Memory Strength (3D)
- Well-connected node (3+ edges): `r *= 1.5`, add glow via `ctx.shadowBlur = 10; ctx.shadowColor = n.c`
- Orphan node: `globalAlpha = 0.3`, dashed circle ring drawn manually

### 4.6 Hub click (3D)
Each category gets a hub node (larger, labeled).  
Click on hub: set `S.highlight3d = category` → non-matching nodes: `globalAlpha = 0.15`.  
Click again → clear.

### 4.7 Focus Mode (3D)
Double-click on node:
- Re-sort fibonacci sphere so focus node + neighbors occupy front hemisphere
- Non-neighbors pushed to back with low opacity
- Pill shown: "מצב מיקוד"

### 4.8 Live Search Highlight (3D)
`S.searchQ` checked each frame:
- Matching nodes: `ctx.shadowBlur = 14; ctx.shadowColor = '#fbbf24'` (yellow glow)
- Non-matching: `globalAlpha = 0.15`

---

## 5. Shared Components

### 5.1 `buildSemanticEdges(nodes)`
One function used by both 2D and 3D. Returns `[{a: nodeIndex, b: nodeIndex, weight: n}]`.

### 5.2 `recencyRadius(created_at)`
```js
function recencyRadius(ts) {
  const days = (Date.now() - new Date(ts)) / 86400000;
  if (days < 1)  return isMob ? 13 : 11;
  if (days < 7)  return isMob ? 11 : 9;
  if (days < 30) return isMob ? 9  : 7;
  return isMob ? 7 : 5;
}
```

### 5.3 `showGraphTooltip(memId, x, y)`
Unified tooltip for both 2D (SVG overlay) and 3D (canvas overlay). Positioned absolutely inside `.graph-canvas` container. Edge-aware flip logic.

### 5.4 `S.searchQ`
Set by `memSearch` input handler. Read by both graph loops each frame. No debounce needed (just a string comparison per node per frame).

---

## 6. CSS Additions

```css
/* KPI interactive */
.kpi { cursor: pointer; transition: border-color .15s, transform .1s; }
.kpi:hover { border-color: var(--amber); transform: scale(1.02); }
.kpi:active { transform: scale(0.98); }

/* Graph tooltip */
.g-tooltip { position:absolute; z-index:50; background:var(--card);
  border:1px solid var(--border); border-radius:var(--r8);
  padding:10px 12px; max-width:220px; pointer-events:auto;
  box-shadow: 0 4px 20px rgba(0,0,0,.4); animation: expandIn .15s ease; }

/* Orphan pulse */
@keyframes orphanPulse {
  0%,100% { opacity:.35 } 50% { opacity:.55 }
}
.orphan-node { animation: orphanPulse 2.5s ease-in-out infinite; }

/* Focus mode pill */
.focus-pill { position:absolute; top:8px; left:50%; transform:translateX(-50%);
  background:rgba(245,158,11,.15); border:1px solid rgba(245,158,11,.3);
  color:var(--amber); border-radius:20px; padding:4px 12px;
  font-size:var(--tx-xs); cursor:pointer; z-index:10; }
```

---

## 7. What Does NOT Change

- Left mem-panel (list / edit / pending tabs) — untouched
- Filter buttons (הכל / עבודה / etc.) — layout unchanged, logic unchanged
- `mpTab()`, `selectMem()`, `saveMemory()`, `deleteMemory()` — all intact
- Knowledge tab memory management panel — untouched
- Thinking / Profile tabs — untouched

---

## 8. File Impact

Single file change: `jarvis-brain.html`

Estimated additions: ~350 lines (JS simulation loop, hit test, tooltip, search highlight, 3D upgrades, CSS).  
Estimated removals: ~80 lines (old `drawGraph()`, `draw3d()`, `onNodeClick()`, `showNodePopup()`).

Net: ~+270 lines.

---

## 9. Out of Scope

- Persisting drag positions between sessions
- Server-side semantic analysis (all done client-side)
- WebGL rendering
- D3.js or any external graph library (pure vanilla JS)
