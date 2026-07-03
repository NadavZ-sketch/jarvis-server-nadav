# Knowledge Tab Reorder + Collapsible Memory List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the "ידע" (Knowledge) tab of `jarvis-brain.html`, move the memory-health-check panel above the memory management section, make the memory management section a collapsible accordion (auto-expanding when approvals are pending), and add category + scope (current/archive) filters to its memory list.

**Architecture:** Pure client-side change to a single existing file. No backend/API changes — `S.memories` already carries `scope` and `category` for every row. A new `effectiveCat(m)` helper (persisted category, falling back to the existing `inferCat()` regex heuristic for legacy uncategorized rows) is introduced and used consistently for the memory list's sort/filter/display, without touching `inferCat()`'s other ~13 call sites elsewhere in the file (graph, clusters, timeline — explicitly out of scope).

**Tech Stack:** Vanilla JS/HTML/CSS (single-file dashboard, no build step, no test framework covers this file).

**Design spec:** `docs/superpowers/specs/2026-07-03-knowledge-tab-reorder-design.md`

---

## File Structure

Single file modified: `jarvis-brain.html`. Two tasks, each an independently-verifiable, self-contained change:

| Task | What it does |
|---|---|
| Task 1 | Reorder sections (health-check above memory list) + make the memory list section collapsible, auto-expanding when approvals are pending |
| Task 2 | Add category + scope filters to the memory list, backed by a new `effectiveCat()` helper |

---

### Task 1: Reorder sections + collapsible memory list

**Files:**
- Modify: `jarvis-brain.html`

- [ ] **Step 1: Verify the anchor text, then add CSS for the collapse toggle**

First, confirm this exact CSS line still exists in `jarvis-brain.html` (search for it):

```css
.mm-search{display:flex;align-items:center;gap:6px;padding:7px 10px;background:var(--card);border:1px solid var(--border);border-radius:var(--r4);margin-bottom:7px}
```

If it matches exactly, insert this new CSS directly before it:

```css
.mm-toggle-chevron{transition:transform .15s;flex-shrink:0}
.mm-toggle-chevron.open{transform:rotate(90deg)}
.mm-collapsible-body{display:none}
.mm-collapsible-body.open{display:block}
```

If the anchor text doesn't match exactly (whitespace or content differs), stop and report what you actually found rather than guessing at a different insertion point — this is a large single-file dashboard and precision matters.

- [ ] **Step 2: Reorder the HTML sections and add the collapsible wrapper**

Find this exact block (search for the `<!-- E: Memory Management` comment through the end of the `<!-- G: Memory Health Check` block — they are adjacent, E immediately followed by G):

```html
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

      <!-- G: Memory Health Check — full width -->
      <div style="margin-top:16px;padding-bottom:20px">
        <div class="sec-head">
          <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-search"/></svg> בדיקת תקינות זיכרונות</div>
          <button class="dup-scan-btn" id="healthRunBtn" onclick="runHealthScanUI()">הרץ בדיקה עכשיו</button>
        </div>
        <div class="health-strip">
          <div class="health-counts" id="healthCounts"></div>
          <div class="mm-mem-time" id="healthLastRun">—</div>
        </div>
        <div class="health-autofix" id="healthAutofix"></div>
        <div id="healthResults"><div class="mm-empty">אין ממצאים ממתינים</div></div>
      </div>
```

Replace the whole block with (G now first, E second and wrapped in a collapsible body, header now clickable with a chevron replacing the old checkmark icon):

