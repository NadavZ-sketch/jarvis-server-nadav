# Memory Health Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a batch memory-health-check system (duplicates, conflicts, category mismatches, stale/thin/orphaned entries) that runs nightly and on demand, surfaces findings in the existing "ידע" (Knowledge) tab with an approval-gated resolve flow, and self-heals non-destructive Supabase↔Pinecone sync gaps automatically.

**Architecture:** A new `memories.category` column and `memory_health_findings` table back a detection engine (`services/memoryHealthCheck.js`) that batches the same Pinecone-embedding thresholds `agents/memoryAgent.js` already uses at creation time, plus new category/staleness checks. A separate resolution module (`services/memoryHealthActions.js`) applies the user's chosen action (delete/merge/move/archive) by reusing existing primitives (Pinecone, Obsidian, the `memories` repo). Four new routes under the existing `/memories` router expose list/run/resolve/dismiss, gated the same way `DELETE /memories/:id` already is. The existing "ידע" tab's client-only duplicate-scan section is replaced with a real findings queue.

**Tech Stack:** Node/Express, Supabase (Postgres), Pinecone (`@pinecone-database/pinecone`), Jest + Supertest, vanilla JS in `jarvis-brain.html`.

**Design spec:** `docs/superpowers/specs/2026-07-02-memory-health-check-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260702_memory_health_check.sql` (new) | `memories.category` column + `memory_health_findings` table |
| `docs/superpowers/migrations/memory_health_check.sql` (new) | Mirror of the above, per repo convention for curated memory-behavior migrations |
| `services/memoryCategory.js` (new) | `classifyCategory(content, useLocal)` — LLM classification into the 5-bucket taxonomy |
| `services/dataAccess/memoryRepo.js` (modify) | `category` column support in `listAll`/`create`/`insert`/`updateById`, with the same column-missing fallback convention already used for `scope`/`status` |
| `services/dataAccess/memoryHealthRepo.js` (new) | Thin CRUD over `memory_health_findings` |
| `services/dataAccess/index.js` (modify) | Wire `memoryHealth: createMemoryHealthRepo(supabase)` into the repos bundle |
| `tests/helpers/fakeRepos.js` (modify) | `makeMemoryHealthRepo` fake, wired into `makeRepos` |
| `services/memoryHealthCheck.js` (new) | `runHealthScan(repos, {useLocal})` — the four detectors + orphan auto-fix |
| `services/memoryHealthActions.js` (new) | `resolveFinding(finding, action, payload, repos)` — applies delete/merge/move/archive |
| `agents/memoryAgent.js` (modify) | Fire-and-forget category classification after an explicit-save insert |
| `services/memoryContext.js` (modify) | Category classification in `savePendingData` (confirmed fact/pref saves) |
| `controllers/memoriesController.js` (modify) | Category in `create`/`update`; new `listHealthFindings`/`runHealthScan`/`resolveHealthFinding`/`dismissHealthFinding` handlers |
| `routes/memories.js` (modify) | Four new routes under `/memories/health/*` |
| `server.js` (modify) | Rate limiter for `/memories/health/run`; new `memory_health_scan` cron at 03:35 Jerusalem |
| `jarvis-brain.html` (modify) | Replace the client-only "זיכרונות דומים" section with the health-check findings queue |
| `tests/integration/memoryHealth.test.js` (new) | End-to-end scan → resolve flow |
| `CLAUDE.md` (modify) | Document the new endpoints, cron job, and services |

---

### Task 1: Migration — `category` column + `memory_health_findings` table

**Files:**
- Create: `supabase/migrations/20260702_memory_health_check.sql`
- Create: `docs/superpowers/migrations/memory_health_check.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260702_memory_health_check.sql
-- Memory health check: persisted category on memories + a findings table for
-- the batch health scan (duplicates, conflicts, category mismatches,
-- stale/thin content, Supabase<->Pinecone sync gaps).

ALTER TABLE memories ADD COLUMN IF NOT EXISTS category TEXT;

CREATE TABLE IF NOT EXISTS memory_health_findings (
    id                 UUID        NOT NULL DEFAULT gen_random_uuid(),
    type               TEXT        NOT NULL CHECK (type IN (
                            'duplicate', 'conflict', 'category_mismatch',
                            'stale', 'thin_content', 'orphaned_vector', 'orphaned_row'
                        )),
    memory_id          BIGINT      NOT NULL,
    related_memory_id  BIGINT,
    suggested_action   TEXT        NOT NULL CHECK (suggested_action IN (
                            'delete', 'merge', 'move', 'archive', 'resync'
                        )),
    suggested_payload  JSONB,
    score              NUMERIC,
    status             TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    content_hash       TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at        TIMESTAMPTZ,
    CONSTRAINT memory_health_findings_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS memory_health_findings_status_idx ON memory_health_findings (status);
CREATE INDEX IF NOT EXISTS memory_health_findings_lookup_idx ON memory_health_findings (type, memory_id, related_memory_id);

COMMENT ON COLUMN memories.category                        IS 'One of עבודה/משפחה/בריאות/תחביב/כללי, LLM-classified at write time; NULL for rows created before this feature';
COMMENT ON TABLE  memory_health_findings                    IS 'Findings from the batch memory-health scan (services/memoryHealthCheck.js)';
COMMENT ON COLUMN memory_health_findings.related_memory_id  IS 'Second memory in a pair finding (duplicate/conflict); NULL for single-memory findings';
COMMENT ON COLUMN memory_health_findings.content_hash       IS 'Hash of the involved memory content(s) at scan time — lets a dismissed finding resurface only if content later changed';
```

- [ ] **Step 2: Mirror the migration into the curated docs subset**

Copy the exact same SQL content to `docs/superpowers/migrations/memory_health_check.sql`.

- [ ] **Step 3: Apply the migration**

Run: `psql "$SUPABASE_DB_URL" -f supabase/migrations/20260702_memory_health_check.sql` (or apply via the Supabase web UI — this repo's convention per `CLAUDE.md`'s "Adding Supabase Tables" workflow). Verify:

```sql
select column_name from information_schema.columns where table_name = 'memories' and column_name = 'category';
select count(*) from memory_health_findings;
```
Expected: the first query returns one row (`category`); the second returns `0`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260702_memory_health_check.sql docs/superpowers/migrations/memory_health_check.sql
git commit -m "feat: add memories.category column and memory_health_findings table"
```

---

### Task 2: `services/memoryCategory.js` — category classification

**Files:**
- Create: `services/memoryCategory.js`
- Test: `tests/unit/memoryCategory.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
// tests/unit/memoryCategory.test.js
'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { classifyCategory, CATEGORIES } = require('../../services/memoryCategory');

beforeEach(() => jest.clearAllMocks());

