# Memory Health Check — Design Spec

Date: 2026-07-02

## Problem

Jarvis has a solid embedding-based duplicate/conflict detector (`checkDuplicate`/`findConflict` in `agents/memoryAgent.js`), but it only runs at memory-creation time. There is no way to check the health of the memories that already exist in the table: near-duplicates that were created before the checker existed, memories whose category label no longer matches their content after an edit, stale/thin/orphaned entries, etc.

The "ידע" (Knowledge) tab in `jarvis-brain.html` already has a client-side `scanDuplicates()` button, but it's a crude in-browser token-overlap heuristic (not semantic), only ever deletes one side of a pair (no merge), and its results aren't persisted between sessions. The prior spec (`2026-06-30-knowledge-tab-v2-design.md`) explicitly listed "server-side semantic duplicate detection," "merge duplicate memories," and "persisting scan results" as out of scope — this spec picks those up.

## Goals

- Detect, on a schedule and on demand, four categories of memory-quality problems:
  1. **Duplicates** — near-identical memories (semantic)
  2. **Conflicts** — memories that contradict each other on the same topic
  3. **Category mismatches** — a memory's stored category no longer matches its content
  4. **Stale/thin/orphaned** — memories unrefreshed for 6+ months, near-empty/uninformative content, or Supabase↔Pinecone sync gaps
- Every finding that would change or remove user content (delete/merge/move/archive) requires explicit one-click user approval — nothing destructive happens automatically.
- Non-destructive internal-consistency repairs (Supabase↔Pinecone sync gaps) are self-healed automatically and just logged.
- Both automatic (nightly cron) and manual ("run now") triggering.
- Extend the existing "ידע" tab UI and pending-queue interaction pattern rather than building a new surface.

## Non-goals

- No mobile UI for this feature in this iteration (web dashboard only, per the "ידע" tab decision).
- No new embedding model/index — reuses the existing Pinecone index and `pineconeMemory.js` API surface as-is.
- No change to the existing creation-time `checkDuplicate`/`findConflict` behavior — the health check is an additive, batch-mode use of the same primitives.
- No automatic backfill migration of `category` for all historical rows as part of the schema migration itself; existing rows start with `category = NULL` and get classified the first time the health scan (or a manual edit) touches them.

## Data model

### `memories.category` (new column)

```sql
ALTER TABLE memories ADD COLUMN IF NOT EXISTS category text;
```