```html
      <!-- G: Memory Health Check — full width (moved above the memory list) -->
      <div style="margin-top:16px">
        <div class="sec-head">
          <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-search"/></svg> בדיקת תקינות זיכרונות</div>
          <button class="dup-scan-btn" id="healthRunBtn" onclick="runHealthScanUI()">הרץ בדיקה עכשיו</button>
        </div>
        <div class="health-strip">
          <div class="health-counts" id="healthCounts"></div>
          <div class="mm-mem-time" id="healthLastRun">—</div>
        </div>
        <div class="health-autofix" id="healthAutofix"></div>
        <div id="healthResults"><div class="mm-empty">אין ממצאים ממתינים</div></div>
      </div>

      <!-- E: Memory Management — full width, collapsible -->
      <div style="margin-top:16px;padding-bottom:20px">
        <div class="sec-head" onclick="toggleMmSection()" style="cursor:pointer">
          <div class="sec-title">
            <svg class="icon icon-sm mm-toggle-chevron" id="mmToggleChevron"><use href="#ic-right"/></svg> בדיקה ואימות זיכרונות
          </div>
          <div style="display:flex;align-items:center;gap:5px">
            <span class="mm-stat-badge approved" id="mm-stat-approved"></span>
            <span class="mm-stat-badge pending" id="mm-stat-pending" style="display:none"></span>
          </div>
        </div>

        <div class="mm-collapsible-body" id="mmCollapsibleBody">
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
      </div>
```

Note: `id="mm-stat-approved"` and `id="mm-stat-pending"` stay exactly where they are (inside the always-visible header, outside the collapsible body) — they must remain visible when the section is collapsed, per the design spec ("the header still shows the existing stat badges... so you get a count at a glance without opening it").

- [ ] **Step 3: Add the collapse state and toggle behavior**

Find this exact block:

```javascript
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
  traceIntentFilter: null, profileDayFilter: null,
  health: { findings: [] },
};
```

Replace with:

```javascript
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
  traceIntentFilter: null, profileDayFilter: null,
  health: { findings: [] },
  mmExpanded: null,
};
```

Find this exact block:

```javascript
function renderMmSection() {
  updateKnowBadge();
  renderMmPending();
  renderMmList();
  renderHealthFindings();
}
```

Replace with:

```javascript
function renderMmSection() {
  if (S.mmExpanded === null) S.mmExpanded = S.pending.length > 0;
  applyMmExpandedState();
  updateKnowBadge();
  renderMmPending();
  renderMmList();
  renderHealthFindings();
}

function applyMmExpandedState() {
  const body = document.getElementById('mmCollapsibleBody');
  const chevron = document.getElementById('mmToggleChevron');
  if (body) body.classList.toggle('open', !!S.mmExpanded);
  if (chevron) chevron.classList.toggle('open', !!S.mmExpanded);
}

function toggleMmSection() {
  S.mmExpanded = !S.mmExpanded;
  applyMmExpandedState();
}
```

This is the core behavior: `S.mmExpanded` starts `null` (undecided). The first time `renderMmSection()` runs after data loads, it's set once based on whether there are pending approvals — never reset to `null` again, so a later poll cycle that brings in new pending memories won't force a section the user manually collapsed back open, and a section the user manually expanded won't get collapsed either.

- [ ] **Step 4: Manual verification**

Since `jarvis-brain.html` has no automated test coverage in this repo, verify by running the server and opening the dashboard in a browser:

Run: `node server.js` (with a valid `.env`), then open `http://localhost:3000/progress-map/brain` and switch to the "ידע" tab.

