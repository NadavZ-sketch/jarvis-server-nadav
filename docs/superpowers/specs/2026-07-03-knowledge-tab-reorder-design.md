# Knowledge Tab Reorder + Collapsible Memory List — Design Spec

Date: 2026-07-03

## Problem

The "ידע" (Knowledge) tab in `jarvis-brain.html` currently renders, in order: the identity card, the two-column clusters/timeline body, then a full-width "בדיקה ואימות זיכרונות" (memory management: pending-approval queue + search/sort + full memory list) section, then the "בדיקת תקינות זיכרונות" (memory health check: findings queue) section built in the previous feature.

Two usability issues:
1. The memory management section always renders its full list (up to 120 rows) inline, pushing the health-check panel — the section a user is more likely to want to act on regularly — further down the page.
2. The memory list has no way to filter by category or to see archived memories at all. Archived memories (created by the health check's merge/archive/conflict-resolution actions, and by the pre-existing archive-on-replace flow in `services/memoryContext.js`) are invisible in this list, and in every other view in this tab (graph, clusters, timeline) — a gap flagged in the final review of the memory-health-check feature.

## Goals

- Move "בדיקת תקינות זיכרונות" above "בדיקה ואימות זיכרונות" in the DOM.
- Make "בדיקה ואימות זיכרונות" a collapsible section: collapsed by default, showing only the header with its existing stat badges (`✓ N מאושרים` / `⏳ N ממתינים`); auto-expands once if there are pending memories awaiting approval at load time. A user's manual toggle is respected for the rest of the session (a later poll refresh does not override it).
- Add a category filter (pill buttons: הכל + the 5 existing categories) and a scope filter (נוכחי / ארכיון toggle, defaulting to נוכחי) to the memory list, alongside the existing date/category sort.

## Non-goals

- No backend/API changes. `S.memories` (populated by the existing `GET /memories` → `repos.memories.listAll()`, already returning `scope` and `category` for every row since the memory-health-check feature) already carries everything needed; this is a pure rendering-layer change in `jarvis-brain.html`.
- No change to the pending-approval queue's own behavior (`mmApprove`/`mmReject`/`mmApproveAll`) — it continues to render inside the collapsible section exactly as it does today, just inside a container that can be hidden.
- No change to the health-check panel's own internals (Task 12 of the prior feature) beyond its position in the DOM.
- No persistence of collapse/filter state across page reloads (session-only, via the in-memory `S` object) — this matches how every other piece of UI state in this file already behaves (e.g. `S.mmSort`, `S.filter` for the graph).
- No change to how archived memories are treated in the graph/clusters/timeline views — those remain out of scope, as they were in the prior feature's final review (this spec only makes archived memories *visible somewhere*, via the new scope filter, not filtered out of the other visualizations).

## Data flow

Purely client-side. `S.memories` already contains every row's `scope` (`long_term` | `archive`, occasionally `session`/`recent` though those are TTL-pruned server-side before they'd normally appear) and `category` (one of the 5 buckets, or `null`/absent for legacy rows never classified). `renderMmList()` is extended to filter `S.memories` by the new `S.mmCatFilter` (`'all'` or one of the 5 category strings) and `S.mmScopeFilter` (`'active'` or `'archive'`) before applying the existing sort and rendering.

For category filtering, a memory's effective category for filter-matching purposes is `m.category || inferCat(m.content)` — reusing the existing `inferCat()` heuristic as a fallback for legacy uncategorized rows, consistent with how the rest of this tab already treats uncategorized memories (the persisted `category` column is preferred when present, per the memory-health-check feature's own design decision to leave `inferCat()` in place for exactly this kind of fallback use).

## Section reordering

In the DOM, section G ("בדיקת תקינות זיכרונות") moves to sit directly after the two-column clusters/timeline body, and section E ("בדיקה ואימות זיכרונות") moves to directly after it. No change to either section's internal markup beyond what's described below — this is a pure move.

## Collapsible section

The section E header (`.sec-head`) becomes clickable, toggling a new wrapper div around the section's existing body (pending-wrap + search/filter/sort row + memory list). A chevron icon in the header indicates expanded/collapsed state.

State: `S.mmExpanded` — a tri-state value (`null` = not yet decided, `true`/`false` = decided, either by the initial auto-expand logic or by a user click). On every `renderMmSection()` call (which already runs after every `loadPending()`/`loadMemories()`/poll cycle), if `S.mmExpanded === null`, it's set to `S.pending.length > 0` and the body's visibility is synced to it. If `S.mmExpanded` is already `true`/`false` (user has interacted, or the initial auto-decision already ran), the render only updates the body's *content*, never its visibility — so a later poll cycle that brings in new pending memories does not forcibly re-expand a section the user deliberately collapsed. The stat badges in the header remain visible and update regardless of collapse state, since they already render outside the toggled body.

## Filters

Two new controls added to the existing `.mm-search` row area (or directly below it, as a second row) in section E, above `mm-all-list`:

- **Category filter**: a row of pill buttons — "הכל" plus one per category (עבודה/משפחה/בריאות/תחביב/כללי), color-coded using the existing `CAT_COLOR` map for visual consistency with the category chips already shown per memory row. Clicking a pill sets `S.mmCatFilter` and re-renders the list. "הכל" is the default (no filtering).
- **Scope filter**: a two-option toggle — "נוכחי" (default) / "ארכיון". "נוכחי" shows memories where `scope !== 'archive'`; "ארכיון" shows only `scope === 'archive'`. Clicking sets `S.mmScopeFilter` and re-renders.

Both filters combine with the existing search box (`mmSearch`, substring match on content) and existing sort (`sortByDate`/`sortByCat`) — filters narrow the candidate set, sort orders what remains, search further narrows by text, matching the order `renderMmList()` already applies (filter → sort → render, search already applied as a pre-filter in the existing code).

When the scope filter is set to "ארכיון", the "אשר הכל" pending-approval affordance and category-mismatch-style actions remain unaffected — the scope filter only affects `mm-all-list`, not `mm-pending-cards` (pending memories are never `scope:'archive'` by construction).

## Error handling

None of this introduces new failure modes — no new network calls, no new external state. Standard defensive coding already present in `renderMmList()` (empty-state message, `m.content` guarded via `esc()`) is unchanged and continues to apply to the filtered subset.

## Testing

This file (`jarvis-brain.html`) has no automated test coverage in this repo (it's a plain HTML/JS dashboard, not exercised by Jest) — verification is manual: open `/progress-map/brain`, confirm section order, confirm the collapse/auto-expand/manual-toggle behavior, confirm both filters narrow the list correctly (including combined with search and sort), and confirm the archive scope filter surfaces memories archived by the health-check feature.
