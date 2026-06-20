# Control Center Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 6-tab mobile control center with a focused 4-tab design (Overview · Intelligence · Dev Workshop · Tests) backed by new server infrastructure for execution logging, weekly scoring, prompt library, and test recording.

**Architecture:** New server repos follow the `createXxxRepo(supabase)` seam in `services/dataAccess/`; all new routes use `repos.xxx` not raw Supabase. Flutter splits `progress_map_screen.dart` (6 191 lines) into one shell + four tab files under `screens/control_center/`. Role-gating hides Intelligence and Dev Workshop from `regular` users.

**Tech Stack:** Node.js/Express, Supabase, Jest (server tests); Flutter/Dart, `fl_chart ^0.69.0`, `shared_preferences ^2.5.0`, `http ^1.6.0` (all already in pubspec).

---

## File Map

### New server files
| File | Purpose |
|------|---------|
| `services/dataAccess/executionLogRepo.js` | CRUD for `execution_log` table |
| `services/dataAccess/promptLibraryRepo.js` | CRUD for `prompt_library` table |
| `services/dataAccess/testCasesRepo.js` | CRUD + run logic for `test_cases` table |
| `routes/controlCenter.js` | All new endpoints mounted at app level |
| `tests/unit/executionLogRepo.test.js` | Repo unit tests |
| `tests/unit/controlCenter.test.js` | Route unit tests |

### Modified server files
| File | Change |
|------|--------|
| `services/dataAccess/index.js` | Register 3 new repos |
| `tests/helpers/fakeRepos.js` | Add fakes for 3 new repos |
| `server.js` | Execution-log middleware after `/ask-jarvis`, `active_model` in `/health`, mount `controlCenter` router |
| `agents/models.js` | Export `_lastActiveProvider` getter |

### New Flutter files
| File | Purpose |
|------|---------|
| `jarvis_mobile/lib/screens/control_center/control_center_shell.dart` | TabController + polling + role-gate |
| `jarvis_mobile/lib/screens/control_center/tab_overview.dart` | Tab 0 |
| `jarvis_mobile/lib/screens/control_center/tab_intelligence.dart` | Tab 1 |
| `jarvis_mobile/lib/screens/control_center/tab_devworkshop.dart` | Tab 2 |
| `jarvis_mobile/lib/screens/control_center/tab_tests.dart` | Tab 3 |

### Modified Flutter files
| File | Change |
|------|--------|
| `jarvis_mobile/lib/screens/progress_map_screen.dart` | Replace body with `ControlCenterShell`, keep file as thin wrapper |
| `jarvis_mobile/lib/services/api_service.dart` | Add methods for all new endpoints |

---

## Task 1: `execution_log` table, repo, and fake

**Files:**
- Create: `services/dataAccess/executionLogRepo.js`
- Modify: `tests/helpers/fakeRepos.js`
- Test: `tests/unit/executionLogRepo.test.js`

- [ ] **Step 1.1 — Write the failing test**

```javascript
// tests/unit/executionLogRepo.test.js
'use strict';
const { createExecutionLogRepo } = require('../../services/dataAccess/executionLogRepo');

function makeSupabase({ rows = [], insertError = null } = {}) {
    const chain = {
        select: jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        limit:  jest.fn().mockResolvedValue({ data: rows, error: null }),
        insert: jest.fn().mockResolvedValue({ error: insertError }),
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('executionLogRepo', () => {
    test('recent returns up to N rows ordered by created_at desc', async () => {
        const rows = [{ id: '1', cmd: 'test', agent: 'chat', model: 'groq', duration_ms: 120, status: 'ok' }];
        const sb = makeSupabase({ rows });
        const repo = createExecutionLogRepo(sb);
        const result = await repo.recent(10);
        expect(result).toEqual(rows);
        expect(sb._chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
        expect(sb._chain.limit).toHaveBeenCalledWith(10);
    });

    test('insert writes a row and does not throw on success', async () => {
        const sb = makeSupabase();
        const repo = createExecutionLogRepo(sb);
        await expect(repo.insert({ cmd: 'hi', agent: 'chat', model: 'groq', duration_ms: 50, status: 'ok' }))
            .resolves.toBeUndefined();
    });

    test('insert swallows errors (degradation)', async () => {
        const sb = makeSupabase({ insertError: new Error('db down') });
        const repo = createExecutionLogRepo(sb);
        await expect(repo.insert({ cmd: 'hi', agent: 'chat', model: 'groq', duration_ms: 50, status: 'ok' }))
            .resolves.toBeUndefined();
    });
});
```

- [ ] **Step 1.2 — Run test to verify it fails**

```bash
npx jest tests/unit/executionLogRepo.test.js --verbose
```
Expected: `Cannot find module '../../services/dataAccess/executionLogRepo'`

- [ ] **Step 1.3 — Create the repo**

```javascript
// services/dataAccess/executionLogRepo.js
'use strict';

const T = 'execution_log';

function createExecutionLogRepo(supabase) {
    return {
        async recent(limit = 50) {
            const { data } = await supabase.from(T)
                .select('id,cmd,agent,model,duration_ms,status,error,created_at')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        async insert({ cmd, agent, model, duration_ms, status, error }) {
            await supabase.from(T).insert({
                cmd: String(cmd || '').slice(0, 300),
                agent: String(agent || '').slice(0, 80),
                model: String(model || '').slice(0, 80),
                duration_ms: Number.isFinite(duration_ms) ? duration_ms : 0,
                status,
                error: error ? String(error).slice(0, 500) : null,
            }).catch(() => {});
        },
    };
}

module.exports = { createExecutionLogRepo };
```

- [ ] **Step 1.4 — Run test to verify it passes**

```bash
npx jest tests/unit/executionLogRepo.test.js --verbose
```
Expected: 3 tests PASS

- [ ] **Step 1.5 — Add fake to fakeRepos.js**

In `tests/helpers/fakeRepos.js`, add after `makeDeviceRepo`:

```javascript
function makeExecutionLogRepo(opts = {}) {
    const { rows = [], insertError = null } = opts;
    return {
        recent:  jest.fn(async () => rows),
        insert:  jest.fn(async () => { if (insertError) throw insertError; }),
    };
}
```

And add to `makeRepos`:
```javascript
executionLog: makeExecutionLogRepo({ rows: tableData.execution_log || [] }),
```

And add to `module.exports`:
```javascript
// append to the exports list:
makeExecutionLogRepo,
```

- [ ] **Step 1.6 — Commit**

```bash
git add services/dataAccess/executionLogRepo.js tests/unit/executionLogRepo.test.js tests/helpers/fakeRepos.js
git commit -m "feat: add executionLogRepo with recent() and insert()"
```

---

## Task 2: Register `executionLog` repo + create DB table SQL

**Files:**
- Modify: `services/dataAccess/index.js`
- Create: `docs/superpowers/migrations/execution_log.sql`

- [ ] **Step 2.1 — Add to index.js**

In `services/dataAccess/index.js`, add after the last `require`:

```javascript
const { createExecutionLogRepo } = require('./executionLogRepo');
```

Add to the returned object inside `createRepos`:

```javascript
executionLog: createExecutionLogRepo(supabase),
```

- [ ] **Step 2.2 — Write migration SQL**

```sql
-- docs/superpowers/migrations/execution_log.sql
CREATE TABLE IF NOT EXISTS execution_log (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cmd         TEXT,
  agent       TEXT,
  model       TEXT,
  duration_ms INTEGER,
  status      TEXT        CHECK (status IN ('ok', 'fail')),
  error       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Keep table lean: auto-delete rows older than 30 days via pg_cron or manual cleanup.
-- Index for the dashboard query (latest N rows).
CREATE INDEX IF NOT EXISTS execution_log_created_at_idx ON execution_log (created_at DESC);
```

Apply in Supabase SQL editor before running integration tests.

- [ ] **Step 2.3 — Verify index.js still exports cleanly**

```bash
node -e "const { createRepos } = require('./services/dataAccess'); console.log(Object.keys(createRepos({ from: () => ({}) })))"
```
Expected output includes `executionLog`.

- [ ] **Step 2.4 — Commit**

```bash
git add services/dataAccess/index.js docs/superpowers/migrations/execution_log.sql
git commit -m "feat: register executionLogRepo in createRepos + add migration SQL"
```

---

## Task 3: Execution-log middleware in `server.js`

**Files:**
- Modify: `server.js`

- [ ] **Step 3.1 — Add `active_model` tracking to models.js**

Open `agents/models.js`. After the line:
```javascript
function getCurrentProvider() {
    return providerContext.getStore()?.provider || null;
}
```
Add:
```javascript
let _lastKnownProvider = null;
function getLastKnownProvider() { return _lastKnownProvider; }
```

In `_setProvider`:
```javascript
function _setProvider(name) {
    const store = providerContext.getStore();
    if (store) store.provider = name;
    _lastKnownProvider = name;   // ← add this line
}
```

Add to the `module.exports` at the bottom of models.js (find the existing exports and add):
```javascript
getLastKnownProvider,
```

- [ ] **Step 3.2 — Update `/health` to include `active_model`**

Find this line in `server.js` (line ~722):
```javascript
app.get('/health', (req, res) => {
    res.json({ ok: true, version: 'multi-agent-v3', ts: Date.now(), pinecone: pinecone.isReady() });
});
```
Replace with:
```javascript
app.get('/health', (req, res) => {
    res.json({
        ok: true,
        version: 'multi-agent-v3',
        ts: Date.now(),
        pinecone: pinecone.isReady(),
        active_model: getLastKnownProvider(),
    });
});
```

