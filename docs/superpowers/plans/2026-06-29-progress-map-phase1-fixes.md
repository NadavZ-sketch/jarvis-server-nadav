# Progress-Map Phase 1 Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 bugs and 2 UX gaps in `progress-map.html` identified in the control-center-vision-report.

**Architecture:** All 5 fixes are isolated edits inside a single file — `progress-map.html`. No backend changes. No new files. Each task targets a distinct code region; they are independent and can be applied in any order.

**Tech Stack:** Vanilla JS, CSS custom properties, HTML. No build step. Test by opening the page in a browser (or `node server.js` and visiting `http://localhost:3000/progress-map`).

---

## File Map

| Region | Lines | Task |
|--------|-------|------|
| `<style>` block end (before `</style>`) | ~700 | Task 1 — add `.ac-overlay` CSS |
| Progress bar JS | 1152–1161 | Task 2 — fix pctPlanned calc |
| `devLabTest()` body | 3011–3015 | Task 3 — pass `useLocal` |
| `<style>` block + `loadSettings()` + `saveSettings()` | 11–18, 2166, 2219 | Task 4 — apply theme |
| `loadE2E()` + `triggerE2E()` + E2E button label | 873, 1880–1943 | Task 5 — E2E UX |

---

## Task 1: Fix Mobile Agent Detail Overlay (`.ac-overlay`)

**Files:**
- Modify: `progress-map.html` — add CSS for `.ac-overlay` / `.ac-overlay-back`

**Problem:** `div#acOverlay` (line 1033) and `button.ac-overlay-back` (line 1034) exist in HTML. JS adds/removes class `.open` (lines 2567, 2572). No CSS exists → overlay is invisible on mobile.

- [ ] **Step 1: Locate the insertion point**

Find the closing `</style>` tag that terminates the main style block. Search for the line:
```
@media(max-width:520px){.settings-2col{grid-template-columns:1fr}}
```
It is near line 493. The `</style>` tag follows shortly after. Insert the new rules **before** `</style>`.

- [ ] **Step 2: Add the CSS**

Insert immediately before the `</style>` tag of the main style block:

```css
/* Mobile agent detail overlay */
.ac-overlay{display:none;position:fixed;inset:0;z-index:1000;background:var(--bg);overflow-y:auto;padding:16px 16px 80px;-webkit-overflow-scrolling:touch}
.ac-overlay.open{display:block}
.ac-overlay-back{display:inline-flex;align-items:center;gap:6px;padding:8px 16px;margin-bottom:16px;background:var(--glass);border:1px solid var(--glass-border);border-radius:var(--radius-sm);color:var(--text);font-size:.84rem;font-weight:600;cursor:pointer;font-family:inherit;transition:background .15s,border-color .15s}
.ac-overlay-back:hover{background:rgba(200,145,58,.1);border-color:rgba(200,145,58,.3)}
```

- [ ] **Step 3: Verify in browser**

Start server (`node server.js`), open `http://localhost:3000/progress-map`, resize browser to <640px width (or use DevTools mobile emulation). Go to the Agents tab. Click any agent. The agent detail panel must slide in as a full-screen overlay with a "→ חזרה לרשימה" back button. Clicking back must dismiss it.

- [ ] **Step 4: Run backend tests (sanity)**

