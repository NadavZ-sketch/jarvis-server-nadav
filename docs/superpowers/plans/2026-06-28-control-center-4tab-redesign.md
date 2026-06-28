# Control Center 4-Tab Redesign — Implementation Plan

**Goal:** Replace the current Flutter control center (סקירה / אינטליגנציה / סדנת פיתוח / בדיקות) with the
4-tab "smart control center" from the mockup: **סקירה · מוח · סוכנים · שיפור**.

**Source of truth:**
- Visual mockup: `docs/control-center-4-tabs-smart-mockup.html`
- Spec report: `docs/control-center-4-tabs-smart-mockup-report.md`

**Design line (keep):** dark, dense, functional. Gold (`--gold`) = headings/emphasis, blue = actions/links,
green = ok/approve, red = risk/reject, amber = warning. Match `JC` color tokens in `jarvis_mobile/lib/main.dart`.

---

## Tab → responsibility map

| Tab | id | Owns | Backend (mostly exists) |
|-----|----|------|------|
| סקירה | `overview` | system status, health score, active model, "דורש פעולה" feed, recent actions | `/health`, `/control-center/events`, `/execution-log`, `/stats` |
| מוח | `brain` | Decision Trace, model+fallback row, memories-in-use (approve/forget) | **Decision Trace = NEW backend**; `/health/providers`; `/memories` (+ approval status NEW) |
| סוכנים | `agents` | live agents list + toggles, expandable agent detail, agent card w/ metrics, permissions & risks | `/progress-map/agents`, `.../toggle`, `.../risk`, `/progress-map/metrics` |
| שיפור | `improve` | E2E/health, surveys+feedback, feedback items, Backlog, dynamic improvement interview, survey modal | `/e2e-reports`, `/stats/weekly-score`, `/surveys/*`, `/feedback`, `/proposals`, `/dashboard/backlog`, `/workshop/*` |

### Backend gaps (only two)
1. **Decision Trace** — no endpoint. Decision: build **full backend** — new `decision_trace` table + capture in
   `/ask-jarvis` (input, intent, confidence, agent, tools/memory, model) + `GET /decision-trace?limit=N`.
   Needed for **מוח** tab (later slice).
2. **Memory approval status** — `memoryRepo` has no `status`/`pending` field. Mockup shows "ממתין לאישור" +
   אשר/שכח. Needed for **סקירה** ("דורש פעולה") and **מוח** (memories-in-use). For slice 1 the "דורש פעולה"
   feed is driven by `/control-center/events` alerts, so memory-approval backend is deferred to the מוח slice.

---

## Slicing (ship order)

- **Slice 1 — Shell + Overview** *(this PR)* — zero new backend.
- Slice 2 — Agents tab (most backend ready).
- Slice 3 — Improve tab (reuse e2e/surveys/feedback/backlog/workshop; survey modal + interview).
- Slice 4 — Brain tab + Decision Trace backend + memory-approval backend.

After each slice, the old tabs whose content was migrated get removed.

---

## Slice 1 — Shell + Overview (detailed)

### Files
- Modify: `jarvis_mobile/lib/screens/control_center/control_center_shell.dart`
- Rebuild: `jarvis_mobile/lib/screens/control_center/tab_overview.dart`
- Create stubs: `tab_brain.dart`, `tab_agents.dart`, `tab_improve.dart` (each a centered "בקרוב" placeholder, `AutomaticKeepAliveClientMixin`)
- Keep (untouched, migrated later): `tab_intelligence.dart`, `tab_dev_workshop.dart`, `tab_tests.dart`, `workshop_screen.dart`

### Shell changes
- Replace `enum CcTab { overview, intelligence, devWorkshop, tests }` →
  `enum CcTab { overview, brain, agents, improve }`.
- Labels: `overview→'סקירה'`, `brain→'מוח'`, `agents→'סוכנים'`, `improve→'שיפור'`.
- `_tabBody`: overview→`TabOverview`, brain→`TabBrain`, agents→`TabAgents`, improve→`TabImprove`.
- Role gating: keep existing pattern. Non-admin sees `[overview, improve]`; admin sees all 4.
  (Brain+Agents are the "internals" tabs, gated like the old intelligence/devWorkshop were.)
- Keep the global web shortcut to `/progress-map` (mockup `.web-shortcut`) — add an AppBar action that opens
  `${settings.serverUrl}/progress-map` via `url_launcher` (method `_openVisualControlCenter()` per spec).

### Overview tab content (mirror mockup `#overview`)
1. **Status card** — headline "ג'רוויס פעיל ובריא", sub "שרת, DB וספקי מודלים זמינים · {latency}ms",
   pulsing status dot (green ok / amber / red). Buttons: "פתח לוג" (blue), "הסבר מצב".
   Data: `healthCheck()` → GET /health (`ok`, `active_model`; latency = measured round-trip ms).
2. **Two metrics** (`grid2`): "ציון בריאות" (derive: 100 minus weighted penalties from provider availability /
   latest e2e score — pick a simple, documented formula) and "מודל פעיל" = `active_model`.
3. **דורש פעולה** section — list from `/control-center/events` `alerts[]`. Style each as `.event` with
   severity color (urgent→red, warning→amber, info→blue/default). Render `title`, `message`, and action
   buttons from `actionHint` (wire the obvious ones; hide buttons with no real action per spec rule #9).
   Add `getControlCenterEvents()` to `ApiService` if missing → GET /control-center/events.
4. **פעולות אחרונות** section — `fetchExecutionLog(limit: 8)` → GET /execution-log. Render as `.event good`
   rows: time (HH:MM from created_at) · agent · short cmd/model summary.

### Constraints
- RTL, `fontFamily: 'Heebo'` everywhere.
- Reuse `JC` tokens; do not hardcode hex when a token exists.
- `RefreshIndicator` + pull-to-refresh; adaptive polling like the existing `tab_overview.dart`
  (30s foreground / pause background).
- Every button maps to a real action or is omitted. No dead buttons.
- Run `flutter analyze` on changed files; zero errors.

### Verification
- `cd jarvis_mobile && flutter analyze lib/screens/control_center/`
- Manual: shell shows 4 tabs; overview renders status + metrics + alerts + recent actions; other 3 tabs show placeholder.

---

## Notes for later slices
- Agents tab: `getAgents()`, `toggleAgent(id)`, `setAgentRisk(id, level)`, `getAgentMetrics()` already exist.
- Improve tab consolidates today's `tab_intelligence` (weekly score/history) + `tab_tests` (e2e/schedule/export)
  + `tab_dev_workshop` (prompts/router-trainer/changelog/proposals) + survey modal + dynamic interview.
- Brain tab blocked on Decision Trace + memory-approval backends — build those first in Slice 4.