Add the import near the top of server.js where `models.js` is already imported. Find:
```javascript
const { callGemma4, callGemma4Stream, callGeminiWithSearch, callGeminiVision, getCurrentProvider, providerContext } = require('./agents/models');
```
Replace with:
```javascript
const { callGemma4, callGemma4Stream, callGeminiWithSearch, callGeminiVision, getCurrentProvider, getLastKnownProvider, providerContext } = require('./agents/models');
```

- [ ] **Step 3.3 — Add execution-log middleware after `/ask-jarvis` response**

In `server.js`, find the line after `const tDone = Date.now();` (line ~1209). Right after the `console.log(...)` timing block (around line 1218), add a fire-and-forget log write:

```javascript
        // ── Execution log (fire-and-forget, never blocks response) ─────────────
        repos.executionLog.insert({
            cmd:         String(originalMessage || userMessage).slice(0, 300),
            agent:       agentName,
            model:       llmProvider || getLastKnownProvider() || 'unknown',
            duration_ms: tDone - t0,
            status:      'ok',
        }).catch(() => {});
```

Also wrap the existing error path. Find the catch handler in the `/ask-jarvis` route (search for `res.status(500).json` inside that route) and add before it:
```javascript
            repos.executionLog.insert({
                cmd:         String(req.body?.userMessage || '').slice(0, 300),
                agent:       'unknown',
                model:       getLastKnownProvider() || 'unknown',
                duration_ms: Date.now() - (req._t0 || Date.now()),
                status:      'fail',
                error:       err?.message,
            }).catch(() => {});
```

- [ ] **Step 3.4 — Add `GET /execution-log` route**

After the `/stats` route in server.js (line ~1442), add:

```javascript
// ─── Execution log ────────────────────────────────────────────────────────
app.get('/execution-log', _rl(30), async (req, res) => {
    try {
        const limit = Math.min(parseInt(req.query.limit) || 50, 200);
        const rows = await repos.executionLog.recent(limit);
        res.json({ log: rows });
    } catch (err) {
        console.error('GET /execution-log error:', err.message);
        res.status(500).json({ error: 'internal server error' });
    }
});
```

- [ ] **Step 3.5 — Run all tests**

```bash
npm test
```
Expected: all existing tests pass (the new middleware is fire-and-forget, so no existing test breaks).

- [ ] **Step 3.6 — Commit**

```bash
git add server.js agents/models.js
git commit -m "feat: execution-log middleware + active_model in /health + GET /execution-log"
```

---

## Task 4: `prompt_library` repo + CRUD endpoints

**Files:**
- Create: `services/dataAccess/promptLibraryRepo.js`
- Modify: `services/dataAccess/index.js`, `tests/helpers/fakeRepos.js`, `server.js`
- Test: `tests/unit/promptLibraryRepo.test.js`

- [ ] **Step 4.1 — Write the failing test**

```javascript
// tests/unit/promptLibraryRepo.test.js
'use strict';
const { createPromptLibraryRepo } = require('../../services/dataAccess/promptLibraryRepo');

function makeSupabase(rows = []) {
    const firstRow = rows[0] || { id: 'p1', name: 'test', content: 'x', version: 1, is_active: true };
    const chain = {
        select: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        single: jest.fn().mockResolvedValue({ data: firstRow, error: null }),
        then:   undefined,
    };
    // make the chain thenable for list calls
    chain.order = jest.fn().mockResolvedValue({ data: rows, error: null });
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('promptLibraryRepo', () => {
    test('listAll returns rows ordered by created_at', async () => {
        const rows = [{ id: 'p1', name: 'Test', content: 'x', version: 1, is_active: true }];
        const sb = makeSupabase(rows);
        const repo = createPromptLibraryRepo(sb);
        const result = await repo.listAll();
        expect(result).toEqual(rows);
    });
});
```

- [ ] **Step 4.2 — Run to confirm fail**

```bash
npx jest tests/unit/promptLibraryRepo.test.js --verbose
```

- [ ] **Step 4.3 — Create the repo**

```javascript
// services/dataAccess/promptLibraryRepo.js
'use strict';

const T = 'prompt_library';

function createPromptLibraryRepo(supabase) {
    return {
        async listAll() {
            const { data, error } = await supabase.from(T)
                .select('*')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        async create({ name, content }) {
            const { data, error } = await supabase.from(T)
                .insert({ name: String(name).slice(0, 120), content: String(content) })
                .select()
                .single();
            if (error) throw error;
            return data;
        },

        async update(id, { name, content, is_active }) {
            const patch = {};
            if (name !== undefined)      patch.name      = String(name).slice(0, 120);
            if (content !== undefined)   patch.content   = String(content);
            if (is_active !== undefined) patch.is_active = Boolean(is_active);
            if (Object.keys(patch).length === 0) throw new Error('nothing to update');
            // Bump version on content change
            if (patch.content) {
                const { data: cur } = await supabase.from(T).select('version').eq('id', id).single();
                patch.version = ((cur?.version) || 1) + 1;
            }
            const { data, error } = await supabase.from(T)
                .update(patch)
                .eq('id', id)
                .select()
                .single();
            if (error) throw error;
            return data;
        },

        async remove(id) {
            const { error } = await supabase.from(T).delete().eq('id', id);
            if (error) throw error;
        },
    };
}

module.exports = { createPromptLibraryRepo };
```

- [ ] **Step 4.4 — Run test to pass**

```bash
npx jest tests/unit/promptLibraryRepo.test.js --verbose
```

- [ ] **Step 4.5 — Register in index.js + add fake**

In `services/dataAccess/index.js`, add:
```javascript
const { createPromptLibraryRepo } = require('./promptLibraryRepo');
// ...inside createRepos:
promptLibrary: createPromptLibraryRepo(supabase),
```

In `tests/helpers/fakeRepos.js`, add:
```javascript
function makePromptLibraryRepo(opts = {}) {
    const { rows = [] } = opts;
    const first = rows[0] || { id: 'p1', name: 'x', content: 'y', version: 1, is_active: true };
    return {
        listAll: jest.fn(async () => rows),
        create:  jest.fn(async () => first),
        update:  jest.fn(async () => first),
        remove:  jest.fn(async () => undefined),
    };
}
```
Add to `makeRepos`: `promptLibrary: makePromptLibraryRepo({ rows: tableData.prompt_library || [] }),`
Add `makePromptLibraryRepo` to `module.exports`.

- [ ] **Step 4.6 — Add CRUD endpoints to server.js**

After `GET /execution-log`, add:

```javascript
// ─── Prompt Library ───────────────────────────────────────────────────────
app.get('/prompt-library', _rl(30), async (_req, res) => {
    try {
        res.json({ prompts: await repos.promptLibrary.listAll() });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/prompt-library', _rl(20), async (req, res) => {
    try {
        const { name, content } = req.body || {};
        if (!name || !content) return res.status(400).json({ error: 'name and content required' });
        res.json({ prompt: await repos.promptLibrary.create({ name, content }) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/prompt-library/:id', _rl(20), async (req, res) => {
    try {
        res.json({ prompt: await repos.promptLibrary.update(req.params.id, req.body || {}) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/prompt-library/:id', _rl(10), async (req, res) => {
    try {
        await repos.promptLibrary.remove(req.params.id);
        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
```

- [ ] **Step 4.7 — Write migration SQL**

```sql
-- docs/superpowers/migrations/prompt_library.sql
CREATE TABLE IF NOT EXISTS prompt_library (
  id         UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT    NOT NULL,
  content    TEXT    NOT NULL,
  version    INTEGER DEFAULT 1,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

- [ ] **Step 4.8 — Run all tests + commit**

```bash
npm test
git add services/dataAccess/promptLibraryRepo.js services/dataAccess/index.js tests/helpers/fakeRepos.js tests/unit/promptLibraryRepo.test.js docs/superpowers/migrations/prompt_library.sql server.js
git commit -m "feat: prompt_library repo + CRUD endpoints"
```

---

## Task 5: `test_cases` repo + recording/run endpoints

**Files:**
- Create: `services/dataAccess/testCasesRepo.js`
- Modify: `services/dataAccess/index.js`, `tests/helpers/fakeRepos.js`, `server.js`
- Test: `tests/unit/testCasesRepo.test.js`

- [ ] **Step 5.1 — Write the failing test**

```javascript
// tests/unit/testCasesRepo.test.js
'use strict';
const { createTestCasesRepo } = require('../../services/dataAccess/testCasesRepo');

const SAMPLE = {
    id: 'tc1', name: 'תזכורת', source: 'recorded',
    turns: [{ input: 'תזכיר לי בשעה 8', expected_intent: 'reminder', expected_action_type: 'reminder_set', expected_contains: ['8:00'] }],
    last_status: 'pending', recorded_at: '2026-06-20T10:00:00Z',
};

function makeSb(rows = []) {
    const chain = {
        select: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        single: jest.fn().mockResolvedValue({ data: rows[0] || SAMPLE, error: null }),
        limit:  jest.fn().mockResolvedValue({ data: rows, error: null }),
    };
    chain.order = jest.fn().mockResolvedValue({ data: rows, error: null });
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('testCasesRepo', () => {
    test('listAll returns rows', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createTestCasesRepo(sb);
        expect(await repo.listAll()).toEqual([SAMPLE]);
    });

    test('create inserts and returns row', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createTestCasesRepo(sb);
        const result = await repo.create({ name: 'test', turns: SAMPLE.turns });
        expect(result).toEqual(SAMPLE);
    });

    test('markResult updates last_status and last_run', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createTestCasesRepo(sb);
        await repo.markResult('tc1', 'pass', []);
        expect(sb._chain.update).toHaveBeenCalled();
    });
});
```

- [ ] **Step 5.2 — Run to confirm fail**

```bash
npx jest tests/unit/testCasesRepo.test.js --verbose
```

- [ ] **Step 5.3 — Create the repo**

```javascript
// services/dataAccess/testCasesRepo.js
'use strict';