Verify:
1. "בדיקת תקינות זיכרונות" now renders above "בדיקה ואימות זיכרונות" in the page.
2. If you have pending memories awaiting approval (or force one via `POST /memories` with `status: 'pending'` — or just check with whatever pending memories already exist in your dev data), the memory-management section starts expanded. If you have none, it starts collapsed.
3. Clicking the section header toggles the chevron rotation and shows/hides the body (pending cards + search/sort + list).
4. The `✓ N מאושרים` / `⏳ N ממתינים` badges in the header remain visible and correct whether the section is collapsed or expanded.
5. Manually collapse the section, then wait for a poll cycle (or trigger `reload()` via the console) — confirm it stays collapsed (doesn't snap back open).
6. Open the browser console and confirm no JavaScript errors on load or on toggling.

- [ ] **Step 5: Commit**

```bash
git add jarvis-brain.html
git commit -m "feat: move health-check panel above memory list, make memory list collapsible"
```

---

### Task 2: Category + scope filters on the memory list

**Files:**
- Modify: `jarvis-brain.html`

- [ ] **Step 1: Verify the anchor text, then add CSS for the filter controls**

Confirm this exact CSS line exists (it should be the same line Task 1 inserted new rules before):

```css
.mm-search{display:flex;align-items:center;gap:6px;padding:7px 10px;background:var(--card);border:1px solid var(--border);border-radius:var(--r4);margin-bottom:7px}
```

Insert this new CSS directly before it (after the block Task 1 already inserted, if both tasks are applied in order — search for the exact `.mm-search{...}` line regardless, it will still be there):

```css
.mm-filter-row{display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:7px}
.mm-cat-pill{background:transparent;border:1px solid var(--border);border-radius:20px;font-size:var(--tx-xs);padding:3px 10px;cursor:pointer;font-family:inherit;transition:all .15s;color:var(--muted);font-weight:600}
.mm-cat-pill.on{background:var(--pill-c,var(--accent));border-color:var(--pill-c,var(--accent));color:#0d1117}
```

- [ ] **Step 2: Add the filter controls markup**

Find this exact block (inside the collapsible body added in Task 1 — the search bar, directly followed by the memory list div):

```html
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
```

Replace with (adds the filter row between the search bar and the list):

```html
          <!-- Search + sort + full memory list -->
          <div class="mm-search">
            <svg class="icon icon-sm"><use href="#ic-search"/></svg>
            <input id="mmSearch" placeholder="חיפוש בזיכרונות..." oninput="renderMmList()">
            <div class="mm-sort-wrap">
              <button class="mm-sort-btn active" id="sortByDate" onclick="setMmSort('date')">↓ תאריך</button>
              <button class="mm-sort-btn" id="sortByCat" onclick="setMmSort('cat')">א-ת קטגוריה</button>
            </div>
          </div>
          <div class="mm-filter-row">
            <button class="mm-cat-pill on" onclick="setMmCatFilter('all',this)">הכל</button>
            <button class="mm-cat-pill" style="--pill-c:#60a5fa" onclick="setMmCatFilter('עבודה',this)">עבודה</button>
            <button class="mm-cat-pill" style="--pill-c:#22c55e" onclick="setMmCatFilter('משפחה',this)">משפחה</button>
            <button class="mm-cat-pill" style="--pill-c:#f59e0b" onclick="setMmCatFilter('בריאות',this)">בריאות</button>
            <button class="mm-cat-pill" style="--pill-c:#a78bfa" onclick="setMmCatFilter('תחביב',this)">תחביב</button>
            <button class="mm-cat-pill" style="--pill-c:#C8913A" onclick="setMmCatFilter('כללי',this)">כללי</button>
            <span style="flex:1"></span>
            <div class="seg-grp">
              <button class="seg-btn on" onclick="setMmScopeFilter('active',this)">נוכחי</button>
              <button class="seg-btn" onclick="setMmScopeFilter('archive',this)">ארכיון</button>
            </div>
          </div>
          <div id="mm-all-list"></div>
```

- [ ] **Step 3: Add the `effectiveCat()` helper**

Find this exact block:

```javascript
function inferCat(text) {
  for (const [cat, re] of Object.entries(CAT_RE)) if (re.test(text || '')) return cat;
  return 'כללי';
}
```

Insert directly after it (do not modify `inferCat` itself — it's used by ~13 other call sites elsewhere in this file for the graph/clusters/timeline, all out of scope for this change):

```javascript
function effectiveCat(m) { return m.category || inferCat(m.content); }
```

- [ ] **Step 4: Add filter state and wire the filtering into `renderMmList()`**

Find this exact block:

```javascript
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
  traceIntentFilter: null, profileDayFilter: null,
  health: { findings: [] },
  mmExpanded: null,
};
```

Replace with:

```javascript
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
  traceIntentFilter: null, profileDayFilter: null,
  health: { findings: [] },
  mmExpanded: null,
  mmCatFilter: 'all', mmScopeFilter: 'active',
};
```

(If Task 1 hasn't been applied yet, or was applied and `mmExpanded: null,` isn't present, insert `mmCatFilter: 'all', mmScopeFilter: 'active',` as a new line directly after whatever the last field in the `S` object literal currently is — the exact position among fields doesn't matter, only that the two new fields exist.)

Find this exact block:

```javascript
function renderMmList() {
  const list = document.getElementById('mm-all-list');
  if (!list) return;
  const q = (document.getElementById('mmSearch')?.value || '').trim().toLowerCase();
  let mems = q ? S.memories.filter(m => m.content.toLowerCase().includes(q)) : [...S.memories];
  if (S.mmSort === 'cat') {
    mems.sort((a, b) => inferCat(a.content).localeCompare(inferCat(b.content), 'he'));
  } else {
    mems.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  }
  if (!mems.length) { list.innerHTML = '<div class="mm-empty">אין זיכרונות</div>'; return; }
  list.innerHTML = mems.slice(0, 120).map(m => {
    const cat = inferCat(m.content), col = CAT_COLOR[cat] || '#C8913A';
    const safeId = esc(m.id);
    return `<div class="mm-mem-item" id="mmi-${safeId}" style="border-right-color:${col}">
      <div class="mm-mem-text" id="mmt-display-${safeId}">${esc(m.content)}</div>
      <textarea class="mm-mem-textarea" id="mmt-${safeId}">${esc(m.content)}</textarea>
      <div class="mm-mem-foot">
        <span class="mm-mem-cat" style="background:${col}22;color:${col};border:1px solid ${col}44">${esc(cat)}</span>
        <span class="mm-mem-time">${relTime(m.created_at)}</span>
        <button class="mm-icon-btn" title="ערוך" onclick="mmStartEdit('${safeId}')"><svg class="icon icon-sm"><use href="#ic-pencil"/></svg></button>
        <button class="mm-icon-btn save" id="mms-${safeId}" style="display:none" onclick="mmSaveEdit('${safeId}')"><svg class="icon icon-sm"><use href="#ic-save"/></svg> שמור</button>
        <button class="mm-icon-btn del" title="מחק" onclick="mmDelete('${safeId}')"><svg class="icon icon-sm"><use href="#ic-trash"/></svg></button>
      </div>
    </div>`;
  }).join('');
}
```

Replace with (adds scope + category filtering before sorting, and switches the sort-by-category and per-row display to use `effectiveCat()` instead of raw `inferCat()`, so the filter, sort, and displayed chip all agree with each other):

```javascript
function renderMmList() {
  const list = document.getElementById('mm-all-list');
  if (!list) return;
  const q = (document.getElementById('mmSearch')?.value || '').trim().toLowerCase();
  let mems = q ? S.memories.filter(m => m.content.toLowerCase().includes(q)) : [...S.memories];
  mems = mems.filter(m => (S.mmScopeFilter === 'archive') === (m.scope === 'archive'));
  if (S.mmCatFilter !== 'all') mems = mems.filter(m => effectiveCat(m) === S.mmCatFilter);
  if (S.mmSort === 'cat') {
    mems.sort((a, b) => effectiveCat(a).localeCompare(effectiveCat(b), 'he'));
  } else {
    mems.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  }
  if (!mems.length) { list.innerHTML = '<div class="mm-empty">אין זיכרונות</div>'; return; }
  list.innerHTML = mems.slice(0, 120).map(m => {
    const cat = effectiveCat(m), col = CAT_COLOR[cat] || '#C8913A';
    const safeId = esc(m.id);
    return `<div class="mm-mem-item" id="mmi-${safeId}" style="border-right-color:${col}">
      <div class="mm-mem-text" id="mmt-display-${safeId}">${esc(m.content)}</div>
      <textarea class="mm-mem-textarea" id="mmt-${safeId}">${esc(m.content)}</textarea>
      <div class="mm-mem-foot">
        <span class="mm-mem-cat" style="background:${col}22;color:${col};border:1px solid ${col}44">${esc(cat)}</span>
        <span class="mm-mem-time">${relTime(m.created_at)}</span>
        <button class="mm-icon-btn" title="ערוך" onclick="mmStartEdit('${safeId}')"><svg class="icon icon-sm"><use href="#ic-pencil"/></svg></button>
        <button class="mm-icon-btn save" id="mms-${safeId}" style="display:none" onclick="mmSaveEdit('${safeId}')"><svg class="icon icon-sm"><use href="#ic-save"/></svg> שמור</button>
        <button class="mm-icon-btn del" title="מחק" onclick="mmDelete('${safeId}')"><svg class="icon icon-sm"><use href="#ic-trash"/></svg></button>
      </div>
    </div>`;
  }).join('');
}
```

The scope-filter line `(S.mmScopeFilter === 'archive') === (m.scope === 'archive')` keeps a memory when both sides agree: `mmScopeFilter:'active'` (false) keeps rows where `scope !== 'archive'` (false), and `mmScopeFilter:'archive'` (true) keeps rows where `scope === 'archive'` (true).

- [ ] **Step 5: Add the filter-toggle functions**

Find this exact block:

```javascript
function setMmSort(mode) {
  S.mmSort = mode;
  document.querySelectorAll('.mm-sort-btn').forEach(b => b.classList.remove('active'));
  document.getElementById(mode === 'date' ? 'sortByDate' : 'sortByCat')?.classList.add('active');
  renderMmList();
}
```

Insert directly after it:

```javascript
function setMmCatFilter(cat, btn) {
  S.mmCatFilter = cat;
  btn.parentElement.querySelectorAll('.mm-cat-pill').forEach(b => b.classList.remove('on'));
  btn.classList.add('on');
  renderMmList();
}

function setMmScopeFilter(scope, btn) {
  S.mmScopeFilter = scope;
  btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.remove('on'));
  btn.classList.add('on');
  renderMmList();
}
```

- [ ] **Step 6: Manual verification**

Run: `node server.js` (with a valid `.env`), open `http://localhost:3000/progress-map/brain`, switch to the "ידע" tab, expand the memory-management section.

Verify:
1. Six pills render ("הכל" + 5 categories), each colored to match that category's existing chip color elsewhere in the list; "הכל" starts selected.
2. Clicking a category pill filters the list to only memories whose effective category (persisted `category` if set, else the `inferCat()` guess) matches, and the clicked pill becomes visually selected while others deselect.
3. The "נוכחי"/"ארכיון" toggle defaults to "נוכחי"; clicking "ארכיון" shows only archived memories (`scope:'archive'`) — if you have none yet, resolve a memory-health-check "duplicate" or "conflict" finding via merge/archive in the health panel above, then switch to "ארכיון" and confirm it now appears there instead of in "נוכחי".
4. Category filter, scope filter, search box, and sort (date/category) all combine correctly — e.g. filtering to "עבודה" + "ארכיון" + typing a search term narrows to the intersection.
5. The per-row category chip color/label now matches whichever pill you filtered by (no mismatch between what's filtered and what's displayed).
6. Browser console shows no JavaScript errors.

- [ ] **Step 7: Commit**

```bash
git add jarvis-brain.html
git commit -m "feat: add category and scope filters to the memory list"
```

---

## Final verification

- [ ] Run `npm test` — confirm the full existing suite is still green (this feature touches no server-side/tested code, so this is a pure regression check).
- [ ] Manually re-verify Task 1 and Task 2's checks together in one browser session (reorder + collapse + filters all working in combination).
- [ ] Push the branch and open a PR referencing `docs/superpowers/specs/2026-07-03-knowledge-tab-reorder-design.md`.