```bash
npm test 2>&1 | tail -5
```
Expected: all existing tests pass (HTML changes don't affect Jest).

- [ ] **Step 5: Commit**

```bash
git add progress-map.html
git commit -m "fix: add missing CSS for .ac-overlay mobile agent detail panel"
```

---

## Task 2: Fix Progress Bar Negative Percentage

**Files:**
- Modify: `progress-map.html` lines 1152–1161

**Problem:** `pctDone` and `pctBuilding` are independently rounded strings via `.toFixed(0)`. Their sum can exceed 100 due to rounding. Then `pctPlanned = 100 - pctDone - pctBuilding` does string subtraction from a number, yielding a negative value that sets a negative CSS `width`.

- [ ] **Step 1: Read the current code (lines 1150–1162)**

Confirm the existing code reads exactly:
```js
const pctDone     = (done.length / total * 100).toFixed(0);
const pctBuilding = (building.length / total * 100).toFixed(0);
const pctPlanned  = (100 - pctDone - pctBuilding);
```

- [ ] **Step 2: Replace the three `pct*` lines**

Replace lines 1152–1154 with:
```js
const pctDone     = (done.length / total * 100).toFixed(0);
const pctBuilding = (building.length / total * 100).toFixed(0);
const pctPlanned  = (planned.length / total * 100).toFixed(0);
```

This computes each segment independently from raw counts, so all three always sum to ≤100 (rounding errors affect only the visual width, never go negative).

- [ ] **Step 3: Verify in browser**

Open `http://localhost:3000/progress-map`. The Overview tab progress bar must show three segments (done / building / planned) with non-negative widths. Open DevTools → Elements, inspect `#pb-planned-seg`; confirm `width` is not negative. Also confirm the `pb-pct-label` shows a reasonable percentage.

- [ ] **Step 4: Commit**

```bash
git add progress-map.html
git commit -m "fix: compute progress bar pctPlanned from raw count, prevents negative width"
```

---

## Task 3: Pass `useLocal` in Feature Lab

**Files:**
- Modify: `progress-map.html` lines 3011–3015 (`devLabTest()`)

**Problem:** `devLabTest()` sends `{ message, history }` to `/progress-map/agents/:id/chat` but omits `useLocal`. The Dev tab's "שימוש במודל מקומי (Ollama)" checkbox (`cfg-useLocal`, line 948) is ignored — the server always uses its default provider chain.

- [ ] **Step 1: Locate `devLabTest()` body**

Find the `fetch` call inside `devLabTest()`:
```js
body: JSON.stringify({ message: input, history: [] }),
```
It is at approximately line 3014.

- [ ] **Step 2: Add `useLocal` to the request body**

Replace that line with:
```js
body: JSON.stringify({ message: input, history: [], useLocal: document.getElementById('cfg-useLocal')?.checked || false }),
```

- [ ] **Step 3: Verify**

In browser, go to Dev tab → Feature Lab. Toggle the "שימוש במודל מקומי" checkbox ON. Run a test. Check the browser Network tab: the request body for `/progress-map/agents/.../chat` must contain `"useLocal":true`. Toggle it OFF, run again — must contain `"useLocal":false`.

- [ ] **Step 4: Commit**

```bash
git add progress-map.html
git commit -m "fix: forward useLocal flag from settings checkbox into Feature Lab requests"
```

---

## Task 4: Apply Theme and Brightness Mode

**Files:**
- Modify: `progress-map.html` — CSS block, `loadSettings()`, `saveSettings()`

**Problem:** `cfg-selectedTheme` (line 968) and `cfg-brightnessMode` (line 969) are loaded into select elements (lines 2166–2167) and saved to the profile (lines 2203–2204), but no JS applies them to the DOM. The page is always the default dark navy theme regardless of the saved setting.

### Step 2a — Add theme CSS variable overrides

- [ ] **Step 1: Add theme and brightness CSS overrides**

Insert **before** the `</style>` tag of the main style block (after the `.ac-overlay` rules you added in Task 1):

```css
/* ── Theme overrides ─────────────────────────────────────────────────── */
html[data-theme="glassDark"]{
  --bg:#050810;--surface:#070b14;--card:rgba(255,255,255,.06);
  --glass:rgba(255,255,255,.08);--glass-border:rgba(255,255,255,.16);
  --accent:#7dd3fc;--accent2:#38bdf8;--glow:rgba(125,211,252,.28);--glow2:rgba(125,211,252,.12)
}
html[data-theme="neoDark"]{
  --bg:#0a0014;--surface:#0f0019;--card:#130024;--card2:#1a0030;
  --accent:#d946ef;--accent2:#e879f9;--glow:rgba(217,70,239,.28);--glow2:rgba(217,70,239,.12)
}
html[data-theme="material3"]{
  --bg:#1c1b1f;--surface:#2b2930;--card:#322f37;--card2:#3b3840;
  --text:#e6e1e5;--muted:#938f99;--accent:#d0bcff;--accent2:#ccc2dc;
  --glass:rgba(255,255,255,.05);--glass-border:rgba(255,255,255,.12);
  --glow:rgba(208,188,255,.2);--glow2:rgba(208,188,255,.08)
}
html[data-theme="cyberpunk"]{
  --bg:#0d0d0d;--surface:#111111;--card:#1a1a1a;--card2:#222;
  --accent:#00ff41;--accent2:#39ff14;--glow:rgba(0,255,65,.3);--glow2:rgba(0,255,65,.1);
  --border:rgba(0,255,65,.15);--glass-border:rgba(0,255,65,.2)
}
/* ── Brightness overrides ────────────────────────────────────────────── */
html[data-brightness="light"]{
  --bg:#f8fafc;--surface:#f1f5f9;--card:#ffffff;--card2:#f8fafc;
  --text:#1e293b;--muted:#64748b;--glass:rgba(0,0,0,.03);--glass-border:rgba(0,0,0,.1);
  --border:rgba(0,0,0,.08)
}
@media(prefers-color-scheme:light){
  html[data-brightness="system"]{
    --bg:#f8fafc;--surface:#f1f5f9;--card:#ffffff;--card2:#f8fafc;
    --text:#1e293b;--muted:#64748b;--glass:rgba(0,0,0,.03);--glass-border:rgba(0,0,0,.1);
    --border:rgba(0,0,0,.08)
  }
}
```

### Step 2b — Add `applyTheme()` JS function

- [ ] **Step 2: Add the `applyTheme` helper function**

Find the `// ── Toast Notifications` comment (line ~1042) and insert the following **immediately before it** (after the `<script>` tag):

```js
function applyTheme(theme, brightness) {
  const h = document.documentElement;
  h.setAttribute('data-theme', theme || 'navyDark');
  h.setAttribute('data-brightness', brightness || 'dark');
}
```

### Step 2c — Call `applyTheme` when settings load

- [ ] **Step 3: Call `applyTheme` at the end of `loadSettings()`**

Find `loadSettings()`. It ends with `loadProviders();` (line 2180). Insert one line **after** `loadProviders();`:

```js
applyTheme(_getVal('cfg-selectedTheme'), _getVal('cfg-brightnessMode'));
```

### Step 2d — Call `applyTheme` when settings save

- [ ] **Step 4: Call `applyTheme` when user saves settings**

Find `saveSettings()`. After `showToast('הגדרות נשמרו ✓','success');` (line 2218), add:

```js
applyTheme(_getVal('cfg-selectedTheme'), _getVal('cfg-brightnessMode'));
```

Also wire the select elements to apply immediately on change. Find where the two selects are (lines 968–969) and add `onchange` handlers. Replace:

```html
<select id="cfg-selectedTheme">
```
with:
```html
<select id="cfg-selectedTheme" onchange="applyTheme(this.value, document.getElementById('cfg-brightnessMode').value)">
```

And replace:
```html
<select id="cfg-brightnessMode">
```
with:
```html
<select id="cfg-brightnessMode" onchange="applyTheme(document.getElementById('cfg-selectedTheme').value, this.value)">
```

- [ ] **Step 5: Verify in browser**

Open Settings tab. Change "ערכת נושא" to "סייברפאנק" — page must turn dark with green accents immediately. Change to "Material 3" — page turns purple-tinted. Change "בהירות" to "בהיר" — page background turns light. Reload the page; the theme must persist (loaded from profile via `loadSettings`).

- [ ] **Step 6: Commit**

```bash
git add progress-map.html
git commit -m "feat: apply theme and brightness mode from settings — CSS vars + applyTheme()"
```

---

## Task 5: E2E UX — Polling, Mark-Done, Rename Button

**Files:**
- Modify: `progress-map.html` — `triggerE2E()`, `loadE2E()`, E2E button label (line 873)

**Problem:** Three UX gaps:
1. After triggering E2E, only one `setTimeout(loadE2E, 5000)` fires — if the run takes >5s the list doesn't update.
2. No "mark as done" button in the reports list.
3. The "📋 ייצוא לקלוד" label at line 873 is ambiguous — it exports AND copies, but the name says only "export".

### 5a — Rename the export button label

- [ ] **Step 1: Rename the export-to-Claude button in the QA tab HTML**

Find line 873:
```html
<div class="spinner" id="exportReportSpinner"></div><span id="exportReportText">📋 ייצוא לקלוד</span>
```
Replace `ייצוא לקלוד` with `שלח לקלוד`:
```html
<div class="spinner" id="exportReportSpinner"></div><span id="exportReportText">📋 שלח לקלוד</span>
```
Also find the `finally` block in `copyReportPrompt` (around line 2052) where the button text is restored. Find:
```js
if (btn) { btn.textContent = '...טוען'; }
```
... and the restore line. Check there's no hardcoded `ייצוא` in the restore path (it uses `orig` — so it's fine).