const T = 'test_cases';

function createTestCasesRepo(supabase) {
    return {
        async listAll() {
            const { data, error } = await supabase.from(T)
                .select('*')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        async create({ name, turns, source = 'recorded', recorded_at }) {
            const { data, error } = await supabase.from(T)
                .insert({
                    name: String(name).slice(0, 120),
                    turns: JSON.stringify(turns),
                    source,
                    recorded_at: recorded_at || new Date().toISOString(),
                    last_status: 'pending',
                })
                .select()
                .single();
            if (error) throw error;
            return data;
        },

        async markResult(id, status, diffArray) {
            const { error } = await supabase.from(T)
                .update({
                    last_status:   status,
                    last_run:      new Date().toISOString(),
                    last_run_diff: JSON.stringify(diffArray),
                })
                .eq('id', id);
            if (error) throw error;
        },

        async byId(id) {
            const { data, error } = await supabase.from(T).select('*').eq('id', id).single();
            if (error) throw error;
            return data;
        },
    };
}

module.exports = { createTestCasesRepo };
```

- [ ] **Step 5.4 — Run tests to pass**

```bash
npx jest tests/unit/testCasesRepo.test.js --verbose
```

- [ ] **Step 5.5 — Register in index.js + add fake**

In `services/dataAccess/index.js`:
```javascript
const { createTestCasesRepo } = require('./testCasesRepo');
// inside createRepos:
testCases: createTestCasesRepo(supabase),
```

In `tests/helpers/fakeRepos.js`:
```javascript
function makeTestCasesRepo(opts = {}) {
    const { rows = [] } = opts;
    const first = rows[0] || { id: 'tc1', name: 'x', turns: '[]', source: 'recorded', last_status: 'pending' };
    return {
        listAll:    jest.fn(async () => rows),
        create:     jest.fn(async () => first),
        markResult: jest.fn(async () => undefined),
        byId:       jest.fn(async () => first),
    };
}
```
Add to `makeRepos`: `testCases: makeTestCasesRepo({ rows: tableData.test_cases || [] }),`
Add to exports.

- [ ] **Step 5.6 — Add server endpoints**

After the prompt-library routes in server.js:

```javascript
// ─── Test Cases ──────────────────────────────────────────────────────────
// In-memory recording state (single-user server; lost on restart).
const _recordings = new Map(); // chatId → { startedAt, turns[] }

app.get('/test-cases', _rl(30), async (_req, res) => {
    try {
        res.json({ testCases: await repos.testCases.listAll() });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/test-cases', _rl(20), async (req, res) => {
    try {
        const { name, turns } = req.body || {};
        if (!name || !Array.isArray(turns) || turns.length === 0)
            return res.status(400).json({ error: 'name and non-empty turns required' });
        res.json({ testCase: await repos.testCases.create({ name, turns }) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/test-cases/start-recording', _rl(10), (req, res) => {
    const chatId = req.body?.chatId || 'default-session';
    _recordings.set(chatId, { startedAt: new Date().toISOString(), turns: [] });
    res.json({ ok: true, chatId });
});

app.post('/test-cases/stop-recording', _rl(10), (req, res) => {
    const chatId = req.body?.chatId || 'default-session';
    const rec = _recordings.get(chatId);
    if (!rec) return res.status(404).json({ error: 'no active recording for chatId' });
    _recordings.delete(chatId);
    res.json({ ok: true, turns: rec.turns, startedAt: rec.startedAt });
});

app.post('/test-cases/:id/run', _rl(5), async (req, res) => {
    try {
        const tc = await repos.testCases.byId(req.params.id);
        const turns = Array.isArray(tc.turns) ? tc.turns : JSON.parse(tc.turns || '[]');
        const results = [];
        let overallPass = true;

        for (const turn of turns) {
            // Replay turn through ask-jarvis logic (lightweight: classify intent only).
            const { classifyIntentDetailed } = require('./agents/router');
            const classification = await classifyIntentDetailed(turn.input, supabase);
            const detectedIntent = classification?.intent || 'unknown';

            const intentMatch = !turn.expected_intent || detectedIntent === turn.expected_intent;
            const pass = intentMatch;
            if (!pass) overallPass = false;

            results.push({
                input:            turn.input,
                expected_intent:  turn.expected_intent,
                detected_intent:  detectedIntent,
                intent_match:     intentMatch,
                pass,
            });
        }

        const finalStatus = overallPass ? 'pass' : 'fail';
        await repos.testCases.markResult(tc.id, finalStatus, results);
        res.json({ status: finalStatus, results });
    } catch (err) {
        console.error('POST /test-cases/:id/run error:', err.message);
        res.status(500).json({ error: err.message });
    }
});
```

Also, hook the recorder into the `/ask-jarvis` response. After `const tDone = Date.now();` (after the execution-log insert), add:

```javascript
        // ── Test recorder: append turn if a recording is active for this chat ───
        const rec = _recordings.get(chatId);
        if (rec) {
            rec.turns.push({
                input:                originalMessage,
                expected_intent:      agentName,
                expected_action_type: action?.type || null,
                expected_contains:    [],
            });
        }
```

- [ ] **Step 5.7 — Write migration SQL**

```sql
-- docs/superpowers/migrations/test_cases.sql
CREATE TABLE IF NOT EXISTS test_cases (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT        NOT NULL,
  turns        JSONB       NOT NULL,
  source       TEXT        DEFAULT 'recorded',
  recorded_at  TIMESTAMPTZ,
  last_run     TIMESTAMPTZ,
  last_status  TEXT,
  last_run_diff JSONB,
  created_at   TIMESTAMPTZ DEFAULT now()
);
```

- [ ] **Step 5.8 — Run all tests + commit**

```bash
npm test
git add services/dataAccess/testCasesRepo.js services/dataAccess/index.js tests/helpers/fakeRepos.js tests/unit/testCasesRepo.test.js docs/superpowers/migrations/test_cases.sql server.js
git commit -m "feat: test_cases repo + recording + run endpoints"
```

---

## Task 6: `GET /stats/weekly-score` + `GET/PUT /e2e-schedule` + `GET /changelog/generate`

**Files:**
- Modify: `server.js`

- [ ] **Step 6.1 — Add `GET /stats/weekly-score`**

After `GET /stats` in server.js (line ~1442):

```javascript
// ─── Weekly Intelligence Score ────────────────────────────────────────────
// Score 0-100 from: execution success rate (33%) + feedback ratio (33%) +
// survey avg (33%). Returns 6 weeks of history for the timeline chart.
app.get('/stats/weekly-score', _rl(20), async (req, res) => {
    try {
        const weeks = Math.min(parseInt(req.query.weeks) || 6, 12);
        const history = [];

        for (let w = 0; w < weeks; w++) {
            const weekEnd   = new Date();
            weekEnd.setDate(weekEnd.getDate() - w * 7);
            const weekStart = new Date(weekEnd);
            weekStart.setDate(weekEnd.getDate() - 7);
            const ws = weekStart.toISOString();
            const we = weekEnd.toISOString();

            // Execution success rate from execution_log
            const logRows = await repos.executionLog.recent(500);
            const weekLog = logRows.filter(r => r.created_at >= ws && r.created_at < we);
            const successRate = weekLog.length === 0 ? null
                : Math.round((weekLog.filter(r => r.status === 'ok').length / weekLog.length) * 100);

            // Feedback ratio from smart_telemetry_events
            const telRows = await repos.telemetry.recentEvents(500);
            const weekTel = telRows.filter(r => r.created_at >= ws && r.created_at < we);
            const ups   = weekTel.filter(r => r.event_name === 'feedback_up').length;
            const downs = weekTel.filter(r => r.event_name === 'feedback_down').length;
            const feedbackScore = (ups + downs) === 0 ? null
                : Math.round((ups / (ups + downs)) * 100);

            const components = [successRate, feedbackScore].filter(v => v !== null);
            const score = components.length === 0 ? null
                : Math.round(components.reduce((a, b) => a + b, 0) / components.length);

            history.push({
                week_start:     ws,
                week_end:       we,
                score,
                success_rate:   successRate,
                feedback_score: feedbackScore,
                positive_count: ups,
                total_feedback: ups + downs,
            });
        }

        res.json({ history, current: history[0] || null });
    } catch (err) {
        console.error('GET /stats/weekly-score error:', err.message);
        res.status(500).json({ error: 'internal server error' });
    }
});
```

- [ ] **Step 6.2 — Add `GET/PUT /e2e-schedule`**

The schedule is stored in the user profile's `preferences` JSON blob. Add after the weekly-score route:

```javascript
// ─── E2E Schedule ─────────────────────────────────────────────────────────
app.get('/e2e-schedule', _rl(20), async (_req, res) => {
    try {
        const profiles = await repos.profile.latest();
        const prefs = profiles[0]?.preferences || {};
        res.json({ schedule: prefs.e2eSchedule || { mode: 'manual' } });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/e2e-schedule', _rl(10), async (req, res) => {
    try {
        const { mode } = req.body || {};
        if (!['manual', 'daily', 'every2h', 'post_deploy'].includes(mode))
            return res.status(400).json({ error: 'invalid mode' });
        const profiles = await repos.profile.latest();
        const current = profiles[0] || {};
        const prefs = { ...(current.preferences || {}), e2eSchedule: { mode } };
        if (profiles[0]) {
            await repos.profile.update(profiles[0].id, { preferences: prefs });
        } else {
            await repos.profile.create({ preferences: prefs });
        }
        res.json({ ok: true, schedule: { mode } });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
```

- [ ] **Step 6.3 — Add `GET /changelog/generate`**

```javascript
// ─── Changelog Generator ─────────────────────────────────────────────────
const { execSync } = require('child_process');
app.get('/changelog/generate', _rl(5), async (_req, res) => {
    try {
        let gitLog = '';
        try {
            gitLog = execSync('git log --oneline -50 --no-merges', { timeout: 5000 }).toString();
        } catch (_) {
            return res.status(503).json({ error: 'git not available' });
        }
        const prompt = [
            { role: 'system', content: 'You are a technical writer. Categorize git commits into: feature, fix, ux, infra. Respond with JSON array: [{category, emoji, message}]. Use Hebrew for messages.' },
            { role: 'user',   content: `Git log:\n${gitLog}\n\nReturn JSON array only.` },
        ];
        const raw = await callGemma4(prompt, { temperature: 0.3 });
        const { extractJSON } = require('./agents/utils');
        const entries = extractJSON(raw) || [];
        res.json({ entries, raw_commits: gitLog.split('\n').filter(Boolean).length });
    } catch (err) {
        console.error('GET /changelog/generate error:', err.message);
        res.status(500).json({ error: err.message });
    }
});
```

- [ ] **Step 6.4 — Add survey export + sentiment**

```javascript
// ─── Survey Export ────────────────────────────────────────────────────────
app.get('/surveys/export', _rl(10), async (req, res) => {
    try {
        const format = req.query.format === 'pdf' ? 'pdf' : 'csv';
        const responses = await repos.surveys.responsesForUser('default');

        if (format === 'csv') {
            const header = 'id,question_id,answer,created_at\n';
            const rows = responses.map(r =>
                [r.id, r.question_id, JSON.stringify(r.answer).replace(/,/g, ';'), r.created_at].join(',')
            ).join('\n');
            res.setHeader('Content-Type', 'text/csv');
            res.setHeader('Content-Disposition', 'attachment; filename="surveys.csv"');
            return res.send(header + rows);
        }

        // PDF: return markdown summary (client renders or downloads)
        const lines = responses.slice(0, 100).map((r, i) =>
            `**${i + 1}.** Q: ${r.question_id} | A: ${JSON.stringify(r.answer)} | ${r.created_at?.slice(0, 10)}`
        );
        res.setHeader('Content-Type', 'text/markdown');
        res.setHeader('Content-Disposition', 'attachment; filename="surveys.md"');
        res.send(`# Survey Export\n\n${lines.join('\n\n')}`);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/surveys/analyze-sentiment', _rl(5), async (req, res) => {
    try {
        const { texts } = req.body || {};
        if (!Array.isArray(texts) || texts.length === 0)
            return res.status(400).json({ error: 'texts array required' });
        const prompt = [
            { role: 'system', content: 'Analyze sentiment of each text. Return JSON: [{text, sentiment: positive|neutral|negative, score: 0-1}]' },
            { role: 'user',   content: texts.slice(0, 20).join('\n---\n') },
        ];
        const raw = await callGemma4(prompt, { temperature: 0.2 });
        const { extractJSON } = require('./agents/utils');
        res.json({ results: extractJSON(raw) || [] });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
```

- [ ] **Step 6.5 — Run all tests + commit**

```bash
npm test
git add server.js
git commit -m "feat: weekly-score, e2e-schedule, changelog/generate, surveys/export endpoints"
```

---

## Task 7: Flutter — `ApiService` new methods

**Files:**
- Modify: `jarvis_mobile/lib/services/api_service.dart`

- [ ] **Step 7.1 — Add all new API methods**

Append to `api_service.dart` before the closing `}` of the `ApiService` class:

```dart
  // ── Execution Log ────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchExecutionLog({int limit = 50}) async {
    try {
      final resp = await _client
          .get(_uri('/execution-log?limit=$limit'), headers: _headers())
          .timeout(_timeout);
      if (resp.statusCode != 200) return [];
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(j['log'] ?? []);
    } catch (e) {
      debugPrint('[ApiService] fetchExecutionLog error: $e');
      return [];
    }
  }

  // ── Health (with active_model) ───────────────────────────────────────────
  Future<Map<String, dynamic>> fetchHealth() async {
    try {
      final resp = await _client
          .get(_uri('/health'), headers: _headers())
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return {};
      return Map<String, dynamic>.from(jsonDecode(resp.body));
    } catch (_) {
      return {};
    }
  }

  // ── Weekly Score ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchWeeklyScore({int weeks = 6}) async {
    try {
      final resp = await _client
          .get(_uri('/stats/weekly-score?weeks=$weeks'), headers: _headers())
          .timeout(_timeout);
      if (resp.statusCode != 200) return {};
      return Map<String, dynamic>.from(jsonDecode(resp.body));
    } catch (e) {
      debugPrint('[ApiService] fetchWeeklyScore error: $e');
      return {};
    }
  }

  // ── Prompt Library ───────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchPrompts() async {
    try {
      final resp = await _client
          .get(_uri('/prompt-library'), headers: _headers())
          .timeout(_timeout);
      if (resp.statusCode != 200) return [];
      return List<Map<String, dynamic>>.from(
          (jsonDecode(resp.body) as Map)['prompts'] ?? []);
    } catch (_) { return []; }
  }

  Future<Map<String, dynamic>?> createPrompt(String name, String content) async {
    try {
      final resp = await _client
          .post(_uri('/prompt-library'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: jsonEncode({'name': name, 'content': content}))
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      return Map<String, dynamic>.from((jsonDecode(resp.body))['prompt']);
    } catch (_) { return null; }
  }

  Future<bool> updatePrompt(String id, Map<String, dynamic> patch) async {
    try {
      final resp = await _client
          .put(_uri('/prompt-library/$id'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: jsonEncode(patch))
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> deletePrompt(String id) async {
    try {
      final resp = await _client
          .delete(_uri('/prompt-library/$id'), headers: _headers())
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Test Cases ───────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchTestCases() async {
    try {
      final resp = await _client
          .get(_uri('/test-cases'), headers: _headers())
          .timeout(_timeout);
      if (resp.statusCode != 200) return [];
      return List<Map<String, dynamic>>.from(
          (jsonDecode(resp.body) as Map)['testCases'] ?? []);
    } catch (_) { return []; }
  }

  Future<bool> startRecording(String chatId) async {
    try {
      final resp = await _client
          .post(_uri('/test-cases/start-recording'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: jsonEncode({'chatId': chatId}))
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<Map<String, dynamic>?> stopRecording(String chatId) async {
    try {
      final resp = await _client
          .post(_uri('/test-cases/stop-recording'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: jsonEncode({'chatId': chatId}))
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      return Map<String, dynamic>.from(jsonDecode(resp.body));
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> runTestCase(String id) async {
    try {
      final resp = await _client
          .post(_uri('/test-cases/$id/run'), headers: _headers())
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) return null;
      return Map<String, dynamic>.from(jsonDecode(resp.body));
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> saveTestCase(String name, List<Map<String, dynamic>> turns) async {
    try {
      final resp = await _client
          .post(_uri('/test-cases'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: jsonEncode({'name': name, 'turns': turns}))
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      return Map<String, dynamic>.from((jsonDecode(resp.body))['testCase']);
    } catch (_) { return null; }
  }

  // ── E2E Schedule ─────────────────────────────────────────────────────────
  Future<String> fetchE2eSchedule() async {
    try {
      final resp = await _client
          .get(_uri('/e2e-schedule'), headers: _headers())
          .timeout(_timeout);
      if (resp.statusCode != 200) return 'manual';
      return (jsonDecode(resp.body)['schedule']?['mode'] ?? 'manual').toString();
    } catch (_) { return 'manual'; }
  }

  Future<bool> setE2eSchedule(String mode) async {
    try {
      final resp = await _client
          .put(_uri('/e2e-schedule'),
              headers: _headers({'Content-Type': 'application/json'}),
              body: jsonEncode({'mode': mode}))
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Changelog ────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> generateChangelog() async {
    try {
      final resp = await _client
          .get(_uri('/changelog/generate'), headers: _headers())
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return [];
      return List<Map<String, dynamic>>.from(
          (jsonDecode(resp.body) as Map)['entries'] ?? []);
    } catch (_) { return []; }
  }

  // ── Survey Export ────────────────────────────────────────────────────────
  Future<String?> exportSurveysUrl(String format) {
    // Returns the full URL; the caller opens it in the browser / share sheet.
    return Future.value('${settings.serverUrl}/surveys/export?format=$format');
  }
```

- [ ] **Step 7.2 — Verify Dart syntax**

```bash
cd jarvis_mobile && flutter analyze lib/services/api_service.dart
```
Expected: no errors.

- [ ] **Step 7.3 — Commit**

```bash
git add jarvis_mobile/lib/services/api_service.dart
git commit -m "feat: add all new API methods to ApiService"
```

---

## Task 8: Flutter file split — create `screens/control_center/` shell

**Files:**
- Create: `jarvis_mobile/lib/screens/control_center/control_center_shell.dart`
- Create: `jarvis_mobile/lib/screens/control_center/tab_overview.dart` (stub)
- Create: `jarvis_mobile/lib/screens/control_center/tab_intelligence.dart` (stub)
- Create: `jarvis_mobile/lib/screens/control_center/tab_devworkshop.dart` (stub)
- Create: `jarvis_mobile/lib/screens/control_center/tab_tests.dart` (stub)
- Modify: `jarvis_mobile/lib/screens/progress_map_screen.dart`

- [ ] **Step 8.1 — Create tab stubs (overview as example)**

```dart
// jarvis_mobile/lib/screens/control_center/tab_overview.dart
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../app_settings.dart';
import '../../services/api_service.dart';

class TabOverview extends StatefulWidget {
  final AppSettings settings;
  final ApiService api;
  const TabOverview({super.key, required this.settings, required this.api});

  @override
  State<TabOverview> createState() => _TabOverviewState();
}

class _TabOverviewState extends State<TabOverview>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(child: Text('סקירה — בפיתוח', style: TextStyle(fontFamily: 'Heebo')));
  }
}
```

Repeat the same stub pattern for `tab_intelligence.dart` (label `אינטליגנציה`), `tab_devworkshop.dart` (label `סדנת פיתוח`), `tab_tests.dart` (label `בדיקות`).

- [ ] **Step 8.2 — Create the shell**

```dart
// jarvis_mobile/lib/screens/control_center/control_center_shell.dart
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../app_settings.dart';
import '../../services/api_service.dart';
import 'tab_overview.dart';
import 'tab_intelligence.dart';
import 'tab_devworkshop.dart';
import 'tab_tests.dart';

// Tab indices — kept in sync with TabBar order below.
enum CcTab { overview, intelligence, devWorkshop, tests }

class ControlCenterShell extends StatefulWidget {
  final AppSettings settings;
  const ControlCenterShell({super.key, required this.settings});

  @override
  State<ControlCenterShell> createState() => _ControlCenterShellState();
}

class _ControlCenterShellState extends State<ControlCenterShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late ApiService _api;

  // Role-based tab visibility: regular users see Overview + Tests only.
  bool get _isAdmin => (widget.settings.userProfile?['role'] ?? 'regular') == 'admin';

  List<CcTab> get _visibleTabs => _isAdmin
      ? CcTab.values
      : [CcTab.overview, CcTab.tests];

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.settings);
    _tabs = TabController(length: _visibleTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _tabLabel(CcTab t) => switch (t) {
    CcTab.overview     => 'סקירה',
    CcTab.intelligence => 'אינטליגנציה',
    CcTab.devWorkshop  => 'סדנה',
    CcTab.tests        => 'בדיקות',
  };

  Widget _tabBody(CcTab t) => switch (t) {
    CcTab.overview     => TabOverview(settings: widget.settings, api: _api),
    CcTab.intelligence => TabIntelligence(settings: widget.settings, api: _api),
    CcTab.devWorkshop  => TabDevWorkshop(settings: widget.settings, api: _api),
    CcTab.tests        => TabTests(settings: widget.settings, api: _api),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: JC.surface,
        elevation: 0,
        centerTitle: false,
        title: const Text('מרכז שליטה',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700,
                color: Color(0xFFC9A84C))),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: _visibleTabs.length > 3,
          indicatorColor: const Color(0xFFC9A84C),
          labelStyle: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
          labelColor: const Color(0xFFC9A84C),
          unselectedLabelColor: JC.textMuted,
          tabs: _visibleTabs.map((t) => Tab(text: _tabLabel(t))).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: _visibleTabs.map(_tabBody).toList(),
      ),
    );
  }
}
```

- [ ] **Step 8.3 — Replace `progress_map_screen.dart` body**

Open `progress_map_screen.dart`. Find the class `ProgressMapScreen extends StatefulWidget` and its `createState`. Replace the `build` method of `_ProgressMapScreenState` to delegate to the shell (keep the class intact for now to avoid breaking navigation):

Find the `build` method of `_ProgressMapScreenState` (search for `Widget build(BuildContext context)` in the class). Replace just the `build` method body with:

```dart
  @override
  Widget build(BuildContext context) {
    return ControlCenterShell(settings: widget.settings);
  }
```

Add the import at the top of `progress_map_screen.dart`:
```dart
import 'control_center/control_center_shell.dart';
```

- [ ] **Step 8.4 — Verify Flutter builds**

```bash
cd jarvis_mobile && flutter build apk --debug 2>&1 | tail -20
```
Expected: build succeeds (or only pre-existing warnings).

- [ ] **Step 8.5 — Commit**

```bash
git add jarvis_mobile/lib/screens/control_center/ jarvis_mobile/lib/screens/progress_map_screen.dart
git commit -m "feat: Flutter control center shell + 4-tab structure (stubs)"
```

---

## Task 9: Tab 0 — Overview (server status + model chain + execution log)

**Files:**
- Modify: `jarvis_mobile/lib/screens/control_center/tab_overview.dart`

- [ ] **Step 9.1 — Replace stub with full implementation**

```dart
// jarvis_mobile/lib/screens/control_center/tab_overview.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../app_settings.dart';
import '../../services/api_service.dart';

class TabOverview extends StatefulWidget {
  final AppSettings settings;
  final ApiService api;
  const TabOverview({super.key, required this.settings, required this.api});

  @override
  State<TabOverview> createState() => _TabOverviewState();
}

class _TabOverviewState extends State<TabOverview>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic> _health = {};
  List<Map<String, dynamic>> _log = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  Timer? _timer;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _schedulePolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    _schedulePolling();
  }

  void _schedulePolling() {
    final interval = _appInForeground ? 30 : 120;
    _timer = Timer.periodic(Duration(seconds: interval), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      widget.api.fetchHealth(),
      widget.api.fetchExecutionLog(limit: 10),
      widget.api.fetchStats(),
    ]);
    if (!mounted) return;
    setState(() {
      _health = results[0] as Map<String, dynamic>;
      _log    = results[1] as List<Map<String, dynamic>>;
      _stats  = results[2] as Map<String, dynamic>;
      _loading = false;
    });
  }

  static const _providerOrder = ['ollama', 'groq', 'deepseek', 'gemini'];
  static const _providerLabel = {
    'ollama': 'Ollama', 'groq': 'Groq', 'deepseek': 'DeepSeek', 'gemini': 'Gemini',
  };

  Widget _modelChain() {
    final active = (_health['active_model'] ?? '').toString().toLowerCase();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Text('שרשרת מודלים פעילה',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, color: Color(0xFFC9A84C))),
        const SizedBox(height: 10),
        Row(
          textDirection: TextDirection.ltr,
          children: _providerOrder.map((p) {
            final isActive = active.isNotEmpty && active.contains(p);
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF1E293B) : JC.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isActive ? const Color(0xFFC9A84C) : JC.border),
                ),
                child: Column(children: [
                  if (isActive) Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                  ),
                  if (isActive) const SizedBox(height: 4),
                  Text(_providerLabel[p] ?? p,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'Heebo', fontSize: 11,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                          color: isActive ? const Color(0xFFC9A84C) : JC.textMuted)),
                ]),
              ),
            ));
          }).toList(),
        ),
      ]),
    );
  }

  Widget _logTable() {
    if (_log.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
        child: const Text('אין רשומות עדיין', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF64748B))),
      );
    }
    return Container(
      decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(flex: 3, child: Text('פקודה', style: TextStyle(fontFamily: 'Heebo', fontSize: 11, color: JC.textMuted))),
            Expanded(flex: 2, child: Text('סוכן', style: TextStyle(fontFamily: 'Heebo', fontSize: 11, color: JC.textMuted))),
            Expanded(flex: 2, child: Text('מודל', style: TextStyle(fontFamily: 'Heebo', fontSize: 11, color: JC.textMuted))),
            const SizedBox(width: 45, child: Text('ms', style: TextStyle(fontFamily: 'Heebo', fontSize: 11, color: Color(0xFF64748B)))),
            const SizedBox(width: 20),
          ]),
        ),
        const Divider(height: 1),
        ..._log.map((r) {
          final ok = r['status'] == 'ok';
          return ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Row(children: [
              Expanded(flex: 3, child: Text(
                (r['cmd'] ?? '').toString().split(' ').take(4).join(' '),
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 12),
                overflow: TextOverflow.ellipsis,
              )),
              Expanded(flex: 2, child: Text(r['agent'] ?? '', style: const TextStyle(fontFamily: 'Heebo', fontSize: 11))),
              Expanded(flex: 2, child: Text(r['model'] ?? '', style: const TextStyle(fontFamily: 'Heebo', fontSize: 11), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 45, child: Text('${r['duration_ms'] ?? 0}', style: const TextStyle(fontFamily: 'Heebo', fontSize: 11))),
              Icon(ok ? Icons.check_circle : Icons.cancel, size: 16, color: ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
            ]),
            children: ok ? [] : [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(r['error'] ?? 'שגיאה לא ידועה',
                    style: const TextStyle(fontFamily: 'Heebo', fontSize: 12, color: Color(0xFFEF4444))),
              ),
            ],
          );
        }),
      ]),
    );
  }

  Widget _agentsAccordion() {
    final agents = Map<String, dynamic>.from(
        (_stats['agents'] as Map<String, dynamic>?) ?? {});
    if (agents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
        child: const Text('אין נתוני שימוש בסוכנים', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF64748B))),
      );
    }
    final entries = agents.entries.toList()
      ..sort((a, b) => ((b.value as Map)['count'] ?? 0).compareTo((a.value as Map)['count'] ?? 0));
    return Container(
      decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
      child: Column(children: entries.map((e) {
        final name = e.key;
        final data = Map<String, dynamic>.from(e.value as Map);
        final count = data['count'] ?? 0;
        final lastUsed = (data['last_used'] ?? '').toString();
        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600))),
            Text('×$count', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted)),
          ]),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (lastUsed.isNotEmpty)
                  Text('שימוש אחרון: ${lastUsed.length > 10 ? lastUsed.substring(0, 10) : lastUsed}',
                      style: TextStyle(fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted)),
              ]),
            ),
          ],
        );
      }).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final serverOk = _health['ok'] == true;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server status pill
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('סטטוס שרת', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: serverOk ? const Color(0xFF166534) : const Color(0xFF7F1D1D),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(serverOk ? '● Online' : '● Offline',
                  style: const TextStyle(fontFamily: 'Heebo', fontSize: 12, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 16),
          _modelChain(),
          const SizedBox(height: 16),
          const Text('לוג ביצוע', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _logTable(),
          const SizedBox(height: 16),
          const Text('סוכנים פעילים', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _agentsAccordion(),
        ],
      ),
    );
  }
}
```

Note: `widget.api.fetchStats()` needs to be added to `ApiService`:

```dart
Future<Map<String, dynamic>> fetchStats() async {
  try {
    final resp = await _client.get(_uri('/stats'), headers: _headers()).timeout(_timeout);
    if (resp.statusCode != 200) return {};
    return Map<String, dynamic>.from(jsonDecode(resp.body));
  } catch (_) { return {}; }
}
```

Add this to `api_service.dart` if it doesn't already exist.

- [ ] **Step 9.2 — Build + verify**

```bash
cd jarvis_mobile && flutter build apk --debug 2>&1 | tail -20
```

- [ ] **Step 9.3 — Commit**

```bash
git add jarvis_mobile/lib/screens/control_center/tab_overview.dart jarvis_mobile/lib/services/api_service.dart
git commit -m "feat: Tab 0 Overview — server status, model chain, execution log, agents accordion"
```

---

## Task 10: Tab 3 — Tests & Surveys

**Files:**
- Modify: `jarvis_mobile/lib/screens/control_center/tab_tests.dart`

- [ ] **Step 10.1 — Implement full Tab 3**

```dart
// jarvis_mobile/lib/screens/control_center/tab_tests.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../main.dart' show JC;
import '../../app_settings.dart';
import '../../services/api_service.dart';
import '../e2e_reports_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class TabTests extends StatefulWidget {
  final AppSettings settings;
  final ApiService api;
  const TabTests({super.key, required this.settings, required this.api});

  @override
  State<TabTests> createState() => _TabTestsState();
}