Values constrained (by application logic, not a DB check constraint, to stay consistent with the rest of the schema's conventions) to the 5 buckets already used client-side in `jarvis-brain.html`: `עבודה`, `משפחה`, `בריאות`, `תחביב`, `כללי`. Classification happens server-side:
- At creation time (`autoExtractMemory`, explicit save via `runMemoryAgent`, and `POST /memories`) — a lightweight LLM classification call assigns the initial category.
- At manual edit time (`PUT /memories/:id`) — re-classified if content changed.
- The client-side `inferCat()`/`CAT_RE` regex in `jarvis-brain.html` is removed; the UI reads the persisted `category` column instead of recomputing it.

### `memory_health_findings` (new table)

```sql
CREATE TABLE memory_health_findings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('duplicate','conflict','category_mismatch','stale','thin_content','orphaned_vector','orphaned_row')),
  memory_id uuid NOT NULL,
  related_memory_id uuid,
  suggested_action text NOT NULL CHECK (suggested_action IN ('delete','merge','move','archive','resync')),
  suggested_payload jsonb,
  score numeric,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  content_hash text,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE INDEX idx_memory_health_findings_status ON memory_health_findings(status);
```

- `content_hash` is a hash of the `memory_id` (and `related_memory_id`, if present) row content at scan time. Used to decide whether a `rejected` finding should be allowed to resurface: if the underlying memory's content has changed since the hash was recorded, a fresh scan is allowed to re-flag it even if the old finding was dismissed.
- Upsert key for dedup across scans: `(type, memory_id, related_memory_id)`. Re-running the scan updates `score`/`suggested_payload`/`created_at` on an existing `pending` row rather than inserting a new one; `approved`/`rejected` rows are left alone unless the content-hash check above says otherwise.
- New `services/dataAccess/memoryHealthRepo.js` wraps this table (list by status/type, upsert-by-key, setStatus), following the existing repo-factory pattern, wired into `dataAccess/index.js`.

Migration file: `supabase/migrations/<timestamp>_memory_health_check.sql` containing both the `category` column addition and the new table (also mirrored to `docs/superpowers/migrations/` per repo convention for curated migrations touching memory behavior).

## Detection engine

New file `services/memoryHealthCheck.js`, single export `runHealthScan(repos)`. Scan targets rows where `scope = 'long_term' AND status = 'approved'` — `archive`-scoped rows are excluded since they're already resolved/superseded, `session`/`recent`-scoped rows are excluded since they're already TTL-managed by `memoryCleanup.js`, and `pending`-status rows are excluded since they aren't confirmed memories yet.

1. **Duplicates**: for each memory, call `pineconeMemory.findSimilarMemory(content, 0.92)` (same threshold as `checkDuplicate`) excluding itself; on a hit, upsert a `duplicate` finding for the pair (order the two IDs deterministically to avoid creating the pair twice), `suggested_action: 'merge'`, `suggested_payload: {mergedContent}` computed via one LLM call that synthesizes both memories' content into a single combined statement.
2. **Conflicts**: same loop, using the 0.70–0.92 band from `findConflict`. `suggested_action: 'archive'` with `suggested_payload` left empty (the UI presents "keep A, archive B" / "keep B, archive A" as two resolve calls with different payloads, not a single suggested one).
3. **Category mismatch**: for each memory with a non-null `category`, one LLM classification call; if it disagrees with the stored value, upsert a `category_mismatch` finding, `suggested_action: 'move'`, `suggested_payload: {category: <llm's answer>}`.
4. **Stale**: `long_term` memories with `created_at` older than 6 months (no "last accessed" column exists, so recency is approximated by creation date — noted as a known limitation, since there's currently no read/recall tracking per memory to do better). `suggested_action: 'archive'`.
5. **Thin content**: content under ~5 words after stripping the `[tag]` prefix. `suggested_action: 'delete'`.
6. **Orphaned vector/row**: reuse `pineconeMemory.listAll()` (Pinecone IDs) vs `memories.listAll()` (Supabase IDs) to diff the two sets, same technique `recoverFromPinecone`/`syncFromSupabase` already use. These findings are `resync` and are **applied immediately by the scan itself** (not left pending) — Supabase-only rows get re-upserted to Pinecone, Pinecone-only vectors get deleted (since a vector with no backing row is bookkeeping debris, not user content to recover — recovery is what `POST /memories/recover-from-pinecone` is for, unchanged). A finding row is still written with `status: 'approved'` and `resolved_at` set immediately, purely as an audit log entry for the "🔧 N synced automatically" UI line.

Cost control: LLM calls only happen for actual findings (duplicate merge synthesis, category classification), not for every memory unconditionally — category classification is one LLM call per memory per scan, which is the dominant cost; batching multiple memories into one prompt per call is left as a future optimization if memory counts grow large enough to matter.

## Triggering

- **Cron**: new `node-cron` entry in `server.js`, `35 3 * * *` (Asia/Jerusalem), named `memory_health_scan`, wrapped in the existing `scheduledJob()` helper (logs to `cron_runs` like all other jobs). Runs right after `memory_cleanup_nightly` (03:30) and before `profile_learning` (03:45).
- **Manual**: `POST /memories/health/run` — calls the same `runHealthScan(repos)`, rate-limited (reusing the `express-rate-limit` pattern already applied to `/scan/errors`, e.g. 5/min), returns a summary `{created, updated, autoResolved}` count by type.

## API

All under the existing `/memories` router (`routes/memories.js` + `controllers/memoriesController.js`):

| Method | Path | Notes |
|---|---|---|
| `GET` | `/memories/health/findings` | `?type=`, `?status=pending` (default) — list findings |
| `POST` | `/memories/health/run` | Manual trigger, rate-limited |
| `POST` | `/memories/health/findings/:id/resolve` | Body `{action, payload?}` — `action` must be one of the finding's valid actions for its type (e.g. a `duplicate` finding accepts `delete` with `payload:{keepId}` or `merge` with `payload:{mergedContent}` or `dismiss`); server validates the action is legal for that finding's `type` before applying. Gated by `requirePolicy('memory.delete', {sensitive:true, irreversible:true})`, mirroring `DELETE /memories/:id`. |
| `POST` | `/memories/health/findings/:id/dismiss` | Sets `status:'rejected'`, records the current `content_hash` |

`resolve` implementations reuse existing primitives: `delete` → same path as `deleteMemory`/`DELETE /memories/:id` (Supabase row + Pinecone vector + Obsidian entry); `archive` → same `scope:'archive'` + Pinecone-removal logic already in `memoryContext.savePendingData`; `move` → `PUT`-equivalent updating just `category`; `merge` → insert one new memory with `suggested_payload.mergedContent` (or user-edited text) run through the same server-side category classification as any new memory, then archive both originals.

## UI

New "בדיקת תקינות" sub-panel inside the existing "ידע" tab in `jarvis-brain.html`, replacing the current `scanDuplicates()` client-only implementation:

- **Header strip**: counts by type, "🔍 הרץ בדיקה עכשיו" button → `POST /memories/health/run`, last-run timestamp, and (when applicable) "🔧 N בעיות סנכרון תוקנו אוטומטית הלילה" (from `resync` findings).
- **Findings list**: one card per pending finding, grouped by type, each showing the involved memory content(s) and type-specific action buttons:
  - **Duplicate**: מחק [A] / מחק [B] / אחד (opens the LLM-suggested merged text in an editable textarea; "שמור מיזוג" submits `resolve` with the edited text) / התעלם
  - **Conflict**: השאר את [A] וארכב את [B] / השאר את [B] וארכב את [A] / התעלם
  - **Category mismatch**: עדכן לקטגוריה: [X] (button shows the suggested category) / a manual dropdown of all 5 categories as an alternative / השאר
  - **Stale**: ארכב / השאר
  - **Thin content**: מחק / ערוך (opens the existing inline memory editor) / השאר
- Every resolve/dismiss action reuses the app's existing irreversible-action confirm dialog pattern (`X-Confirm-Action`/`X-User-Consent` headers sent by the dashboard's `api()` helper, matching how `DELETE /memories/:id` is already called from this same tab).
- Badge count added to `GET /control-center/events`, following the existing `memory_pending` alert shape, as `memory_health_findings` (or similar key) so the dashboard shell shows a nudge without opening the tab.

## Error handling

- Per-item scan failures (one memory's Pinecone/LLM call throwing) are caught and skipped, logged via `systemLog.js`; they don't abort the rest of the scan or the cron job.
- If Pinecone is unreachable for the whole run, duplicate/conflict/orphan checks are skipped for that run (no findings written, no crash); category/stale/thin checks still proceed since they don't depend on it.
- `resolve`/`dismiss` endpoints 404 if the finding is already resolved (idempotent double-click protection), and 400 if the requested `action` isn't valid for the finding's `type`.

## Testing

- `tests/unit/memoryHealthCheck.test.js` — one test per detection type against `tests/helpers/fakeRepos.js` + a mocked `pineconeMemory`; upsert-on-rerun dedup; "dismissed finding doesn't resurface unless content changed" via `content_hash`.
- `tests/unit/dataAccess/memoryHealthRepo.test.js` — new repo, following existing `dataAccess` test conventions.
- `tests/integration/memoryHealth.test.js` — one flow: run scan → resolve a merge → confirm both originals archived, new merged memory created, Pinecone/Supabase consistent.
- Existing `tests/unit/memoryAgent.test.js` (`checkDuplicate`/`findConflict`) is untouched — the health engine calls these, doesn't reimplement them.