### 5b — Add E2E polling after trigger

- [ ] **Step 2: Replace the one-shot setTimeout in `triggerE2E()` with polling**

Find the `triggerE2E()` function (lines 1935–1944). The current `finally` block ends with:
```js
finally { btn.disabled=false; sp.style.display='none'; tx.textContent='▶️ הרץ בדיקות E2E'; setTimeout(loadE2E, 5000); }
```

Replace **only** the `setTimeout(loadE2E, 5000)` call at the end of the `finally` block with a polling helper call:

```js
finally { btn.disabled=false; sp.style.display='none'; tx.textContent='▶️ הרץ בדיקות E2E'; _pollE2E(6); }
```

Then add the `_pollE2E` helper immediately **before** `triggerE2E()` (around line 1935):

```js
function _pollE2E(attemptsLeft, delay = 5000) {
  setTimeout(async () => {
    await loadE2E();
    if (attemptsLeft > 1) _pollE2E(attemptsLeft - 1, Math.min(delay * 1.5, 30000));
  }, delay);
}
```

This polls 6 times with exponential backoff (5s → 7.5s → 11s → 16s → 24s → 30s ≈ ~93s total coverage).

### 5c — Add mark-done button to each report row

- [ ] **Step 3: Add a mark-done button in `loadE2E()`**