describe('classifyCategory', () => {
    test('returns the LLM-classified category when it is a known bucket', async () => {
        callGemma4.mockResolvedValue('{"category":"בריאות"}');
        const result = await classifyCategory('יש לי פגישה עם הרופא ביום שלישי');
        expect(result).toBe('בריאות');
    });

    test('defaults to כללי when the LLM returns an unknown category', async () => {
        callGemma4.mockResolvedValue('{"category":"ספורט"}');
        const result = await classifyCategory('תוכן כלשהו');
        expect(result).toBe('כללי');
    });

    test('defaults to כללי when the LLM returns invalid JSON', async () => {
        callGemma4.mockResolvedValue('not json');
        const result = await classifyCategory('תוכן כלשהו');
        expect(result).toBe('כללי');
    });

    test('defaults to כללי when callGemma4 throws', async () => {
        callGemma4.mockRejectedValue(new Error('provider down'));
        const result = await classifyCategory('תוכן כלשהו');
        expect(result).toBe('כללי');
    });

    test('returns כללי for empty content without calling the LLM', async () => {
        const result = await classifyCategory('   ');
        expect(result).toBe('כללי');
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('CATEGORIES exposes the 5-bucket taxonomy', () => {
        expect(CATEGORIES).toEqual(['עבודה', 'משפחה', 'בריאות', 'תחביב', 'כללי']);
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx jest tests/unit/memoryCategory.test.js`
Expected: FAIL — `Cannot find module '../../services/memoryCategory'`

- [ ] **Step 3: Write the implementation**

```javascript
// services/memoryCategory.js
'use strict';

const { callGemma4 } = require('../agents/models');
const { extractJSON } = require('../agents/utils');

const CATEGORIES = ['עבודה', 'משפחה', 'בריאות', 'תחביב', 'כללי'];

const PROMPT_PREFIX = `סווג את התוכן הבא לאחת מהקטגוריות: עבודה, משפחה, בריאות, תחביב, כללי.
כללי היא ברירת המחדל כשאין התאמה ברורה לאף קטגוריה אחרת.
החזר JSON בלבד: {"category": "אחת מהקטגוריות בעברית"}

תוכן: `;

async function classifyCategory(content, useLocal = false) {
    if (!content || !content.trim()) return 'כללי';
    try {
        const aiText = await callGemma4([{ role: 'user', content: PROMPT_PREFIX + content }], useLocal, 60);
        const parsed = extractJSON(aiText);
        const category = parsed?.category;
        return CATEGORIES.includes(category) ? category : 'כללי';
    } catch (err) {
        console.error('[memoryCategory] classify error (defaulting to כללי):', err.message);
        return 'כללי';
    }
}

module.exports = { classifyCategory, CATEGORIES };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx jest tests/unit/memoryCategory.test.js`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add services/memoryCategory.js tests/unit/memoryCategory.test.js
git commit -m "feat: add memoryCategory.js for LLM-based memory categorization"
```

---

### Task 3: `memoryRepo.js` — persist and return `category`

**Files:**
- Modify: `services/dataAccess/memoryRepo.js`
- Test: `tests/unit/dataAccess/memoryRepo.test.js`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/dataAccess/memoryRepo.test.js`:

```javascript
describe('memoryRepo.category', () => {
    test('listAll includes category in the row when present', async () => {
        const chain = makeChain([{ id: 1, content: 'a', scope: 'long_term', category: 'עבודה', created_at: '2026-01-01' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.listAll();
        expect(rows[0].category).toBe('עבודה');
    });

    test('listAll falls back to the pre-category column set when category is missing', async () => {
        const noCatChain = makeChain(null, { message: 'column "category" does not exist', code: '42703' });
        const okChain = makeChain([{ id: 1, content: 'a', scope: 'long_term', created_at: '2026-01-01' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? noCatChain : okChain) });
        const rows = await repo.listAll();
        expect(rows).toEqual([{ id: 1, content: 'a', scope: 'long_term', created_at: '2026-01-01' }]);
    });

    test('create includes category in the insert payload and echoes it back', async () => {
        const chain = makeChain([{ id: 9, content: 'x', scope: 'long_term', category: 'תחביב', created_at: '2026-01-01' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.create({ content: 'x', scope: 'long_term', category: 'תחביב' });
        expect(chain.insert).toHaveBeenCalledWith([{ content: 'x', scope: 'long_term', category: 'תחביב' }]);
        expect(rows[0].category).toBe('תחביב');
    });

    test('create retries without category when the column is missing', async () => {
        const catErrChain = makeChain(null, { message: 'column "category" does not exist', code: '42703' });
        const okChain = makeChain([{ id: 9, content: 'x', scope: 'long_term', created_at: '2026-01-01' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? catErrChain : okChain) });
        const rows = await repo.create({ content: 'x', scope: 'long_term', category: 'תחביב' });
        expect(rows[0].id).toBe(9);
    });

    test('insert retries without category when missing, then still applies the scope/status fallback chain', async () => {
        const catErrChain    = makeChain(null, { message: 'column "category" does not exist' });
        const scopeErrChain  = makeChain(null, { message: 'scope column missing', code: '42703' });
        const statusErrChain = makeChain(null, { message: 'status column missing', code: '42703' });
        const okChain        = makeChain([{ id: 20 }]);
        const chains = [catErrChain, scopeErrChain, statusErrChain, okChain];
        let call = 0;
        const repo = createMemoryRepo({ from: () => chains[call++] });
        const rows = await repo.insert({ content: 'c', scope: 'session', status: 'pending', category: 'כללי' });
        expect(rows).toEqual([{ id: 20 }]);
    });

    test('updateById includes category in the select and patch', async () => {
        const chain = makeChain([{ id: 7, content: 'new', scope: 'long_term', category: 'בריאות' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.updateById('7', { category: 'בריאות' });
        expect(chain.update).toHaveBeenCalledWith({ category: 'בריאות' });
        expect(rows[0].category).toBe('בריאות');
    });

    test('updateById falls back without category when the column is missing', async () => {
        const catErrChain = makeChain(null, { message: 'column "category" does not exist' });
        const okChain = makeChain([{ id: 7, content: 'new', scope: 'long_term' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? catErrChain : okChain) });
        const rows = await repo.updateById('7', { content: 'new' });
        expect(rows[0].id).toBe(7);
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/unit/dataAccess/memoryRepo.test.js`
Expected: FAIL — the new tests fail because `category` isn't selected/handled yet (e.g. `rows[0].category` is `undefined`, the fallback chains throw instead of degrading).

- [ ] **Step 3: Implement — modify `listAll`, `create`, `insert`, `updateById`**

In `services/dataAccess/memoryRepo.js`, replace the `listAll` method:

```javascript
        async listAll() {
            const { data, error } = await supabase.from(M)
                .select('id, content, scope, category, created_at')
                .order('created_at', { ascending: false });
            if (!error) return data || [];
            // category may be missing — fall back to the pre-category column set unchanged.
            const { data: dataNoCat, error: errNoCat } = await supabase.from(M)
                .select('id, content, scope, created_at')
                .order('created_at', { ascending: false });
            if (!errNoCat) return dataNoCat || [];
            // scope may be missing — try without it but keep created_at ordering
            const { data: data2, error: err2 } = await supabase.from(M)
                .select('id, content, created_at')
                .order('created_at', { ascending: false });
            if (!err2) return data2 || [];
            // created_at may be missing — keep scope so session rows stay hidden
            const { data: data3, error: err3 } = await supabase.from(M)
                .select('id, content, scope')
                .order('id', { ascending: false });
            if (!err3) return data3 || [];
            // Last resort: minimal columns only
            const { data: data4, error: err4 } = await supabase.from(M)
                .select('id, content')
                .order('id', { ascending: false });
            if (err4) throw err4;
            return data4 || [];
        },
```

Replace the `create` method:

```javascript
        async create(row) {
            const { data, error } = await supabase.from(M)
                .insert([row])
                .select('id, content, scope, category, created_at')
                .limit(1);
            if (!error) return data || [];

            if (error.message?.includes('category')) {
                const { category: _cat, ...rowWithoutCategory } = row;
                const { data: d1, error: err1 } = await supabase.from(M)
                    .insert([rowWithoutCategory])
                    .select('id, content, scope, created_at')
                    .limit(1);
                if (!err1) return d1 || [];
                if (err1.message?.includes('scope') || err1.code === '42703') {
                    const { scope: _s, ...rowMinimal } = rowWithoutCategory;
                    const { data: d2, error: err2 } = await supabase.from(M)
                        .insert([rowMinimal])
                        .select('id, content, created_at')
                        .limit(1);
                    if (err2) throw err2;
                    return d2 || [];
                }
                throw err1;
            }

            if (error.message?.includes('scope') || error.code === '42703') {
                const { scope: _s, ...rowWithoutScope } = row;
                const { data: d2, error: err2 } = await supabase.from(M)
                    .insert([rowWithoutScope])
                    .select('id, content, created_at')
                    .limit(1);
                if (err2) throw err2;
                return d2 || [];
            }
            throw error;
        },
```

Replace the `insert` method:

```javascript
        async insert(row) {
            const { data, error } = await supabase.from(M).insert([row]).select('id').limit(1);
            if (!error) return data || [];

            let workingRow = row;
            let workingError = error;

            // category is the newest optional column — strip it first if that's
            // the cause, then fall through to the pre-existing fallback chain below.
            if (workingError.message?.includes('category')) {
                const { category: _cat, ...rest } = workingRow;
                workingRow = rest;
                const retry = await supabase.from(M).insert([workingRow]).select('id').limit(1);
                if (!retry.error) return retry.data || [];
                workingError = retry.error;
            }

            if (workingError.message?.includes('scope') || workingError.code === '42703') {
                const { scope: _s, ...rowWithoutScope } = workingRow;
                const { data: d2, error: err2 } = await supabase.from(M).insert([rowWithoutScope]).select('id').limit(1);
                if (!err2) return d2 || [];
                // status column may also be missing — try without it too
                if (err2.message?.includes('status') || err2.code === '42703') {
                    const { status: _st, ...rowMinimal } = rowWithoutScope;
                    const { data: d3 } = await supabase.from(M).insert([rowMinimal]).select('id').limit(1);
                    return d3 || [];
                }
                throw err2;
            }
            // status column may not exist yet — retry without it
            if (workingError.message?.includes('status')) {
                const { status: _st, ...rowWithoutStatus } = workingRow;
                const { data: d2 } = await supabase.from(M).insert([rowWithoutStatus]).select('id').limit(1);
                return d2 || [];
            }
            throw workingError;
        },
```

Replace the `updateById` method:

```javascript
        async updateById(id, patch) {
            const { data, error } = await supabase.from(M)
                .update(patch)
                .eq('id', id)
                .select('id, content, scope, category, created_at')
                .limit(1);
            if (!error) return data || [];
            if (error.message?.includes('category')) {
                const { data: d2, error: err2 } = await supabase.from(M)
                    .update(patch)
                    .eq('id', id)
                    .select('id, content, scope, created_at')
                    .limit(1);
                if (err2) throw err2;
                return d2 || [];
            }
            throw error;
        },
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx jest tests/unit/dataAccess/memoryRepo.test.js`
Expected: PASS (all existing + 7 new tests)

- [ ] **Step 5: Commit**

```bash
git add services/dataAccess/memoryRepo.js tests/unit/dataAccess/memoryRepo.test.js
git commit -m "feat: persist and return memories.category with column-missing fallback"
```

---

### Task 4: `memoryHealthRepo.js` — data access for findings

**Files:**
- Create: `services/dataAccess/memoryHealthRepo.js`
- Modify: `services/dataAccess/index.js`
- Test: `tests/unit/dataAccess/memoryHealthRepo.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
// tests/unit/dataAccess/memoryHealthRepo.test.js
'use strict';

const { createMemoryHealthRepo } = require('../../../services/dataAccess/memoryHealthRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('memoryHealthRepo', () => {
    test('listFindings defaults to status=pending', async () => {
        const chain = makeChain([{ id: 'f1', type: 'duplicate', status: 'pending' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const rows = await repo.listFindings();
        expect(chain.eq).toHaveBeenCalledWith('status', 'pending');
        expect(rows).toEqual([{ id: 'f1', type: 'duplicate', status: 'pending' }]);
    });

    test('listFindings filters by type when provided', async () => {
        const chain = makeChain([]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        await repo.listFindings({ status: 'pending', type: 'conflict' });
        expect(chain.eq).toHaveBeenCalledWith('type', 'conflict');
    });

    test('findExisting looks up by type + memory_id + related_memory_id', async () => {
        const chain = makeChain([{ id: 'f1' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const row = await repo.findExisting('duplicate', '1', '2');
        expect(chain.eq).toHaveBeenCalledWith('type', 'duplicate');
        expect(chain.eq).toHaveBeenCalledWith('memory_id', '1');
        expect(chain.eq).toHaveBeenCalledWith('related_memory_id', '2');
        expect(row).toEqual({ id: 'f1' });
    });

    test('findExisting uses .is for a null related_memory_id', async () => {
        const chain = makeChain([]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        await repo.findExisting('stale', '1', null);
        expect(chain.is).toHaveBeenCalledWith('related_memory_id', null);
    });

    test('insertFinding returns the inserted row', async () => {
        const chain = makeChain([{ id: 'f2', type: 'stale' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const row = await repo.insertFinding({ type: 'stale', memory_id: '3' });
        expect(chain.insert).toHaveBeenCalledWith([{ type: 'stale', memory_id: '3' }]);
        expect(row).toEqual({ id: 'f2', type: 'stale' });
    });

    test('setStatus sets resolved_at for a non-pending status', async () => {
        const chain = makeChain([{ id: 'f3', status: 'approved' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        await repo.setStatus('f3', 'approved');
        const [patch] = chain.update.mock.calls[0];
        expect(patch.status).toBe('approved');
        expect(typeof patch.resolved_at).toBe('string');
    });

    test('getById returns null when no row matches', async () => {
        const chain = makeChain([]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        expect(await repo.getById('missing')).toBeNull();
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx jest tests/unit/dataAccess/memoryHealthRepo.test.js`
Expected: FAIL — `Cannot find module '../../../services/dataAccess/memoryHealthRepo'`

- [ ] **Step 3: Write the implementation**

```javascript
// services/dataAccess/memoryHealthRepo.js
'use strict';

// Thin data-access layer over memory_health_findings. Business logic (when to
// upsert vs. leave a resolved finding alone, content-hash comparisons) lives
// in services/memoryHealthCheck.js — this repo only talks to Supabase.

const H = 'memory_health_findings';

function createMemoryHealthRepo(supabase) {
    return {
        async listFindings({ status = 'pending', type } = {}) {
            let query = supabase.from(H).select('*');
            if (status) query = query.eq('status', status);
            if (type) query = query.eq('type', type);
            const { data, error } = await query.order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        async findExisting(type, memoryId, relatedMemoryId) {
            let query = supabase.from(H).select('*').eq('type', type).eq('memory_id', memoryId);
            query = relatedMemoryId
                ? query.eq('related_memory_id', relatedMemoryId)
                : query.is('related_memory_id', null);
            const { data, error } = await query.limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async insertFinding(row) {
            const { data, error } = await supabase.from(H).insert([row]).select('*').limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async updateFinding(id, patch) {
            const { data, error } = await supabase.from(H).update(patch).eq('id', id).select('*').limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async getById(id) {
            const { data, error } = await supabase.from(H).select('*').eq('id', id).limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async setStatus(id, status) {
            const patch = { status };
            if (status !== 'pending') patch.resolved_at = new Date().toISOString();
            const { data, error } = await supabase.from(H).update(patch).eq('id', id).select('*').limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },
    };
}

module.exports = { createMemoryHealthRepo };
```

Wire it into `services/dataAccess/index.js`: add near the other `require`s

```javascript
const { createMemoryHealthRepo } = require('./memoryHealthRepo');
```

and inside `createRepos(supabase)`'s returned object, add (next to `memories:`):

```javascript
        memoryHealth: createMemoryHealthRepo(supabase),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx jest tests/unit/dataAccess/memoryHealthRepo.test.js`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add services/dataAccess/memoryHealthRepo.js services/dataAccess/index.js tests/unit/dataAccess/memoryHealthRepo.test.js
git commit -m "feat: add memoryHealthRepo data-access layer"
```

---

### Task 5: Wire the fake into `tests/helpers/fakeRepos.js`

**Files:**
- Modify: `tests/helpers/fakeRepos.js`

- [ ] **Step 1: Add `makeMemoryHealthRepo` and wire it into `makeRepos`**

Add this function near `makeCronRepo` in `tests/helpers/fakeRepos.js`:

```javascript
function makeMemoryHealthRepo(opts = {}) {
    const { rows = [], byId = {} } = opts;
    return {
        listFindings:  jest.fn(async () => rows),
        findExisting:  jest.fn(async () => null),
        insertFinding: jest.fn(async (row) => ({ id: 'f-' + Math.random().toString(36).slice(2), ...row })),
        updateFinding: jest.fn(async (id, patch) => ({ id, ...patch })),
        getById:       jest.fn(async (id) => byId[id] || rows.find(r => String(r.id) === String(id)) || null),
        setStatus:     jest.fn(async (id, status) => ({ id, status })),
    };
}
```

In `makeRepos(tableData = {})`, add a line next to `memories:`:

```javascript
        memoryHealth: makeMemoryHealthRepo({ rows: tableData.memory_health_findings || [] }),
```

In `module.exports`, add `makeMemoryHealthRepo` to the exported list.

- [ ] **Step 2: Verify the existing suite still passes with the new fake present**

Run: `npx jest tests/unit/dataAccess tests/integration/memoriesRoutes.test.js`
Expected: PASS — this is purely additive, no existing fake behavior changed.

- [ ] **Step 3: Commit**

```bash
git add tests/helpers/fakeRepos.js
git commit -m "test: add makeMemoryHealthRepo fake"
```

---

### Task 6: `services/memoryHealthCheck.js` — detection engine

**Files:**
- Create: `services/memoryHealthCheck.js`
- Test: `tests/unit/memoryHealthCheck.test.js`

- [ ] **Step 1: Write the failing tests**

```javascript
// tests/unit/memoryHealthCheck.test.js
'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
    isReady: jest.fn().mockReturnValue(true),
    searchMemoriesDetailed: jest.fn(),
    listAll: jest.fn().mockResolvedValue([]),
    upsertMemory: jest.fn().mockResolvedValue(true),
    deleteMemory: jest.fn().mockResolvedValue(),
}));
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const pinecone = require('../../services/pineconeMemory');
const { classifyCategory } = require('../../services/memoryCategory');
const { runHealthScan } = require('../../services/memoryHealthCheck');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => {
    jest.clearAllMocks();
    pinecone.isReady.mockReturnValue(true);
    pinecone.searchMemoriesDetailed.mockResolvedValue([]);
    pinecone.listAll.mockResolvedValue([]);
    classifyCategory.mockResolvedValue('כללי');
});

const longTermMem = (id, content, extra = {}) => ({
    id, content, scope: 'long_term', status: 'approved', created_at: new Date().toISOString(), ...extra,
});

describe('runHealthScan — duplicates', () => {
    test('creates a duplicate finding with a merge suggestion above 0.92', async () => {
        // Content is deliberately ≥5 words and category is pre-set to match the
        // mocked classifier — otherwise the thin_content or category_mismatch
        // detectors would also fire and break the exact-call-count assertion below.
        const memA = longTermMem(1, 'אני אוהב לשתות קפה שחור כל בוקר', { category: 'כללי' });
        const memB = longTermMem(2, 'אני שותה קפה שחור בכל בוקר בשבוע', { category: 'כללי' });
        const repos = makeRepos({ memories: [memA, memB] });
        pinecone.searchMemoriesDetailed.mockImplementation(async (query) => {
            if (query === memA.content) return [{ id: '1', content: memA.content, score: 1 }, { id: '2', content: memB.content, score: 0.95 }];
            return [{ id: '2', content: memB.content, score: 1 }, { id: '1', content: memA.content, score: 0.95 }];
        });
        callGemma4.mockResolvedValue('{"merged":"אוהב לשתות קפה שחור כל בוקר"}');

        const summary = await runHealthScan(repos);

        expect(repos.memoryHealth.insertFinding).toHaveBeenCalledTimes(1);
        const [row] = repos.memoryHealth.insertFinding.mock.calls[0];
        expect(row.type).toBe('duplicate');
        expect(row.suggested_action).toBe('merge');
        expect(row.suggested_payload.mergedContent).toBe('אוהב לשתות קפה שחור כל בוקר');
        expect(summary.created).toBe(1);
    });

    test('does not flag the memory against itself', async () => {
        const mem = longTermMem(1, 'תוכן ייחודי שלא דומה לשום זיכרון אחר בכלל', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });
        pinecone.searchMemoriesDetailed.mockResolvedValue([{ id: '1', content: mem.content, score: 1 }]);

        await runHealthScan(repos);

        expect(repos.memoryHealth.insertFinding).not.toHaveBeenCalled();
    });
});

describe('runHealthScan — conflicts', () => {
    test('creates a conflict finding in the 0.70-0.92 band with an archive suggestion', async () => {
        const memA = longTermMem(1, 'עובד בחברת נאווה כבר שלוש שנים', { category: 'כללי' });
        const memB = longTermMem(2, 'התחיל תפקיד חדש בחברת קוואנטום סופט', { category: 'כללי' });
        const repos = makeRepos({ memories: [memA, memB] });
        pinecone.searchMemoriesDetailed.mockImplementation(async (query) => {
            if (query === memA.content) return [{ id: '1', content: memA.content, score: 1 }, { id: '2', content: memB.content, score: 0.8 }];
            return [{ id: '2', content: memB.content, score: 1 }, { id: '1', content: memA.content, score: 0.8 }];
        });

        const summary = await runHealthScan(repos);

        expect(repos.memoryHealth.insertFinding).toHaveBeenCalledTimes(1);
        const [row] = repos.memoryHealth.insertFinding.mock.calls[0];
        expect(row.type).toBe('conflict');
        expect(row.suggested_action).toBe('archive');
        expect(callGemma4).not.toHaveBeenCalled(); // no merge synthesis for conflicts
        expect(summary.created).toBe(1);
    });
});

describe('runHealthScan — category', () => {
    test('backfills a null category directly without creating a finding', async () => {
        const mem = longTermMem(1, 'יש לו פגישה עם הרופא', { category: null });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('בריאות');

        const summary = await runHealthScan(repos);

        expect(repos.memories.updateById).toHaveBeenCalledWith(1, { category: 'בריאות' });
        expect(repos.memoryHealth.insertFinding).not.toHaveBeenCalledWith(
            expect.objectContaining({ type: 'category_mismatch' }));
        expect(summary.autoResolved).toBeGreaterThanOrEqual(1);
    });

    test('creates a category_mismatch finding when an already-categorized memory disagrees', async () => {
        const mem = longTermMem(1, 'קונה כרטיסים למשחק כדורגל', { category: 'משפחה' });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('תחביב');

        const summary = await runHealthScan(repos);

        const call = repos.memoryHealth.insertFinding.mock.calls.find(([r]) => r.type === 'category_mismatch');
        expect(call[0].suggested_action).toBe('move');
        expect(call[0].suggested_payload).toEqual({ category: 'תחביב' });
        expect(summary.created).toBeGreaterThanOrEqual(1);
    });

    test('does nothing when the classified category matches the stored one', async () => {
        const mem = longTermMem(1, 'תוכן כלשהו', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('כללי');

        await runHealthScan(repos);

        expect(repos.memories.updateById).not.toHaveBeenCalled();
        expect(repos.memoryHealth.insertFinding).not.toHaveBeenCalledWith(
            expect.objectContaining({ type: 'category_mismatch' }));
    });
});

describe('runHealthScan — stale and thin content', () => {
    test('flags content under 5 words as thin_content', async () => {
        const mem = longTermMem(1, 'אוהב פיצה', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });

        await runHealthScan(repos);

        const call = repos.memoryHealth.insertFinding.mock.calls.find(([r]) => r.type === 'thin_content');
        expect(call[0].suggested_action).toBe('delete');
    });

    test('flags a long_term memory older than 6 months as stale', async () => {
        const old = new Date(Date.now() - 200 * 24 * 60 * 60 * 1000).toISOString();
        const mem = longTermMem(1, 'מתכנן לנסוע לטיול בתאילנד בקיץ הקרוב', { category: 'כללי', created_at: old });
        const repos = makeRepos({ memories: [mem] });

        await runHealthScan(repos);

        const call = repos.memoryHealth.insertFinding.mock.calls.find(([r]) => r.type === 'stale');
        expect(call[0].suggested_action).toBe('archive');
    });
});

describe('runHealthScan — orphans (auto-resolved, no approval needed)', () => {
    test('re-upserts a Supabase row missing from Pinecone', async () => {
        const mem = longTermMem(1, 'זיכרון תקין', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });
        pinecone.listAll.mockResolvedValue([]); // no vectors at all → row 1 is orphaned

        const summary = await runHealthScan(repos);

        expect(pinecone.upsertMemory).toHaveBeenCalledWith(1, 'זיכרון תקין');
        expect(summary.autoResolved).toBeGreaterThanOrEqual(1);
    });

    test('deletes a Pinecone vector missing from Supabase', async () => {
        const repos = makeRepos({ memories: [] });
        pinecone.listAll.mockResolvedValue([{ id: '99', content: 'orphaned vector' }]);

        await runHealthScan(repos);

        expect(pinecone.deleteMemory).toHaveBeenCalledWith('99');
    });

    test('skips pending-status rows — they are intentionally excluded from Pinecone', async () => {
        const pendingMem = { id: 5, content: 'ממתין לאישור', scope: 'session', status: 'pending', created_at: new Date().toISOString() };
        const repos = makeRepos({ memories: [pendingMem] });
        pinecone.listAll.mockResolvedValue([]);

        await runHealthScan(repos);

        expect(pinecone.upsertMemory).not.toHaveBeenCalledWith(5, expect.anything());
    });
});

describe('runHealthScan — skips detection when Pinecone is not ready', () => {
    test('skips duplicate/conflict scan but still runs category/stale/thin', async () => {
        pinecone.isReady.mockReturnValue(false);
        const mem = longTermMem(1, 'אוהב פיצה', { category: null });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('כללי');

        await runHealthScan(repos);

        expect(pinecone.searchMemoriesDetailed).not.toHaveBeenCalled();
        expect(repos.memories.updateById).toHaveBeenCalledWith(1, { category: 'כללי' });
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/unit/memoryHealthCheck.test.js`
Expected: FAIL — `Cannot find module '../../services/memoryHealthCheck'`

- [ ] **Step 3: Write the implementation**

```javascript
// services/memoryHealthCheck.js
'use strict';

// Batch health scan over existing memories — duplicates, conflicts, category
// mismatches, and stale/thin/orphaned entries. Extends the same Pinecone
// cosine-similarity thresholds agents/memoryAgent.js uses at creation time
// (checkDuplicate/findConflict), but cannot call those functions directly:
// a memory already indexed in Pinecone is always its own closest neighbour,
// so this uses searchMemoriesDetailed with topK > 1 and filters out the
// query memory itself before applying the same 0.70/0.92 thresholds.

const crypto = require('crypto');
const { callGemma4 } = require('../agents/models');
const { extractJSON } = require('../agents/utils');
const pinecone = require('./pineconeMemory');
const { classifyCategory } = require('./memoryCategory');

const DUPLICATE_THRESHOLD = 0.92;
const CONFLICT_THRESHOLD  = 0.70;
const STALE_MS   = 6 * 30 * 24 * 60 * 60 * 1000; // ~6 months
const THIN_WORDS = 5;

function hashContent(str) {
    return crypto.createHash('sha1').update(str || '').digest('hex');
}

function hashPair(a, b) {
    return hashContent([a, b].sort().join('|'));
}

async function synthesizeMerge(contentA, contentB, useLocal = false) {
    const prompt = `מזג את שני הזיכרונות הבאים למשפט אחד קצר וברור בעברית, ללא כפילות מידע:
A: ${contentA}
B: ${contentB}
החזר JSON בלבד: {"merged": "התוכן הממוזג"}`;
    try {
        const aiText = await callGemma4([{ role: 'user', content: prompt }], useLocal, 150);
        const parsed = extractJSON(aiText);
        const merged = (parsed?.merged || '').trim();
        return merged || `${contentA} / ${contentB}`;
    } catch (err) {
        console.error('[memoryHealthCheck] merge synthesis error (using naive join):', err.message);
        return `${contentA} / ${contentB}`;
    }
}

// Insert-or-refresh a pending finding; leaves an already-resolved finding
// alone unless the underlying content changed since it was last resolved.
async function upsertFinding(repos, { type, memoryId, relatedMemoryId = null, suggestedAction, suggestedPayload = null, score = null, contentHash }) {
    const existing = await repos.memoryHealth.findExisting(type, memoryId, relatedMemoryId);
    const patch = {
        suggested_action: suggestedAction,
        suggested_payload: suggestedPayload,
        score,
        content_hash: contentHash,
    };

    if (!existing) {
        await repos.memoryHealth.insertFinding({
            type, memory_id: memoryId, related_memory_id: relatedMemoryId,
            status: 'pending', ...patch,
        });
        return 'created';
    }
    if (existing.status === 'pending') {
        await repos.memoryHealth.updateFinding(existing.id, patch);
        return 'updated';
    }
    if (existing.content_hash !== contentHash) {
        await repos.memoryHealth.updateFinding(existing.id, { ...patch, status: 'pending', resolved_at: null });
        return 'updated';
    }
    return 'skipped';
}

async function recordAutoResolved(repos, { type, memoryId, suggestedAction }) {
    await repos.memoryHealth.insertFinding({
        type, memory_id: memoryId, related_memory_id: null,
        suggested_action: suggestedAction, suggested_payload: null, score: null,
        content_hash: null, status: 'approved', resolved_at: new Date().toISOString(),
    });
}

function tally(summary, outcome) {
    if (outcome === 'created') summary.created++;
    else if (outcome === 'updated') summary.updated++;
}

async function scanDuplicatesAndConflicts(memories, repos, summary, useLocal) {
    const seenPairs = new Set();
    for (const mem of memories) {
        let hits;
        try {
            hits = await pinecone.searchMemoriesDetailed(mem.content, 3);
        } catch (err) {
            summary.errors.push(`duplicate-scan ${mem.id}: ${err.message}`);
            continue;
        }
        if (!hits) continue;
        const match = hits.find(h => String(h.id) !== String(mem.id));
        if (!match || match.score < CONFLICT_THRESHOLD) continue;

        const [aId, bId] = [String(mem.id), String(match.id)].sort();
        const pairKey = `${aId}:${bId}`;
        if (seenPairs.has(pairKey)) continue;
        seenPairs.add(pairKey);

        const isDuplicate = match.score > DUPLICATE_THRESHOLD;
        let suggestedPayload = null;
        if (isDuplicate) {
            const merged = await synthesizeMerge(mem.content, match.content, useLocal);
            suggestedPayload = { mergedContent: merged };
        }

        const outcome = await upsertFinding(repos, {
            type: isDuplicate ? 'duplicate' : 'conflict',
            memoryId: aId, relatedMemoryId: bId,
            suggestedAction: isDuplicate ? 'merge' : 'archive',
            suggestedPayload, score: match.score,
            contentHash: hashPair(mem.content, match.content),
        });
        tally(summary, outcome);
    }
}

async function scanCategoryMismatch(memories, repos, summary, useLocal) {
    for (const mem of memories) {
        let suggested;
        try {
            suggested = await classifyCategory(mem.content, useLocal);
        } catch (err) {
            summary.errors.push(`category ${mem.id}: ${err.message}`);
            continue;
        }

        if (!mem.category) {
            // Never classified before (predates this feature). Backfilling
            // absent metadata isn't a user-visible change, so no approval needed.
            try {
                await repos.memories.updateById(mem.id, { category: suggested });
                summary.autoResolved++;
            } catch (err) {
                summary.errors.push(`category-backfill ${mem.id}: ${err.message}`);
            }
            continue;
        }

        if (suggested === mem.category) continue;

        const outcome = await upsertFinding(repos, {
            type: 'category_mismatch', memoryId: String(mem.id),
            suggestedAction: 'move', suggestedPayload: { category: suggested },
            contentHash: hashContent(mem.content),
        });
        tally(summary, outcome);
    }
}

async function scanStaleAndThin(memories, repos, summary) {
    const staleCutoff = Date.now() - STALE_MS;
    for (const mem of memories) {
        const core = (mem.content || '').replace(/^\[[^\]]+\]\s*/, '').trim();
        const wordCount = core ? core.split(/\s+/).length : 0;

        if (wordCount > 0 && wordCount < THIN_WORDS) {
            const outcome = await upsertFinding(repos, {
                type: 'thin_content', memoryId: String(mem.id),
                suggestedAction: 'delete', suggestedPayload: null,
                contentHash: hashContent(mem.content),
            });
            tally(summary, outcome);
            continue; // thin takes priority over stale for the same memory
        }

        if (mem.created_at && new Date(mem.created_at).getTime() < staleCutoff) {
            const outcome = await upsertFinding(repos, {
                type: 'stale', memoryId: String(mem.id),
                suggestedAction: 'archive', suggestedPayload: null,
                contentHash: hashContent(mem.content),
            });
            tally(summary, outcome);
        }
    }
}

async function scanOrphans(repos, summary) {
    if (!pinecone.isReady()) return;
    const [pineconeRecords, supabaseRows] = await Promise.all([
        pinecone.listAll(),
        repos.memories.listAll(),
    ]);
    const supabaseIds = new Set(supabaseRows.map(r => String(r.id)));
    const pineconeIds = new Set(pineconeRecords.map(r => String(r.id)));

    for (const row of supabaseRows) {
        if (pineconeIds.has(String(row.id))) continue;
        if ((row.status || 'approved') === 'pending') continue; // intentionally excluded
        try {
            await pinecone.upsertMemory(row.id, row.content);
            await recordAutoResolved(repos, { type: 'orphaned_row', memoryId: String(row.id), suggestedAction: 'resync' });
            summary.autoResolved++;
        } catch (err) {
            summary.errors.push(`resync-row ${row.id}: ${err.message}`);
        }
    }

    for (const rec of pineconeRecords) {
        if (supabaseIds.has(String(rec.id))) continue;
        try {
            await pinecone.deleteMemory(rec.id);
            await recordAutoResolved(repos, { type: 'orphaned_vector', memoryId: String(rec.id), suggestedAction: 'resync' });
            summary.autoResolved++;
        } catch (err) {
            summary.errors.push(`resync-vector ${rec.id}: ${err.message}`);
        }
    }
}

async function runHealthScan(repos, { useLocal = false } = {}) {
    const summary = { created: 0, updated: 0, autoResolved: 0, errors: [] };
    const allMemories = await repos.memories.listAll();
    const inScope = allMemories.filter(m =>
        (m.scope || 'long_term') === 'long_term' && (m.status || 'approved') === 'approved');

    if (pinecone.isReady()) {
        await scanDuplicatesAndConflicts(inScope, repos, summary, useLocal);
    }
    await scanCategoryMismatch(inScope, repos, summary, useLocal);
    await scanStaleAndThin(inScope, repos, summary);
    await scanOrphans(repos, summary);

    return summary;
}

module.exports = { runHealthScan };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx jest tests/unit/memoryHealthCheck.test.js`
Expected: PASS (13 tests)

- [ ] **Step 5: Commit**

```bash
git add services/memoryHealthCheck.js tests/unit/memoryHealthCheck.test.js
git commit -m "feat: add memoryHealthCheck batch scan engine"
```

---

### Task 7: `services/memoryHealthActions.js` — resolution engine

**Files:**
- Create: `services/memoryHealthActions.js`
- Test: `tests/unit/memoryHealthActions.test.js`

- [ ] **Step 1: Write the failing tests**

```javascript
// tests/unit/memoryHealthActions.test.js
'use strict';

jest.mock('../../services/pineconeMemory', () => ({
    deleteMemory: jest.fn().mockResolvedValue(),
    upsertMemory: jest.fn().mockResolvedValue(true),
}));
jest.mock('../../services/obsidianSync', () => ({ removeFromVault: jest.fn() }));
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn().mockResolvedValue('כללי') }));

const pinecone = require('../../services/pineconeMemory');
const obsidianSync = require('../../services/obsidianSync');
const { resolveFinding, ACTIONS_BY_TYPE } = require('../../services/memoryHealthActions');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => jest.clearAllMocks());

describe('resolveFinding — duplicate', () => {
    test('delete removes the non-kept side', async () => {
        const repos = makeRepos({ memories: [{ id: 1, content: 'A' }] });
        repos.memories.removeById = jest.fn(async () => [{ id: 2, content: 'B' }]);
        const finding = { type: 'duplicate', memory_id: '1', related_memory_id: '2' };
        await resolveFinding(finding, 'delete', { keepId: '1' }, repos);
        expect(repos.memories.removeById).toHaveBeenCalledWith('2');
        expect(pinecone.deleteMemory).toHaveBeenCalledWith(2);
        expect(obsidianSync.removeFromVault).toHaveBeenCalledWith('memories', { id: 2, content: 'B' });
    });

    test('merge creates a new memory and archives both originals', async () => {
        const repos = makeRepos();
        repos.memories.create = jest.fn(async () => [{ id: 9, content: 'merged text' }]);
        repos.memories.updateById = jest.fn(async () => [{ id: 1, scope: 'archive' }]);
        const finding = { type: 'duplicate', memory_id: '1', related_memory_id: '2', suggested_payload: { mergedContent: 'merged text' } };
        const row = await resolveFinding(finding, 'merge', {}, repos);
        expect(repos.memories.create).toHaveBeenCalledWith({ content: 'merged text', scope: 'long_term', category: 'כללי' });
        expect(pinecone.upsertMemory).toHaveBeenCalledWith(9, 'merged text');
        expect(repos.memories.updateById).toHaveBeenCalledWith('1', { scope: 'archive' });
        expect(repos.memories.updateById).toHaveBeenCalledWith('2', { scope: 'archive' });
        expect(row).toEqual({ id: 9, content: 'merged text' });
    });

    test('merge uses the caller-supplied payload over the stored suggestion', async () => {
        const repos = makeRepos();
        repos.memories.create = jest.fn(async () => [{ id: 9, content: 'edited by user' }]);
        repos.memories.updateById = jest.fn(async () => [{}]);
        const finding = { type: 'duplicate', memory_id: '1', related_memory_id: '2', suggested_payload: { mergedContent: 'original suggestion' } };
        await resolveFinding(finding, 'merge', { mergedContent: 'edited by user' }, repos);
        expect(repos.memories.create).toHaveBeenCalledWith({ content: 'edited by user', scope: 'long_term', category: 'כללי' });
    });
});

describe('resolveFinding — conflict', () => {
    test('archive flips the chosen memory to scope=archive', async () => {
        const repos = makeRepos();
        repos.memories.updateById = jest.fn(async () => [{ id: 2, scope: 'archive' }]);
        const finding = { type: 'conflict', memory_id: '1', related_memory_id: '2' };
        await resolveFinding(finding, 'archive', { archiveId: '2' }, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith('2', { scope: 'archive' });
        expect(pinecone.deleteMemory).toHaveBeenCalledWith('2');
    });
});

describe('resolveFinding — category_mismatch', () => {
    test('move updates the category', async () => {
        const repos = makeRepos();
        repos.memories.updateById = jest.fn(async () => [{ id: 1, category: 'תחביב' }]);
        const finding = { type: 'category_mismatch', memory_id: '1', suggested_payload: { category: 'תחביב' } };
        await resolveFinding(finding, 'move', {}, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith('1', { category: 'תחביב' });
    });
});

describe('resolveFinding — stale / thin_content', () => {
    test('stale archive archives the single memory', async () => {
        const repos = makeRepos();
        repos.memories.updateById = jest.fn(async () => [{ id: 1, scope: 'archive' }]);
        await resolveFinding({ type: 'stale', memory_id: '1' }, 'archive', {}, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith('1', { scope: 'archive' });
    });

    test('thin_content delete removes the single memory', async () => {
        const repos = makeRepos();
        repos.memories.removeById = jest.fn(async () => [{ id: 1, content: 'x' }]);
        await resolveFinding({ type: 'thin_content', memory_id: '1' }, 'delete', {}, repos);
        expect(repos.memories.removeById).toHaveBeenCalledWith('1');
    });
});

describe('resolveFinding — invalid action', () => {
    test('rejects an action not valid for the finding type with a 400-flavored error', async () => {
        const repos = makeRepos();
        await expect(resolveFinding({ type: 'thin_content', memory_id: '1' }, 'merge', {}, repos))
            .rejects.toMatchObject({ status: 400 });
    });
});

test('ACTIONS_BY_TYPE enumerates the allowed action per finding type', () => {
    expect(ACTIONS_BY_TYPE).toEqual({
        duplicate: ['delete', 'merge'],
        conflict: ['archive'],
        category_mismatch: ['move'],
        stale: ['archive'],
        thin_content: ['delete'],
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/unit/memoryHealthActions.test.js`
Expected: FAIL — `Cannot find module '../../services/memoryHealthActions'`

- [ ] **Step 3: Write the implementation**

```javascript
// services/memoryHealthActions.js
'use strict';

// Applies a chosen action for a memory-health finding, reusing the same
// primitives the manual /memories CRUD endpoints already use (Pinecone +
// Obsidian cleanup on delete, scope flip on archive, category patch on move).

const pinecone = require('./pineconeMemory');
const obsidianSync = require('./obsidianSync');
const { classifyCategory } = require('./memoryCategory');

const ACTIONS_BY_TYPE = {
    duplicate: ['delete', 'merge'],
    conflict: ['archive'],
    category_mismatch: ['move'],
    stale: ['archive'],
    thin_content: ['delete'],
};

function invalidActionError(action, type) {
    const err = new Error(`Invalid action "${action}" for finding type "${type}"`);
    err.status = 400;
    return err;
}

async function deleteMemoryById(id, repos) {
    const rows = await repos.memories.removeById(id);
    const row = rows[0];
    if (row) {
        await pinecone.deleteMemory(row.id);
        obsidianSync.removeFromVault('memories', row);
    }
    return row;
}

async function archiveMemoryById(id, repos) {
    const rows = await repos.memories.updateById(id, { scope: 'archive' });
    await pinecone.deleteMemory(id).catch(() => {});
    return rows[0];
}

async function resolveFinding(finding, action, payload, repos) {
    const allowed = ACTIONS_BY_TYPE[finding.type] || [];
    if (!allowed.includes(action)) throw invalidActionError(action, finding.type);

    if (finding.type === 'duplicate') {
        if (action === 'delete') {
            const keepId = payload.keepId;
            const deleteId = String(finding.memory_id) === String(keepId) ? finding.related_memory_id : finding.memory_id;
            return deleteMemoryById(deleteId, repos);
        }
        if (action === 'merge') {
            const content = (payload.mergedContent || finding.suggested_payload?.mergedContent || '').trim();
            if (!content) throw Object.assign(new Error('mergedContent required'), { status: 400 });
            const category = await classifyCategory(content, false);
            const inserted = await repos.memories.create({ content, scope: 'long_term', category });
            const row = inserted[0];
            if (row?.id) await pinecone.upsertMemory(row.id, content).catch(() => {});
            await archiveMemoryById(finding.memory_id, repos);
            await archiveMemoryById(finding.related_memory_id, repos);
            return row;
        }
    }

    if (finding.type === 'conflict' && action === 'archive') {
        const archiveId = payload.archiveId || finding.related_memory_id;
        return archiveMemoryById(archiveId, repos);
    }

    if (finding.type === 'category_mismatch' && action === 'move') {
        const category = payload.category || finding.suggested_payload?.category;
        const rows = await repos.memories.updateById(finding.memory_id, { category });
        return rows[0];
    }

    if (finding.type === 'stale' && action === 'archive') {
        return archiveMemoryById(finding.memory_id, repos);
    }

    if (finding.type === 'thin_content' && action === 'delete') {
        return deleteMemoryById(finding.memory_id, repos);
    }

    throw invalidActionError(action, finding.type);
}

module.exports = { resolveFinding, ACTIONS_BY_TYPE };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx jest tests/unit/memoryHealthActions.test.js`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add services/memoryHealthActions.js tests/unit/memoryHealthActions.test.js
git commit -m "feat: add memoryHealthActions resolution engine"
```

---

### Task 8: Category classification on explicit chat save (`agents/memoryAgent.js`)

**Files:**
- Modify: `agents/memoryAgent.js`
- Test: `tests/unit/memoryAgent.test.js`

- [ ] **Step 1: Write the failing test**

Append to the `describe('runMemoryAgent — save', ...)` block in `tests/unit/memoryAgent.test.js`:

```javascript
    test('classifies category fire-and-forget after saving, without blocking the reply', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] אני אוהב פיצה"}');
        const repos = makeRepos({ memories: [{ id: 1, content: '[hobby] אני אוהב פיצה' }] });
        const { classifyCategory } = require('../../services/memoryCategory');
        classifyCategory.mockResolvedValue('תחביב');

        const result = await runMemoryAgent('זכור ש אני אוהב פיצה', repos);

        // insert() itself must stay unchanged — category is applied via a
        // follow-up updateById so it never blocks the chat reply.
        expect(repos.memories.insert).toHaveBeenCalledWith({ content: '[hobby] אני אוהב פיצה', scope: 'long_term' });
        expect(result.answer).toContain('שמרתי');
        // allow the fire-and-forget promise to settle
        await new Promise(r => setImmediate(r));
        expect(repos.memories.updateById).toHaveBeenCalledWith(1, { category: 'תחביב' });
    });
```

Add the mock near the top of the file (with the other `jest.mock` calls):

```javascript
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn().mockResolvedValue('כללי') }));
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx jest tests/unit/memoryAgent.test.js -t "classifies category"`
Expected: FAIL — `repos.memories.updateById` was never called.

- [ ] **Step 3: Implement — fire-and-forget category classify after the explicit-save insert**

In `agents/memoryAgent.js`, add the import near the top:

```javascript
const { classifyCategory } = require('../services/memoryCategory');
```

In `runMemoryAgent`, find this block:

```javascript
        console.log('🧠 MemoryAgent saving:', parsed.memoryContent);
        const saved = await memories.insert({ content: parsed.memoryContent, scope: 'long_term' });
        obsidianSync.dbToVault('memories', { content: parsed.memoryContent, scope: 'long_term' });
        if (saved?.[0]?.id) pinecone.upsertMemory(saved[0].id, parsed.memoryContent).catch(() => {});
        _invalidateMemoryCache();
        return { answer: `שמרתי לפניי: ${parsed.memoryContent}` };
```

Replace it with:

```javascript
        console.log('🧠 MemoryAgent saving:', parsed.memoryContent);
        const saved = await memories.insert({ content: parsed.memoryContent, scope: 'long_term' });
        obsidianSync.dbToVault('memories', { content: parsed.memoryContent, scope: 'long_term' });
        if (saved?.[0]?.id) {
            const savedId = saved[0].id;
            pinecone.upsertMemory(savedId, parsed.memoryContent).catch(() => {});
            // Fire-and-forget: classifying/persisting the category never blocks
            // the chat reply, same idiom as the Pinecone upsert above.
            classifyCategory(parsed.memoryContent, useLocal)
                .then(category => memories.updateById(savedId, { category }))
                .catch(() => {});
        }
        _invalidateMemoryCache();
        return { answer: `שמרתי לפניי: ${parsed.memoryContent}` };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx jest tests/unit/memoryAgent.test.js`
Expected: PASS — all existing tests (including the exact-match `insert()` assertions at the other save tests) plus the new one.

- [ ] **Step 5: Commit**

```bash
git add agents/memoryAgent.js tests/unit/memoryAgent.test.js
git commit -m "feat: classify memory category fire-and-forget on explicit chat save"
```

---

### Task 9: Category classification on confirmed fact/pref saves (`services/memoryContext.js`)

**Files:**
- Modify: `services/memoryContext.js`
- Create: `tests/unit/memoryContext.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
// tests/unit/memoryContext.test.js
'use strict';

jest.mock('../../services/pineconeMemory', () => ({
    upsertMemory: jest.fn().mockResolvedValue(true),
    deleteMemory: jest.fn().mockResolvedValue(),
    isReady: jest.fn().mockReturnValue(false),
    searchMemories: jest.fn().mockResolvedValue(null),
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn(), removeFromVault: jest.fn() }));
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn() }));

const pinecone = require('../../services/pineconeMemory');
const { classifyCategory } = require('../../services/memoryCategory');
const memoryContext = require('../../services/memoryContext');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => jest.clearAllMocks());

describe('savePendingData', () => {
    test('classifies and persists a category on the new memory', async () => {
        classifyCategory.mockResolvedValue('משפחה');
        const repos = makeRepos({ memories: [{ id: 5 }] });
        await memoryContext.savePendingData({ content: '[fact] יש לי שני ילדים' }, repos);
        expect(classifyCategory).toHaveBeenCalledWith('[fact] יש לי שני ילדים', false);
        expect(repos.memories.insert).toHaveBeenCalledWith({
            content: '[fact] יש לי שני ילדים', scope: 'long_term', category: 'משפחה',
        });
    });

    test('archives the old memory when replacing an existing one', async () => {
        classifyCategory.mockResolvedValue('כללי');
        const repos = makeRepos({ memories: [{ id: 5 }] });
        await memoryContext.savePendingData({ content: '[fact] x', replacesId: 3 }, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith(3, { scope: 'archive' });
        expect(pinecone.deleteMemory).toHaveBeenCalledWith(3);
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx jest tests/unit/memoryContext.test.js`
Expected: FAIL — `repos.memories.insert` is called without `category`.

- [ ] **Step 3: Implement**

In `services/memoryContext.js`, add the import:

```javascript
const { classifyCategory } = require('./memoryCategory');
```

Replace `savePendingData`:

```javascript
async function savePendingData(pending, repos) {
    const category = await classifyCategory(pending.content, false).catch(() => null);
    const inserted = await repos.memories.insert({ content: pending.content, scope: 'long_term', category });
    if (inserted?.[0]?.id) {
        await pinecone.upsertMemory(inserted[0].id, pending.content).catch(() => {});
    }
    if (pending.replacesId) {
        await repos.memories.updateById(pending.replacesId, { scope: 'archive' });
        await pinecone.deleteMemory(pending.replacesId).catch(() => {});
        console.log('🧠 Archived old memory:', pending.replacesId);
    }
    invalidateCache();
    obsidianSync.dbToVault('memories', { content: pending.content, scope: 'long_term' });
    return { saved: true, content: pending.content };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx jest tests/unit/memoryContext.test.js`
Expected: PASS (2 tests)

Also run the full suite to confirm no regression, since `savePendingData` is mocked (not exercised directly) in every other test file that touches it:

Run: `npx jest tests/unit/memoriesConfirm.test.js tests/integration/memoriesRoutes.test.js`
Expected: PASS (unaffected — those files mock `memoryContext` entirely)

- [ ] **Step 5: Commit**

```bash
git add services/memoryContext.js tests/unit/memoryContext.test.js
git commit -m "feat: classify memory category on confirmed fact/pref saves"
```

---

### Task 10: Controller + routes — health endpoints and category on manual CRUD

**Files:**
- Modify: `controllers/memoriesController.js`
- Modify: `routes/memories.js`
- Modify: `tests/integration/memoriesRoutes.test.js`

- [ ] **Step 1: Write the failing tests**

Add these `jest.mock` calls near the top of `tests/integration/memoriesRoutes.test.js` (after the existing `jest.mock('../../agents/memoryAgent', ...)` line):

```javascript
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn().mockResolvedValue('כללי') }));
jest.mock('../../services/memoryHealthCheck', () => ({ runHealthScan: jest.fn() }));
jest.mock('../../services/memoryHealthActions', () => ({ resolveFinding: jest.fn() }));
```

Add the corresponding `require`s near the other imports:

```javascript
const memoryHealthCheck = require('../../services/memoryHealthCheck');
const memoryHealthActions = require('../../services/memoryHealthActions');
```

Append these `describe` blocks at the end of the file:

```javascript
describe('GET /memories/health/findings', () => {
  test('lists pending findings by default', async () => {
    const repos = makeRepos();
    repos.memoryHealth.listFindings = jest.fn(async () => [{ id: 'f1', type: 'duplicate', status: 'pending' }]);
    const res = await request(mountApp(repos)).get('/memories/health/findings');
    expect(res.status).toBe(200);
    expect(res.body.findings).toEqual([{ id: 'f1', type: 'duplicate', status: 'pending' }]);
  });
});

describe('POST /memories/health/run', () => {
  test('runs the scan and returns the summary', async () => {
    memoryHealthCheck.runHealthScan.mockResolvedValue({ created: 2, updated: 1, autoResolved: 0, errors: [] });
    const res = await request(mountApp(makeRepos())).post('/memories/health/run');
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ ok: true, created: 2, updated: 1 });
  });
});

describe('POST /memories/health/findings/:id/resolve', () => {
  test('404s when the finding is missing or already resolved', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => null);
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/resolve').send({ action: 'delete' });
    expect(res.status).toBe(404);
  });

  test('applies the action and marks the finding approved', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => ({ id: 'f1', type: 'thin_content', status: 'pending', memory_id: '1' }));
    repos.memoryHealth.setStatus = jest.fn(async (id, status) => ({ id, status }));
    memoryHealthActions.resolveFinding.mockResolvedValue({ id: 1 });
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/resolve').send({ action: 'delete' });
    expect(res.status).toBe(200);
    expect(memoryHealthActions.resolveFinding).toHaveBeenCalled();
    expect(repos.memoryHealth.setStatus).toHaveBeenCalledWith('f1', 'approved');
  });

  test('propagates a 400 from an invalid action', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => ({ id: 'f1', type: 'thin_content', status: 'pending', memory_id: '1' }));
    const err = new Error('Invalid action "merge" for finding type "thin_content"');
    err.status = 400;
    memoryHealthActions.resolveFinding.mockRejectedValue(err);
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/resolve').send({ action: 'merge' });
    expect(res.status).toBe(400);
  });
});

describe('POST /memories/health/findings/:id/dismiss', () => {
  test('marks the finding rejected', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => ({ id: 'f1', status: 'pending' }));
    repos.memoryHealth.setStatus = jest.fn(async (id, status) => ({ id, status }));
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/dismiss');
    expect(res.status).toBe(200);
    expect(repos.memoryHealth.setStatus).toHaveBeenCalledWith('f1', 'rejected');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/integration/memoriesRoutes.test.js`
Expected: FAIL — the new routes 404 (not yet defined).

- [ ] **Step 3: Implement — controller handlers**

In `controllers/memoriesController.js`, add imports near the top:

```javascript
const { classifyCategory } = require('../services/memoryCategory');
const memoryHealthCheck = require('../services/memoryHealthCheck');
const memoryHealthActions = require('../services/memoryHealthActions');
```

Replace the `create` method:

```javascript
    async create(req, res) {
      try {
        const { content, scope = 'long_term' } = req.body;
        if (!content || typeof content !== 'string' || !content.trim()) {
          return res.status(400).json({ error: 'content is required' });
        }
        const trimmed = content.trim();
        const category = await classifyCategory(trimmed, false).catch(() => null);
        const data = await repos.memories.create({ content: trimmed, scope, category });
        const row = data?.[0];
        if (row?.id) {
          pinecone.upsertMemory(row.id, row.content).catch(() => {});
          obsidianSync.dbToVault('memories', row);
        }
        memoryContext.invalidateCache();
        res.json({ memory: row });
      } catch (err) {
        console.error('POST /memories error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
```

Replace the `update` method:

```javascript
    async update(req, res) {
      try {
        const { id } = req.params;
        const { content, scope } = req.body;
        if (!content || typeof content !== 'string' || !content.trim()) {
          return res.status(400).json({ error: 'content is required' });
        }
        const trimmed = content.trim();
        const category = await classifyCategory(trimmed, false).catch(() => null);
        const patch = { content: trimmed, category };
        if (scope) patch.scope = scope;
        const data = await repos.memories.updateById(id, patch);
        if (!data || data.length === 0) return res.status(404).json({ error: 'Memory not found' });
        pinecone.upsertMemory(data[0].id, data[0].content).catch(() => {});
        obsidianSync.dbToVault('memories', data[0]);
        memoryContext.invalidateCache();
        res.json({ memory: data[0] });
      } catch (err) {
        console.error('PUT /memories/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
```

Add four new methods to the returned object (e.g. right after `confirm`, before the closing `};`):

```javascript
    async listHealthFindings(req, res) {
      try {
        const { status = 'pending', type } = req.query;
        const data = await repos.memoryHealth.listFindings({ status, type });
        res.json({ findings: data });
      } catch (err) {
        console.error('GET /memories/health/findings error:', err.message);
        res.json({ findings: [] });
      }
    },

    async runHealthScan(_req, res) {
      try {
        const summary = await memoryHealthCheck.runHealthScan(repos);
        memoryContext.invalidateCache();
        res.json({ ok: true, ...summary });
      } catch (err) {
        console.error('POST /memories/health/run error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
      }
    },

    async resolveHealthFinding(req, res) {
      try {
        const { id } = req.params;
        const { action, payload = {} } = req.body;
        const finding = await repos.memoryHealth.getById(id);
        if (!finding || finding.status !== 'pending') {
          return res.status(404).json({ error: 'Finding not found or already resolved' });
        }
        await memoryHealthActions.resolveFinding(finding, action, payload, repos);
        const updated = await repos.memoryHealth.setStatus(id, 'approved');
        memoryContext.invalidateCache();
        res.json({ ok: true, finding: updated });
      } catch (err) {
        console.error('POST /memories/health/findings/:id/resolve error:', err.message);
        res.status(err.status || 500).json({ error: err.status ? err.message : 'Internal server error' });
      }
    },

    async dismissHealthFinding(req, res) {
      try {
        const { id } = req.params;
        const finding = await repos.memoryHealth.getById(id);
        if (!finding || finding.status !== 'pending') {
          return res.status(404).json({ error: 'Finding not found or already resolved' });
        }
        const updated = await repos.memoryHealth.setStatus(id, 'rejected');
        res.json({ ok: true, finding: updated });
      } catch (err) {
        console.error('POST /memories/health/findings/:id/dismiss error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
```

- [ ] **Step 4: Implement — routes**

In `routes/memories.js`, insert the four new routes before `router.post('/:id/approve', ...)`:

```javascript
  router.get('/health/findings', controller.listHealthFindings);
  router.post('/health/run', controller.runHealthScan);
  router.post('/health/findings/:id/resolve', requirePolicy('memory.delete', { sensitive: true, irreversible: true }), controller.resolveHealthFinding);
  router.post('/health/findings/:id/dismiss', controller.dismissHealthFinding);
  router.post('/:id/approve', controller.approve);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npx jest tests/integration/memoriesRoutes.test.js`
Expected: PASS — all existing tests plus the new health-endpoint tests (12 total describe blocks)

- [ ] **Step 6: Commit**

```bash
git add controllers/memoriesController.js routes/memories.js tests/integration/memoriesRoutes.test.js
git commit -m "feat: add memory health check endpoints and category on manual CRUD"
```

---

### Task 11: Cron job + rate limiter (`server.js`)

**Files:**
- Modify: `server.js`

- [ ] **Step 1: Add the rate limiter**

In `server.js`, find:

```javascript
app.use('/memories',      _rl(60));
```

Insert a new line directly before it (more specific path first, matching the `/scan/errors` convention of a tighter limit for an expensive scan):

```javascript
app.use('/memories/health/run', _rl(5));
app.use('/memories',      _rl(60));
```

- [ ] **Step 2: Add the cron job**

Find the `memory_cleanup_nightly` cron block:

```javascript
if (!isTestEnv) scheduledJob('memory_cleanup_nightly', '30 3 * * *', async () => {
    const res = await cleanupExpiredMemories(repos);
    if (res.deleted > 0) {
        memoryContext.invalidateCache();
        console.log(`🧹 nightly memoryCleanup: removed ${res.deleted} expired memories`);
    }
    if (res.errors?.length) console.warn('🧹 nightly memoryCleanup errors:', res.errors);
}, { timezone: 'Asia/Jerusalem' });
```

Insert a new cron job directly after it:

```javascript
// Nightly memory health scan — 03:35 Jerusalem (after the 03:30 cleanup pass).
// Duplicates/conflicts/category mismatches become pending findings reviewed
// in the "ידע" tab; Supabase<->Pinecone sync gaps are self-healed inline.
if (!isTestEnv) scheduledJob('memory_health_scan', '35 3 * * *', async () => {
    const memoryHealthCheck = require('./services/memoryHealthCheck');
    const summary = await memoryHealthCheck.runHealthScan(repos);
    memoryContext.invalidateCache();
    console.log(`🩺 memory health scan: +${summary.created} new, ${summary.updated} updated, ${summary.autoResolved} auto-resolved`);
    if (summary.errors.length) console.warn('🩺 memory health scan errors:', summary.errors);
}, { timezone: 'Asia/Jerusalem' });
```

- [ ] **Step 3: Verify the server still boots and existing tests pass**

Run: `npx jest tests/integration tests/unit/dataAccess tests/unit/memoryAgent.test.js tests/unit/memoryContext.test.js`
Expected: PASS — `isTestEnv` guards the cron registration, so this is inert under Jest; this run is a regression check that requiring `server.js` (as several integration tests do) still succeeds with the new lines present.

- [ ] **Step 4: Commit**

```bash
git add server.js
git commit -m "feat: schedule nightly memory health scan cron and rate-limit manual trigger"
```

---

### Task 12: Dashboard UI — replace the duplicate-scan section with the health-check panel

**Files:**
- Modify: `jarvis-brain.html`

- [ ] **Step 1: Add the CSS**

In `jarvis-brain.html`, find the existing duplicate-detection CSS block ending with:

```css
.dup-score{grid-column:1/-1;text-align:center;font-size:var(--tx-xs);color:var(--muted);border-top:1px solid var(--border);padding-top:6px;margin-top:2px}
```

Insert new rules directly after it:

```css
.health-strip{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;background:var(--card);border:1px solid var(--border);border-radius:var(--r8);padding:9px 12px;margin-bottom:10px}
.health-counts{display:flex;gap:6px;flex-wrap:wrap}
.health-chip{display:inline-flex;align-items:center;gap:5px;padding:2px 9px;border-radius:20px;font-size:var(--tx-xs);border:1px solid var(--border);font-weight:600;font-variant-numeric:tabular-nums}
.health-chip .sw{width:7px;height:7px;border-radius:50%}
.health-autofix{font-size:var(--tx-xs);color:var(--muted);padding:6px 10px;border:1px dashed var(--border);border-radius:var(--r4);margin-bottom:10px;display:none}
.health-section{margin-bottom:14px}
.health-section-title{font-size:var(--tx-xs);font-weight:700;color:var(--muted);margin-bottom:6px;display:flex;align-items:center;gap:6px}
.health-card{background:var(--card);border:1px solid var(--border);border-right:3px solid var(--tc,var(--accent));border-radius:var(--r8);padding:10px 12px;margin-bottom:8px}
.health-card-top{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:7px;font-size:var(--tx-xs);color:var(--muted)}
.health-mem{font-size:var(--tx-sm);color:var(--text);background:var(--surface);border:1px solid var(--border);border-radius:var(--r4);padding:6px 9px;margin-bottom:5px;line-height:1.45}
.health-cat-row{display:flex;align-items:center;gap:7px;font-size:var(--tx-xs);color:var(--muted);margin:6px 0}
.health-cat-pill{padding:1px 8px;border-radius:20px;font-weight:700;border:1px solid var(--border)}
.health-actions{display:flex;flex-wrap:wrap;gap:5px;margin-top:6px}
.health-merge-box{display:none;margin-top:7px}
.health-merge-box.open{display:block}
.health-merge-box textarea{width:100%;background:var(--surface);border:1px solid rgba(200,145,58,.45);border-radius:var(--r2);color:var(--text);font-family:inherit;font-size:var(--tx-sm);padding:7px 9px;resize:vertical;min-height:52px;line-height:1.45;outline:none;margin-bottom:6px}
```

- [ ] **Step 2: Replace the HTML section**

Find:

```html
      <!-- F: Duplicate Detection — full width, new -->
      <div style="margin-top:16px;padding-bottom:20px">
        <div class="sec-head">
          <div class="sec-title"><svg class="icon icon-sm"><use href="#ic-search"/></svg> זיכרונות דומים</div>
          <button class="dup-scan-btn" id="dupScanBtn" onclick="scanDuplicates()">סרוק כפילויות</button>
        </div>
        <div id="dupResults"><div class="mm-empty">לחץ "סרוק כפילויות" לאיתור זיכרונות דומים</div></div>
      </div>
```

Replace with:

```html
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

- [ ] **Step 3: Extend state and wire loading**

Find:

```javascript
const S = {
  memories: [], pending: [], trace: [], log: [], providers: {},
  stats: {}, profile: {}, filter: 'all', view3d: false,
  editId: null, pollTimer: null, provTimer: null,
  searchQ: '', highlight: null, mmSort: 'date',
  traceIntentFilter: null, profileDayFilter: null,
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
};
```

Find:

```javascript
async function reload() {
  await Promise.all([loadMemories(), loadPending(), loadTrace(), loadProviders(), loadStats()]);
  const now = new Date().toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit' });
  document.getElementById('tbTime').innerHTML = `עדכון ${now} <span class="live-dot"></span>`;
}
```

Replace with:

```javascript
async function reload() {
  await Promise.all([loadMemories(), loadPending(), loadHealthFindings(), loadTrace(), loadProviders(), loadStats()]);
  const now = new Date().toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit' });
  document.getElementById('tbTime').innerHTML = `עדכון ${now} <span class="live-dot"></span>`;
}
```

Find:

```javascript
function renderMmSection() {
  updateKnowBadge();
  renderMmPending();
  renderMmList();
}
```

Replace with:

```javascript
function renderMmSection() {
  updateKnowBadge();
  renderMmPending();
  renderMmList();
  renderHealthFindings();
}
```

Find `function updateKnowBadge() {` and its body:

```javascript
function updateKnowBadge() {
  const n = S.pending.length;
  const badge = document.getElementById('knowBadge');
  if (badge) { badge.textContent = n; badge.style.display = n > 0 ? 'inline-flex' : 'none'; }
  const sa = document.getElementById('mm-stat-approved');
  const sp = document.getElementById('mm-stat-pending');
  if (sa) sa.textContent = `✓ ${S.memories.length} מאושרים`;
  if (sp) { sp.textContent = `⏳ ${n} ממתינים`; sp.style.display = n > 0 ? 'inline-flex' : 'none'; }
}
```

Replace with (adds health findings to the tab badge count):

```javascript
function updateKnowBadge() {
  const n = S.pending.length + S.health.findings.length;
  const badge = document.getElementById('knowBadge');
  if (badge) { badge.textContent = n; badge.style.display = n > 0 ? 'inline-flex' : 'none'; }
  const sa = document.getElementById('mm-stat-approved');
  const sp = document.getElementById('mm-stat-pending');
  if (sa) sa.textContent = `✓ ${S.memories.length} מאושרים`;
  if (sp) { sp.textContent = `⏳ ${S.pending.length} ממתינים`; sp.style.display = S.pending.length > 0 ? 'inline-flex' : 'none'; }
}
```

- [ ] **Step 4: Replace the JS — remove `scanDuplicates`/`dupDelete`, add the health-check functions**

Find the entire block from the `// ── Duplicate Detection ──` comment through the end of `dupDelete`:

```javascript
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

Replace it with:

```javascript
// ── Memory Health Check ──────────────────────────────────────────────────
const HEALTH_TYPE_LABEL = {
  duplicate: 'כפילות', conflict: 'סתירה', category_mismatch: 'התאמת קטגוריה',
  stale: 'ישן', thin_content: 'תוכן דל',
};
const HEALTH_TYPE_COLOR = {
  duplicate: 'var(--accent)', conflict: 'var(--red)', category_mismatch: 'var(--blue)',
  stale: 'var(--purple)', thin_content: 'var(--purple)',
};

async function loadHealthFindings() {
  try {
    const r = await api('/memories/health/findings');
    S.health.findings = r.findings || [];
    renderHealthFindings();
  } catch (e) { console.warn('health findings:', e); }
}

async function runHealthScanUI() {
  const btn = document.getElementById('healthRunBtn');
  if (btn) { btn.disabled = true; btn.textContent = 'סורק...'; }
  try {
    const r = await api('/memories/health/run', { method: 'POST' });
    await loadHealthFindings();
    document.getElementById('healthLastRun').textContent = 'הרצה אחרונה: עכשיו';
    const fix = document.getElementById('healthAutofix');
    if (fix) {
      if (r.autoResolved > 0) {
        fix.style.display = 'block';
        fix.textContent = `🔧 ${r.autoResolved} בעיות סנכרון/קטגוריה תוקנו אוטומטית`;
      } else {
        fix.style.display = 'none';
      }
    }
  } catch (e) { alert('שגיאה בהרצת הבדיקה: ' + e.message); }
  finally { if (btn) { btn.disabled = false; btn.textContent = 'הרץ בדיקה עכשיו'; } }
}

function healthMemText(id) {
  const m = S.memories.find(x => String(x.id) === String(id));
  return m ? esc(m.content) : '(זיכרון לא נמצא)';
}

function renderHealthFindings() {
  const countsEl = document.getElementById('healthCounts');
  const resultsEl = document.getElementById('healthResults');
  if (!resultsEl) return;

  const byType = {};
  S.health.findings.forEach(f => { (byType[f.type] = byType[f.type] || []).push(f); });

  if (countsEl) {
    countsEl.innerHTML = Object.keys(HEALTH_TYPE_LABEL).map(t => `
      <span class="health-chip" style="color:${HEALTH_TYPE_COLOR[t]};border-color:${HEALTH_TYPE_COLOR[t]}55">
        <span class="sw" style="background:${HEALTH_TYPE_COLOR[t]}"></span>${HEALTH_TYPE_LABEL[t]} ${(byType[t] || []).length}
      </span>`).join('');
  }

  if (!S.health.findings.length) {
    resultsEl.innerHTML = '<div class="mm-empty">אין ממצאים ממתינים ✓</div>';
    return;
  }

  resultsEl.innerHTML = Object.entries(byType).map(([type, findings]) => `
    <div class="health-section">
      <div class="health-section-title">${HEALTH_TYPE_LABEL[type]} · ${findings.length}</div>
      ${findings.map(f => renderHealthCard(f)).join('')}
    </div>`).join('');
}

function renderHealthCard(f) {
  const color = HEALTH_TYPE_COLOR[f.type];
  const pct = f.score ? Math.round(f.score * 100) + '% דמיון' : '';
  const id = esc(f.id);

  let body = '';
  let actions = '';

  if (f.type === 'duplicate' || f.type === 'conflict') {
    body = `
      <div class="health-mem">A: ${healthMemText(f.memory_id)}</div>
      <div class="health-mem">B: ${healthMemText(f.related_memory_id)}</div>`;
    if (f.type === 'duplicate') {
      actions = `
        <button class="mm-icon-btn del" onclick="resolveHealthFinding('${id}','delete',{keepId:'${esc(f.related_memory_id)}'})">מחק את A</button>
        <button class="mm-icon-btn del" onclick="resolveHealthFinding('${id}','delete',{keepId:'${esc(f.memory_id)}'})">מחק את B</button>
        <button class="mm-icon-btn" onclick="toggleMergeBox('${id}')">✳ אחד</button>
        <button class="mm-icon-btn" onclick="dismissHealthFinding('${id}')">התעלם</button>`;
      body += `
        <div class="health-merge-box" id="mergeBox-${id}">
          <textarea id="mergeText-${id}">${esc(f.suggested_payload?.mergedContent || '')}</textarea>
          <button class="mm-icon-btn save" onclick="submitMerge('${id}')">שמור מיזוג</button>
          <button class="mm-icon-btn" onclick="toggleMergeBox('${id}')">ביטול</button>
        </div>`;
    } else {
      actions = `
        <button class="mm-icon-btn" onclick="resolveHealthFinding('${id}','archive',{archiveId:'${esc(f.related_memory_id)}'})">השאר את A, ארכב את B</button>
        <button class="mm-icon-btn" onclick="resolveHealthFinding('${id}','archive',{archiveId:'${esc(f.memory_id)}'})">השאר את B, ארכב את A</button>
        <button class="mm-icon-btn" onclick="dismissHealthFinding('${id}')">התעלם</button>`;
    }
  } else if (f.type === 'category_mismatch') {
    const cur = S.memories.find(x => String(x.id) === String(f.memory_id))?.category || '—';
    const suggested = f.suggested_payload?.category || '—';
    body = `
      <div class="health-mem">${healthMemText(f.memory_id)}</div>
      <div class="health-cat-row">מסווג: <span class="health-cat-pill">${esc(cur)}</span> → מוצע: <span class="health-cat-pill" style="color:var(--green)">${esc(suggested)}</span></div>`;
    actions = `
      <button class="mm-icon-btn save" onclick="resolveHealthFinding('${id}','move',{category:'${esc(suggested)}'})">עדכן לקטגוריה: ${esc(suggested)}</button>
      <button class="mm-icon-btn" onclick="dismissHealthFinding('${id}')">השאר</button>`;
  } else if (f.type === 'stale') {
    body = `<div class="health-mem">${healthMemText(f.memory_id)}</div>`;
    actions = `
      <button class="mm-icon-btn del" onclick="resolveHealthFinding('${id}','archive',{})">ארכב</button>
      <button class="mm-icon-btn" onclick="dismissHealthFinding('${id}')">השאר — עדיין רלוונטי</button>`;
  } else if (f.type === 'thin_content') {
    body = `<div class="health-mem">${healthMemText(f.memory_id)}</div>`;
    actions = `
      <button class="mm-icon-btn del" onclick="resolveHealthFinding('${id}','delete',{})">מחק</button>
      <button class="mm-icon-btn" onclick="dismissHealthFinding('${id}')">השאר</button>`;
  }

  return `<div class="health-card" id="health-${id}" style="--tc:${color}">
    <div class="health-card-top"><span>${HEALTH_TYPE_LABEL[f.type]}</span><span>${pct}</span></div>
    ${body}
    <div class="health-actions">${actions}</div>
  </div>`;
}

function toggleMergeBox(id) {
  document.getElementById('mergeBox-' + id)?.classList.toggle('open');
}

function submitMerge(id) {
  const content = document.getElementById('mergeText-' + id)?.value.trim();
  if (!content) return;
  resolveHealthFinding(id, 'merge', { mergedContent: content });
}

async function resolveHealthFinding(id, action, payload) {
  const confirmMsg = action === 'delete' ? 'למחוק זיכרון זה? הפעולה בלתי הפיכה.'
    : action === 'merge' ? 'לאחד את שני הזיכרונות לזיכרון חדש ולהעביר את המקוריים לארכיון?'
    : action === 'archive' ? 'להעביר זיכרון זה לארכיון?'
    : 'לעדכן את הקטגוריה?';
  if (!confirm(confirmMsg)) return;
  try {
    await api(`/memories/health/findings/${id}/resolve`, { method: 'POST', body: JSON.stringify({ action, payload }) });
    S.health.findings = S.health.findings.filter(f => String(f.id) !== String(id));
    renderHealthFindings();
    await loadMemories();
  } catch (e) { alert('שגיאה: ' + e.message); }
}

async function dismissHealthFinding(id) {
  try {
    await api(`/memories/health/findings/${id}/dismiss`, { method: 'POST' });
    S.health.findings = S.health.findings.filter(f => String(f.id) !== String(id));
    renderHealthFindings();
  } catch (e) { alert('שגיאה: ' + e.message); }
}
```

Note: `HEB_STOP` (the Hebrew stop-word set) stays in the file — it is still used by `buildSemanticEdges()` for the graph visualization. Do not remove it.

- [ ] **Step 4: Manual smoke test**

Run: `node server.js` (with valid `.env`), open `/progress-map/brain`, switch to the "ידע" tab.
Expected: the old "זיכרונות דומים" section is gone; a new "בדיקת תקינות זיכרונות" section renders with a count strip, an "הרץ בדיקה עכשיו" button, and (once findings exist) type-grouped cards whose action buttons call the new endpoints. Confirm no JS console errors on tab load.

- [ ] **Step 5: Commit**

```bash
git add jarvis-brain.html
git commit -m "feat: replace client-only duplicate scan with the memory health check panel"
```

---

### Task 13: End-to-end integration test

**Files:**
- Create: `tests/integration/memoryHealth.test.js`

- [ ] **Step 1: Write the test**

```javascript
// tests/integration/memoryHealth.test.js
'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
  isReady: jest.fn().mockReturnValue(true),
  searchMemoriesDetailed: jest.fn(),
  listAll: jest.fn().mockResolvedValue([]),
  upsertMemory: jest.fn().mockResolvedValue(true),
  deleteMemory: jest.fn().mockResolvedValue(),
  searchMemories: jest.fn().mockResolvedValue(null),
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn(), removeFromVault: jest.fn() }));
jest.mock('../../services/memoryContext', () => ({ invalidateCache: jest.fn(), savePendingData: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ getPendingMemory: jest.fn(), clearPendingMemory: jest.fn() }));

const express = require('express');
const request = require('supertest');
const pinecone = require('../../services/pineconeMemory');
const { callGemma4 } = require('../../agents/models');
const { createMemoriesRouter } = require('../../routes/memories');
const { makeRepos } = require('../helpers/fakeRepos');

function mountApp(repos) {
  const app = express();
  app.use(express.json());
  app.use('/memories', createMemoriesRouter({ repos }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('memory health check — scan then resolve a merge', () => {
  test('a scan-detected duplicate can be merged via the resolve endpoint', async () => {
    const memA = { id: 1, content: 'אוהב קפה שחור בבוקר', scope: 'long_term', status: 'approved', category: 'כללי', created_at: new Date().toISOString() };
    const memB = { id: 2, content: 'שותה קפה שחור כל בוקר', scope: 'long_term', status: 'approved', category: 'כללי', created_at: new Date().toISOString() };
    const repos = makeRepos({ memories: [memA, memB] });
    repos.memories.create = jest.fn(async () => [{ id: 9, content: 'אוהב לשתות קפה שחור כל בוקר' }]);
    repos.memories.updateById = jest.fn(async (id) => [{ id, scope: 'archive' }]);

    pinecone.searchMemoriesDetailed.mockImplementation(async (query) => {
      if (query === memA.content) return [{ id: '1', content: memA.content, score: 1 }, { id: '2', content: memB.content, score: 0.95 }];
      return [{ id: '2', content: memB.content, score: 1 }, { id: '1', content: memA.content, score: 0.95 }];
    });
    callGemma4.mockImplementation(async (messages) => {
      const text = Array.isArray(messages) ? messages[0].content : messages;
      if (text.includes('מזג')) return '{"merged":"אוהב לשתות קפה שחור כל בוקר"}';
      return '{"category":"כללי"}';
    });

    const app = mountApp(repos);

    const runRes = await request(app).post('/memories/health/run');
    expect(runRes.status).toBe(200);
    expect(runRes.body.created).toBeGreaterThanOrEqual(1);
    expect(repos.memoryHealth.insertFinding).toHaveBeenCalled();

    const [findingRow] = repos.memoryHealth.insertFinding.mock.calls[0];
    expect(findingRow.type).toBe('duplicate');
    const findingId = 'f-test-1';
    repos.memoryHealth.getById = jest.fn(async () => ({
      id: findingId, type: 'duplicate', status: 'pending',
      memory_id: findingRow.memory_id, related_memory_id: findingRow.related_memory_id,
      suggested_payload: findingRow.suggested_payload,
    }));

    const resolveRes = await request(app)
      .post(`/memories/health/findings/${findingId}/resolve`)
      .send({ action: 'merge' });

    expect(resolveRes.status).toBe(200);
    expect(repos.memories.create).toHaveBeenCalledWith(
      expect.objectContaining({ content: 'אוהב לשתות קפה שחור כל בוקר', scope: 'long_term' }));
    expect(repos.memories.updateById).toHaveBeenCalledWith(findingRow.memory_id, { scope: 'archive' });
    expect(repos.memories.updateById).toHaveBeenCalledWith(findingRow.related_memory_id, { scope: 'archive' });
  });

  test('a dismissed finding does not resurface on the next identical scan', async () => {
    const mem = { id: 1, content: 'אוהב פיצה', scope: 'long_term', status: 'approved', category: 'כללי', created_at: new Date().toISOString() };
    const repos = makeRepos({ memories: [mem] });
    pinecone.searchMemoriesDetailed.mockResolvedValue([]);
    callGemma4.mockResolvedValue('{"category":"כללי"}');

    const app = mountApp(repos);
    await request(app).post('/memories/health/run'); // first scan creates the thin_content finding

    const [firstFinding] = repos.memoryHealth.insertFinding.mock.calls
      .map(([r]) => r).filter(r => r.type === 'thin_content');
    expect(firstFinding).toBeTruthy();

    // Simulate it now existing with status 'rejected' and an unchanged content hash
    repos.memoryHealth.findExisting = jest.fn(async () => ({
      id: 'existing-1', status: 'rejected', content_hash: firstFinding.content_hash,
    }));
    repos.memoryHealth.insertFinding.mockClear();

    await request(app).post('/memories/health/run'); // second scan, same content

    const reCreated = repos.memoryHealth.insertFinding.mock.calls
      .map(([r]) => r).find(r => r.type === 'thin_content');
    expect(reCreated).toBeUndefined();
    expect(repos.memoryHealth.updateFinding).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx jest tests/integration/memoryHealth.test.js`
Expected: FAIL initially if any prior task step was missed — this test only exercises code from Tasks 1–10, so at this point in the plan it should already PASS. Run it to confirm.

- [ ] **Step 3: Fix any integration gaps found**

If it fails, the most likely causes are: `findExisting`'s default fake behavior (Task 5) not matching a test override, or a mismatch between the `content_hash` computed by `hashPair` and what the test expects — adjust the test's assumptions to match the actual `services/memoryHealthCheck.js` hashing implementation from Task 6, not the other way around (the unit-level behavior in Task 6 is the source of truth).

- [ ] **Step 4: Run test to verify it passes**

Run: `npx jest tests/integration/memoryHealth.test.js`
Expected: PASS (2 tests)

- [ ] **Step 5: Run the full suite**

Run: `npm test`
Expected: PASS — full suite green, including coverage thresholds (`npm run test:coverage` if you want to confirm thresholds specifically).

- [ ] **Step 6: Commit**

```bash
git add tests/integration/memoryHealth.test.js
git commit -m "test: add end-to-end memory health scan-then-resolve coverage"
```

---

### Task 14: Documentation — `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the new endpoints**

Find:

```
| `GET` | `/memories/pending` | Pending memories awaiting approval | Returns `{ memories: [] }` |
```

Insert directly after it:

```
| `GET` | `/memories/health/findings` | Pending memory-health findings | Optional `?type=`, `?status=` (default `pending`) |
| `POST` | `/memories/health/run` | Trigger a memory health scan now | Rate-limited (5/min); same scan as the nightly `memory_health_scan` cron |
| `POST` | `/memories/health/findings/:id/resolve` | Apply a finding's suggested (or edited) action | Body `{action, payload?}`; requires policy + `X-Confirm-Action`/`X-User-Consent` |
| `POST` | `/memories/health/findings/:id/dismiss` | Dismiss a finding without acting | Resurfaces only if the memory's content later changes |
```

- [ ] **Step 2: Add the cron job**

Find:

```
- **`30 3 * * *` (03:30)** — `memory_cleanup_nightly`: full nightly memory cleanup (Pinecone + Obsidian pass)
```

Insert directly after it:

```
- **`35 3 * * *` (03:35)** — `memory_health_scan`: batch memory-health scan (duplicates, conflicts, category mismatches, stale/thin/orphaned) — see `services/memoryHealthCheck.js`; Supabase↔Pinecone sync gaps are self-healed inline, everything else becomes a pending finding reviewed in the "ידע" tab
```

- [ ] **Step 3: Add the new services and repo**

Find:

```
| `memoryContext.js` | Loads memories for a request (Pinecone → keyword fallback) and manages the short-lived "pending memory" confirmation flow per chat |
```

Insert directly after it:

```
| `memoryCategory.js` | LLM classification of a memory's content into the 5-bucket category taxonomy (עבודה/משפחה/בריאות/תחביב/כללי), used at write time and by the health scan |
| `memoryHealthCheck.js` | Batch health scan over existing memories — duplicates, conflicts, category mismatches, stale/thin content, Supabase↔Pinecone sync gaps. Nightly cron + manual trigger |
| `memoryHealthActions.js` | Applies a chosen action (delete/merge/move/archive) for a memory-health finding, reusing the same primitives as the manual `/memories` CRUD endpoints |
```

Find:

```
`chatRepo`, `contactRepo`, `cronRepo`, `decisionTraceRepo`, `deviceRepo`, `e2eRepo`, `executionLogRepo`, `habitRepo`, `memoryRepo`, `metricsRepo`, `noteRepo`, `playlistRepo`, `profileRepo`, `projectRepo`, `promptLibraryRepo`, `reminderRepo`, `shoppingRepo`, `sprintRepo`, `statsRepo`, `subtaskRepo`, `summaryRepo`, `surveyRepo`, `tableRepo` (generic shallow CRUD), `taskRepo`, `telemetryRepo`, `testCasesRepo`, `userPromptRepo` — each wraps one Supabase table (see table names in Memory & Storage below).
```

Replace with:

```
`chatRepo`, `contactRepo`, `cronRepo`, `decisionTraceRepo`, `deviceRepo`, `e2eRepo`, `executionLogRepo`, `habitRepo`, `memoryHealthRepo`, `memoryRepo`, `metricsRepo`, `noteRepo`, `playlistRepo`, `profileRepo`, `projectRepo`, `promptLibraryRepo`, `reminderRepo`, `shoppingRepo`, `sprintRepo`, `statsRepo`, `subtaskRepo`, `summaryRepo`, `surveyRepo`, `tableRepo` (generic shallow CRUD), `taskRepo`, `telemetryRepo`, `testCasesRepo`, `userPromptRepo` — each wraps one Supabase table (see table names in Memory & Storage below).
```

- [ ] **Step 4: Note the schema change**

Find:

```
| **Supabase** | `chat_history`, `chat_summaries`, `tasks`, `subtasks`, `reminders`, `notes`, `memories` (has a `status` column: `pending`\|`approved`), `contacts`, `shopping_items`, `habits`, `habit_logs`, `projects`, `project_milestones`, `project_sprints`, `e2e_reports`, `user_surveys`, `execution_log`, `decision_trace`, `prompt_library`, `test_cases`, `user_prompts`, `agent_metrics`, `cron_runs`, `device_tokens`, `system_events`, `smart_telemetry_events`, `daily_briefings`, `user_profiles` |
```

Replace with:

```
| **Supabase** | `chat_history`, `chat_summaries`, `tasks`, `subtasks`, `reminders`, `notes`, `memories` (has `status`: `pending`\|`approved`, and `category`: עבודה/משפחה/בריאות/תחביב/כללי), `memory_health_findings`, `contacts`, `shopping_items`, `habits`, `habit_logs`, `projects`, `project_milestones`, `project_sprints`, `e2e_reports`, `user_surveys`, `execution_log`, `decision_trace`, `prompt_library`, `test_cases`, `user_prompts`, `agent_metrics`, `cron_runs`, `device_tokens`, `system_events`, `smart_telemetry_events`, `daily_briefings`, `user_profiles` |
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document the memory health check endpoints, cron, and services"
```

---

## Final verification

- [ ] Run `npm test` — full suite green.
- [ ] Run `npm run test:coverage` — thresholds (58/46/54/61) still met.
- [ ] Run `npm run lint` — no syntax errors (covers the modified `jarvis-brain.html` inline script too, if `lint-syntax.js` checks it — otherwise manually open the file in a browser and check the console for parse errors).
- [ ] Manually smoke-test per Task 12 Step 4.
- [ ] Push the branch and open a PR referencing `docs/superpowers/specs/2026-07-02-memory-health-check-design.md`.