class _TabTestsState extends State<TabTests>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic> _weeklyScore = {};
  String _e2eSchedule = 'manual';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.api.fetchWeeklyScore(weeks: 6),
      widget.api.fetchE2eSchedule(),
    ]);
    if (!mounted) return;
    setState(() {
      _weeklyScore  = results[0] as Map<String, dynamic>;
      _e2eSchedule  = results[1] as String;
      _loading = false;
    });
  }

  // ── E2E Schedule card ────────────────────────────────────────────────────
  Widget _scheduleCard() {
    const modes = ['manual', 'daily', 'every2h', 'post_deploy'];
    const labels = {'manual': 'ידני', 'daily': 'יומי', 'every2h': 'כל שעתיים', 'post_deploy': 'אחרי Deploy'};
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Text('תזמון E2E אוטומטי',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: modes.map((m) {
            final active = m == _e2eSchedule;
            return GestureDetector(
              onTap: () async {
                await widget.api.setE2eSchedule(m);
                if (mounted) setState(() => _e2eSchedule = m);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF4F46E5) : JC.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? const Color(0xFF4F46E5) : JC.border),
                ),
                child: Text(labels[m] ?? m,
                    style: TextStyle(
                        fontFamily: 'Heebo', fontSize: 12,
                        color: active ? Colors.white : JC.textMuted)),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  // ── Survey timeline chart (fl_chart) ─────────────────────────────────────
  Widget _surveyTimeline() {
    final history = List<Map<String, dynamic>>.from(
        (_weeklyScore['history'] as List<dynamic>?) ?? []);
    if (history.isEmpty || history.every((h) => h['score'] == null)) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
        child: const Text('אין עדיין ציוני סקרים', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF64748B))),
      );
    }

    final spots = <FlSpot>[];
    final posSpots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      final h = history[history.length - 1 - i];
      final score = (h['score'] as num?)?.toDouble();
      final pos = (h['feedback_score'] as num?)?.toDouble();
      if (score != null) spots.add(FlSpot(i.toDouble(), score));
      if (pos != null) posSpots.add(FlSpot(i.toDouble(), pos));
    }

    return Container(
      height: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Text('ציון שבועי — 6 שבועות',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(LineChartData(
            gridData: FlGridData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10, fontFamily: 'Heebo')))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minY: 0, maxY: 100,
            lineBarsData: [
              LineChartBarData(spots: spots, isCurved: true, color: const Color(0xFF7C3AED),
                  barWidth: 2, dotData: FlDotData(show: false)),
              if (posSpots.isNotEmpty)
                LineChartBarData(spots: posSpots, isCurved: true, color: const Color(0xFF22C55E),
                    barWidth: 2, dotData: FlDotData(show: false), dashArray: [4, 4]),
            ],
          )),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Container(width: 12, height: 3, color: const Color(0xFF7C3AED)),
          const SizedBox(width: 4),
          const Text('ציון כולל', style: TextStyle(fontSize: 10, fontFamily: 'Heebo')),
          const SizedBox(width: 12),
          Container(width: 12, height: 3, color: const Color(0xFF22C55E)),
          const SizedBox(width: 4),
          const Text('משוב חיובי', style: TextStyle(fontSize: 10, fontFamily: 'Heebo')),
        ]),
      ]),
    );
  }

  // ── Export buttons ───────────────────────────────────────────────────────
  Widget _exportRow() => Row(children: [
    Expanded(child: _exportBtn('CSV', Icons.table_chart, () async {
      final url = await widget.api.exportSurveysUrl('csv');
      if (url != null) launchUrl(Uri.parse(url));
    })),
    const SizedBox(width: 8),
    Expanded(child: _exportBtn('PDF', Icons.picture_as_pdf, () async {
      final url = await widget.api.exportSurveysUrl('pdf');
      if (url != null) launchUrl(Uri.parse(url));
    })),
  ]);

  Widget _exportBtn(String label, IconData icon, VoidCallback onTap) =>
    ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontFamily: 'Heebo')),
      style: ElevatedButton.styleFrom(
        backgroundColor: JC.surface,
        foregroundColor: JC.textPrimary,
        side: BorderSide(color: JC.border),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // E2E Reports — embedded existing panel
          const Text('דוחות E2E', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 400,
            child: E2eReportsScreen(settings: widget.settings, embedded: true),
          ),
          const SizedBox(height: 16),
          _scheduleCard(),
          const SizedBox(height: 16),
          const Text('ציר זמן סקרים', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _surveyTimeline(),
          const SizedBox(height: 16),
          const Text('ייצוא סקרים', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _exportRow(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
```

- [ ] **Step 10.2 — Build + verify**

```bash
cd jarvis_mobile && flutter build apk --debug 2>&1 | tail -20
```

- [ ] **Step 10.3 — Commit**

```bash
git add jarvis_mobile/lib/screens/control_center/tab_tests.dart
git commit -m "feat: Tab 3 Tests — E2E embed, schedule card, survey timeline chart, export"
```

---

## Task 11: Tab 1 — Intelligence (weekly score + feedback loop)

**Files:**
- Modify: `jarvis_mobile/lib/screens/control_center/tab_intelligence.dart`

- [ ] **Step 11.1 — Implement full Tab 1**

```dart
// jarvis_mobile/lib/screens/control_center/tab_intelligence.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../app_settings.dart';
import '../../services/api_service.dart';

class TabIntelligence extends StatefulWidget {
  final AppSettings settings;
  final ApiService api;
  const TabIntelligence({super.key, required this.settings, required this.api});

  @override
  State<TabIntelligence> createState() => _TabIntelligenceState();
}

class _TabIntelligenceState extends State<TabIntelligence>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic> _weeklyScore = {};
  List<Map<String, dynamic>> _recentMessages = [];
  bool _loading = true;

  // Client-side set of already-rated message IDs (persisted via SharedPreferences in production;
  // here we keep it in-memory per session for simplicity).
  final Set<String> _ratedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.api.fetchWeeklyScore(weeks: 6),
      widget.api.fetchChatHistory(),
    ]);
    if (!mounted) return;
    final history = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
    // Show last 5 Jarvis messages that haven't been rated this session.
    final jarvisMessages = history
        .where((m) => m['role'] == 'jarvis' || m['role'] == 'assistant')
        .toList()
        .reversed
        .take(5)
        .toList();
    setState(() {
      _weeklyScore    = results[0] as Map<String, dynamic>;
      _recentMessages = jarvisMessages;
      _loading = false;
    });
  }

  Future<void> _rate(Map<String, dynamic> msg, String signal) async {
    final id = msg['id']?.toString() ?? msg['created_at']?.toString() ?? '';
    if (_ratedIds.contains(id)) return;
    setState(() => _ratedIds.add(id));
    await widget.api.sendFeedback(
      chatId: msg['chat_id']?.toString() ?? 'default-session',
      messageText: (msg['message'] ?? '').toString(),
      signal: signal,
      source: 'control_center',
    );
  }

  Widget _scoreCard() {
    final current = Map<String, dynamic>.from(
        (_weeklyScore['current'] as Map<String, dynamic>?) ?? {});
    final score = current['score'];
    if (score == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
        child: const Text('אין עדיין מספיק נתונים לחישוב ציון', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF64748B))),
      );
    }
    final successRate   = current['success_rate'];
    final feedbackScore = current['feedback_score'];

    Color scoreColor(int s) {
      if (s >= 80) return const Color(0xFF22C55E);
      if (s >= 50) return const Color(0xFFF59E0B);
      return const Color(0xFFEF4444);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JC.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('ציון שבועי', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          Text('$score', style: TextStyle(fontFamily: 'Heebo', fontSize: 36,
              fontWeight: FontWeight.w900, color: scoreColor(score))),
        ]),
        const SizedBox(height: 12),
        if (successRate != null) _breakdownRow('שיעור הצלחה', successRate, const Color(0xFF3B82F6)),
        if (feedbackScore != null) _breakdownRow('דירוגי משוב', feedbackScore, const Color(0xFF22C55E)),
      ]),
    );
  }

  Widget _breakdownRow(String label, int value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontFamily: 'Heebo', fontSize: 13))),
      SizedBox(width: 120, child: LinearProgressIndicator(
        value: value / 100, backgroundColor: JC.border,
        valueColor: AlwaysStoppedAnimation(color),
      )),
      const SizedBox(width: 8),
      Text('$value%', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted)),
    ]),
  );

  Widget _feedbackQueue() {
    final unrated = _recentMessages.where((m) {
      final id = m['id']?.toString() ?? m['created_at']?.toString() ?? '';
      return !_ratedIds.contains(id);
    }).toList();

    if (unrated.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
        child: const Text('כל התגובות דורגו — תודה! 🎉', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF22C55E))),
      );
    }

    return Column(children: unrated.map((msg) {
      final text = (msg['message'] ?? '').toString();
      final preview = text.length > 120 ? '${text.substring(0, 120)}…' : text;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JC.surface, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JC.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(preview, style: const TextStyle(fontFamily: 'Heebo', fontSize: 13)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => _rate(msg, 'up'),
              child: const Text('👍', style: TextStyle(fontSize: 18)),
            ),
            TextButton(
              onPressed: () => _rate(msg, 'down'),
              child: const Text('👎', style: TextStyle(fontSize: 18)),
            ),
          ]),
        ]),
      );
    }).toList());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ציון שבועי', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _scoreCard(),
          const SizedBox(height: 16),
          const Text('דירוג תגובות', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _feedbackQueue(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
```

`fetchChatHistory()` — add to `ApiService` if not already present:

```dart
Future<List<Map<String, dynamic>>> fetchChatHistory({String? chatId}) async {
  try {
    final path = chatId != null ? '/chat-history?chatId=$chatId' : '/chat-history';
    final resp = await _client.get(_uri(path), headers: _headers()).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(j['history'] ?? []);
  } catch (_) { return []; }
}
```

- [ ] **Step 11.2 — Build + verify**

```bash
cd jarvis_mobile && flutter build apk --debug 2>&1 | tail -20
```

- [ ] **Step 11.3 — Commit**

```bash
git add jarvis_mobile/lib/screens/control_center/tab_intelligence.dart jarvis_mobile/lib/services/api_service.dart
git commit -m "feat: Tab 1 Intelligence — weekly score breakdown + feedback rating queue"
```

---

## Task 12: Tab 2 — Dev Workshop (prompt library + test recorder + changelog)

**Files:**
- Modify: `jarvis_mobile/lib/screens/control_center/tab_devworkshop.dart`

- [ ] **Step 12.1 — Implement full Tab 2**

```dart
// jarvis_mobile/lib/screens/control_center/tab_devworkshop.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../main.dart' show JC;
import '../../app_settings.dart';
import '../../services/api_service.dart';

enum _WorkshopView { main, promptLibrary, testRecorder, changelog }

class TabDevWorkshop extends StatefulWidget {
  final AppSettings settings;
  final ApiService api;
  const TabDevWorkshop({super.key, required this.settings, required this.api});

  @override
  State<TabDevWorkshop> createState() => _TabDevWorkshopState();
}

class _TabDevWorkshopState extends State<TabDevWorkshop>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  _WorkshopView _view = _WorkshopView.main;

  // Prompt Library
  List<Map<String, dynamic>> _prompts = [];
  bool _loadingPrompts = true;

  // Test Recorder
  List<Map<String, dynamic>> _testCases = [];
  bool _recording = false;
  bool _loadingTests = true;
  String _recordingChatId = 'cc-recording';
  List<Map<String, dynamic>> _recordedTurns = [];
  final _testNameCtrl = TextEditingController();
  Map<String, dynamic>? _runResult;

  // Changelog
  List<Map<String, dynamic>> _changelogEntries = [];
  bool _loadingChangelog = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _testNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      widget.api.fetchPrompts(),
      widget.api.fetchTestCases(),
    ]);
    if (!mounted) return;
    setState(() {
      _prompts      = results[0] as List<Map<String, dynamic>>;
      _testCases    = results[1] as List<Map<String, dynamic>>;
      _loadingPrompts = false;
      _loadingTests   = false;
    });
  }

  // ── Prompt Library ────────────────────────────────────────────────────────
  Widget _promptLibraryView() {
    return Column(children: [
      // Header
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _view = _WorkshopView.main)),
          const Expanded(child: Text('ספריית פרומפטים',
              style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 18))),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showPromptDialog(null),
          ),
        ]),
      ),
      if (_loadingPrompts)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_prompts.isEmpty)
        const Expanded(child: Center(child: Text('אין פרומפטים עדיין',
            style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF64748B)))))
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _prompts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = _prompts[i];
              return Container(
                decoration: BoxDecoration(
                  color: JC.surface, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: JC.border),
                ),
                child: ListTile(
                  title: Text(p['name'] ?? '', style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                  subtitle: Text('v${p['version'] ?? 1} · ${(p['content'] ?? '').toString().substring(0, (p['content'] ?? '').toString().length.clamp(0, 60))}…',
                      style: TextStyle(fontFamily: 'Heebo', fontSize: 11, color: JC.textMuted)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _showPromptDialog(p)),
                    IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () async {
                      await widget.api.deletePrompt(p['id']);
                      final updated = await widget.api.fetchPrompts();
                      if (mounted) setState(() => _prompts = updated);
                    }),
                  ]),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Future<void> _showPromptDialog(Map<String, dynamic>? existing) async {
    final nameCtrl    = TextEditingController(text: existing?['name'] ?? '');
    final contentCtrl = TextEditingController(text: existing?['content'] ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JC.surface,
        title: Text(existing == null ? 'פרומפט חדש' : 'ערוך פרומפט',
            style: const TextStyle(fontFamily: 'Heebo')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
              style: const TextStyle(fontFamily: 'Heebo'),
              decoration: const InputDecoration(labelText: 'שם')),
          const SizedBox(height: 8),
          TextField(controller: contentCtrl,
              style: const TextStyle(fontFamily: 'Heebo'),
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'תוכן')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול', style: TextStyle(fontFamily: 'Heebo'))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (existing == null) {
                await widget.api.createPrompt(nameCtrl.text, contentCtrl.text);
              } else {
                await widget.api.updatePrompt(existing['id'], {'name': nameCtrl.text, 'content': contentCtrl.text});
              }
              final updated = await widget.api.fetchPrompts();
              if (mounted) setState(() => _prompts = updated);
            },
            child: const Text('שמור', style: TextStyle(fontFamily: 'Heebo')),
          ),
        ],
      ),
    );
  }

  // ── Test Recorder ─────────────────────────────────────────────────────────
  Widget _testRecorderView() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _view = _WorkshopView.main)),
          const Expanded(child: Text('Test Recorder',
              style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 18))),
        ]),
      ),
      Expanded(child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Recording controls
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _recording ? const Color(0xFFEF4444) : JC.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_recording ? '● מקליט...' : 'הקלטת שיחה',
                  style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700,
                      color: _recording ? const Color(0xFFEF4444) : JC.textPrimary)),
              const SizedBox(height: 4),
              Text(_recording
                  ? 'עבור לטאב שיחה ודבר עם ג\'רוויס. חזור לכאן ולחץ "עצור".'
                  : 'לחץ "התחל" → עבור לשיחה → חזור ולחץ "עצור".',
                  style: TextStyle(fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _recording ? _stopRecording : _startRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _recording ? const Color(0xFFEF4444) : const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_recording ? '⏹ עצור הקלטה' : '⏺ התחל הקלטה',
                      style: const TextStyle(fontFamily: 'Heebo')),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Recorded turns preview (after stop)
          if (_recordedTurns.isNotEmpty) ...[
            const Text('תורים שהוקלטו', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._recordedTurns.asMap().entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: JC.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('קלט: ${(e.value['input'] ?? '').toString().substring(0, (e.value['input'] ?? '').toString().length.clamp(0, 80))}',
                    style: const TextStyle(fontFamily: 'Heebo', fontSize: 12)),
                Text('intent: ${e.value['expected_intent'] ?? '-'}',
                    style: TextStyle(fontFamily: 'Heebo', fontSize: 11, color: JC.textMuted)),
              ]),
            )),
            const SizedBox(height: 8),
            TextField(controller: _testNameCtrl,
                style: const TextStyle(fontFamily: 'Heebo'),
                decoration: InputDecoration(
                  labelText: 'שם לבדיקה',
                  labelStyle: const TextStyle(fontFamily: 'Heebo'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                )),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveRecording,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white),
                child: const Text('💾 שמור בדיקה', style: TextStyle(fontFamily: 'Heebo')),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Existing test cases
          const Text('בדיקות שמורות', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_loadingTests)
            const Center(child: CircularProgressIndicator())
          else if (_testCases.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
              child: const Text('אין עדיין בדיקות מוקלטות', textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF64748B))),
            )
          else ..._testCases.map((tc) => _testCaseTile(tc)),
        ],
      )),
    ]);
  }

  Widget _testCaseTile(Map<String, dynamic> tc) {
    final status = tc['last_status'] ?? 'pending';
    final statusColor = status == 'pass' ? const Color(0xFF22C55E)
        : status == 'fail' ? const Color(0xFFEF4444) : const Color(0xFF64748B);
    final turns = (tc['turns'] is List) ? List.from(tc['turns'])
        : (tc['turns'] is String) ? [] : [];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: JC.border)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Row(children: [
          Expanded(child: Text(tc['name'] ?? '', style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(status, style: TextStyle(fontFamily: 'Heebo', fontSize: 11, color: statusColor)),
          ),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${turns.length} תורים', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted)),
              const SizedBox(height: 8),
              if (_runResult != null && _runResult!['tcId'] == tc['id']) ...[
                ...List<Map>.from(_runResult!['results'] ?? []).map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(r['pass'] == true ? Icons.check_circle : Icons.cancel, size: 14,
                        color: r['pass'] == true ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                        'צפוי: ${r['expected_intent']} | זוהה: ${r['detected_intent']}',
                        style: const TextStyle(fontFamily: 'Heebo', fontSize: 11))),
                  ]),
                )),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await widget.api.runTestCase(tc['id']);
                    if (result != null && mounted) {
                      setState(() => _runResult = {...result, 'tcId': tc['id']});
                      await _loadAll();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white,
                  ),
                  child: const Text('▶ הרץ שוב', style: TextStyle(fontFamily: 'Heebo')),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    final ok = await widget.api.startRecording(_recordingChatId);
    if (ok && mounted) setState(() { _recording = true; _recordedTurns = []; });
  }

  Future<void> _stopRecording() async {
    final result = await widget.api.stopRecording(_recordingChatId);
    if (result != null && mounted) {
      setState(() {
        _recording = false;
        _recordedTurns = List<Map<String, dynamic>>.from(result['turns'] ?? []);
      });
    }
  }

  Future<void> _saveRecording() async {
    if (_testNameCtrl.text.trim().isEmpty || _recordedTurns.isEmpty) return;
    await widget.api.saveTestCase(_testNameCtrl.text.trim(), _recordedTurns);
    _testNameCtrl.clear();
    if (mounted) setState(() => _recordedTurns = []);
    await _loadAll();
  }

  // ── Changelog ─────────────────────────────────────────────────────────────
  Widget _changelogView() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _view = _WorkshopView.main)),
          const Expanded(child: Text('Changelog', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 18))),
        ]),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loadingChangelog ? null : _generateChangelog,
            icon: _loadingChangelog
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: const Text('ייצר מ-git commits', style: TextStyle(fontFamily: 'Heebo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_changelogEntries.isEmpty && !_loadingChangelog)
          const Text('לחץ "ייצר" כדי לסכם שינויים אחרונים.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Heebo', color: Color(0xFF64748B)))
        else ..._changelogEntries.map((e) {
          final catEmoji = {'feature': '✨', 'fix': '🐛', 'ux': '💄', 'infra': '⚙️'}[e['category']] ?? '📝';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: JC.border)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$catEmoji ', style: const TextStyle(fontSize: 16)),
              Expanded(child: Text(e['message'] ?? '', style: const TextStyle(fontFamily: 'Heebo', fontSize: 13))),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () => Clipboard.setData(ClipboardData(text: '$catEmoji ${e['message']}')),
              ),
            ]),
          );
        }),
        if (_changelogEntries.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final text = _changelogEntries.map((e) {
                final emoji = {'feature': '✨', 'fix': '🐛', 'ux': '💄', 'infra': '⚙️'}[e['category']] ?? '📝';
                return '$emoji ${e['message']}';
              }).join('\n');
              Clipboard.setData(ClipboardData(text: text));
            },
            icon: const Icon(Icons.copy_all),
            label: const Text('העתק הכל', style: TextStyle(fontFamily: 'Heebo')),
          ),
        ],
      ])),
    ]);
  }

  Future<void> _generateChangelog() async {
    setState(() => _loadingChangelog = true);
    final entries = await widget.api.generateChangelog();
    if (mounted) setState(() { _changelogEntries = entries; _loadingChangelog = false; });
  }

  // ── Main view ─────────────────────────────────────────────────────────────
  Widget _mainView() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('כלי פיתוח', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 18)),
      const SizedBox(height: 16),
      _toolCard('📚 ספריית פרומפטים', 'נהל פרומפטים מערכתיים עם גרסאות', () => setState(() => _view = _WorkshopView.promptLibrary)),
      const SizedBox(height: 10),
      _toolCard('⏺ Test Recorder', 'הקלט שיחות אמיתיות וצור בדיקות רגרסיה', () => setState(() => _view = _WorkshopView.testRecorder)),
      const SizedBox(height: 10),
      _toolCard('📋 Changelog', 'ייצר סיכום שינויים מ-git commits', () => setState(() => _view = _WorkshopView.changelog)),
    ]);
  }

  Widget _toolCard(String title, String subtitle, VoidCallback onTap) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: JC.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(title, style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted)),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.chevron_left, color: JC.textMuted),
        ]),
      ),
    );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return switch (_view) {
      _WorkshopView.promptLibrary => _promptLibraryView(),
      _WorkshopView.testRecorder  => _testRecorderView(),
      _WorkshopView.changelog     => _changelogView(),
      _WorkshopView.main          => _mainView(),
    };
  }
}
```

- [ ] **Step 12.2 — Build + verify**

```bash
cd jarvis_mobile && flutter build apk --debug 2>&1 | tail -20
```
Expected: no errors.

- [ ] **Step 12.3 — Commit**

```bash
git add jarvis_mobile/lib/screens/control_center/tab_devworkshop.dart
git commit -m "feat: Tab 2 Dev Workshop — prompt library, test recorder, changelog"
```

---

## Task 13: Final wiring — push + PR

- [ ] **Step 13.1 — Run full test suite**

```bash
npm test
cd jarvis_mobile && flutter analyze lib/
```
Expected: all server tests pass; no Flutter errors.

- [ ] **Step 13.2 — Push**

```bash
git push -u origin claude/amazing-newton-0egkmm
```

- [ ] **Step 13.3 — Verify PR**

Check that PR #384 (or a new PR) exists on `nadavz-sketch/jarvis-server-nadav` targeting `main` from `claude/amazing-newton-0egkmm`. If not, create it (draft).

---

## Self-Review

### Spec coverage

| Spec section | Covered by |
|---|---|
| Tab 0 — server status, model chain, execution log, agents accordion | Task 9 |
| Tab 1 — weekly score, feedback queue, breakdown | Task 11 |
| Tab 2 — prompt library, test recorder, changelog | Task 12 |
| Tab 3 — E2E embed, schedule card, survey timeline, export | Task 10 |
| `GET /execution-log` | Task 3 |
| `active_model` in `/health` | Task 3 |
| `GET /stats/weekly-score` | Task 6 |
| `GET/PUT /e2e-schedule` | Task 6 |
| Prompt Library CRUD | Task 4 |
| Test Cases + recording + run | Task 5 |
| Changelog generate | Task 6 |
| Survey export CSV/PDF | Task 6 |
| Flutter file split into 5 files | Task 8 |
| Role-gating (regular=tabs 0+3, admin=all) | Task 8 (shell) |
| Adaptive polling 30s/120s | Tasks 9, 10 |
| `AutomaticKeepAliveClientMixin` (lazy load per tab) | All tab tasks |
| Real data only, empty states | All tab tasks |
| RTL Hebrew UI | All tab tasks |

### Gaps
- **`message_feedback` table**: spec mentions it but existing `/feedback` endpoint + `smart_telemetry_events` already stores 👍/👎 as `feedback_up`/`feedback_down` events. The weekly score query reads from `smart_telemetry_events` directly. No new table needed.
- **Auto-tuning proposals** (`/insights/proposals`): not yet implemented — requires an AI analysis pipeline. Marked as deferred; Tab 1 shows empty state until the endpoint exists.
- **Flaky detection badge** (spec: ≥2 pass + ≥2 fail in last 5 runs): `E2eReportsScreen` is embedded as-is. Flaky logic can be added in a follow-up task once the embedded panel exposes per-run history.
- **Inline 👍👎 in the chat tab**: the existing `/feedback` endpoint accepts these; the chat tab widget change is a separate PR not covered here.

### Type consistency
- `ApiService` methods return `Future<List<Map<String,dynamic>>>` or `Future<Map<String,dynamic>>` consistently.
- Repo methods throw on error for endpoint repos; swallow for fire-and-forget (`executionLogRepo.insert`).
- `CcTab` enum values match `_tabLabel`/`_tabBody` switch arms exactly.