Find `loadE2E()` (lines 1880–1918). Inside the `.map(r => ...)` template string, find the line that renders the send button:

```js
const sendBtn = r.count > 0
  ? `<button class="qa-btn report-send-btn" onclick="copyReportPrompt('${escapeHtml(r.run_id||'')}', this)">📋 שלח לקלוד</button>`
  : '';
```

Replace with:

```js
const sendBtn = r.count > 0
  ? `<button class="qa-btn report-send-btn" onclick="copyReportPrompt('${escapeHtml(r.run_id||'')}', this)">📋 שלח לקלוד</button>`
  : '';
const doneBtn = `<button class="qa-btn" style="background:rgba(34,197,94,.1);border-color:rgba(34,197,94,.25);color:var(--green)" onclick="markE2EDone('${escapeHtml(r.run_id||'')}', this)" title="סמן כטופל ומחק דוח">✓ טופל</button>`;
```

Then find where `sendBtn` is rendered inside the HTML template (it's in the `e2e-sev` div):
```js
<div class="e2e-sev">${sev || '<span class="sev-pill sev-low">נקי</span>'}${sendBtn}</div>
```

Replace with:
```js
<div class="e2e-sev">${sev || '<span class="sev-pill sev-low">נקי</span>'}${sendBtn}${doneBtn}</div>
```

- [ ] **Step 4: Add `markE2EDone()` function**

Insert immediately after `loadE2E()` closes (after line 1918):

```js
async function markE2EDone(runId, btn) {
  if (!runId) return;
  if (!confirm('לסמן את הדוח כטופל ולמחוק אותו?')) return;
  const orig = btn ? btn.textContent : '';
  if (btn) { btn.disabled = true; btn.textContent = '...'; }
  try {
    const r = await fetch(`/e2e-reports/${encodeURIComponent(runId)}/mark-done`, { method: 'POST' });
    if (r.ok) { showToast('הדוח סומן כטופל ✓', 'success'); await loadE2E(); }
    else showToast('שגיאה בסימון הדוח', 'error');
  } catch { showToast('שגיאת רשת', 'error'); }
  finally { if (btn) { btn.disabled = false; btn.textContent = orig; } }
}
```

- [ ] **Step 5: Verify in browser**

1. Open QA tab → confirm the E2E trigger button reads "▶️ הרץ בדיקות E2E".
2. Confirm each report row shows a green "✓ טופל" button.
3. Trigger an E2E run. Observe the reports list auto-refreshes several times over the next ~30s.
4. Click "✓ טופל" on a report → confirm dialog appears → confirm → report disappears from list.
5. Open Settings tab → confirm the export-to-Claude button in the QA tab header reads "📋 שלח לקלוד".

- [ ] **Step 6: Run backend tests**

```bash
npm test 2>&1 | tail -5
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add progress-map.html
git commit -m "feat: E2E UX — polling after trigger, mark-done button, rename שלח לקלוד"
```

---

## Self-Review

### Spec coverage

| Finding from report | Covered by |
|---------------------|-----------|
| BUG-1: `.ac-overlay` CSS missing | Task 1 ✅ |
| BUG-2: theme/brightness stubbed | Task 4 ✅ |
| BUG-3: Progress Bar negative | Task 2 ✅ |
| UX: Feature Lab ignores `useLocal` | Task 3 ✅ |
| UX: Alerts no auto-refresh | Already implemented at line 2443 (`setInterval(loadSmartAlerts, 90000)`) — ✅ false alarm |
| UX: E2E polling + mark-done + rename | Task 5 ✅ |

**Note:** The report listed alerts auto-refresh as a UX gap, but `progress-map.html:2443` already has `setInterval(loadSmartAlerts, 90000)` in the init block. No fix needed.

### Placeholder scan

All code blocks are complete. No "TBD" or "fill in later". All function names referenced are defined within this plan or already exist in the file.

### Type consistency

- `applyTheme(theme, brightness)` defined in Task 4 Step 2, called in Task 4 Steps 3 and 4 — consistent.
- `_pollE2E(attemptsLeft, delay)` defined in Task 5 Step 2, called in `triggerE2E` — consistent.
- `markE2EDone(runId, btn)` defined in Task 5 Step 4, called from inline HTML in Step 3 — consistent.
- `escapeHtml()` — already exists in `progress-map.html` (used throughout).
