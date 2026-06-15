# Smart Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the memory system to auto-extract facts/preferences/context, detect conflicts via Pinecone, ask the user inline before saving/updating, archive replaced memories, and inject memories proactively into chat.

**Architecture:** `autoExtractMemory` now runs a new 3-type LLM prompt (fact/pref/context), calls `findConflict()` to check Pinecone similarity bands, and stores candidates in a server-side TTL cache instead of saving immediately. On the next request for the same chatId, `chatAgent` is told there is a pending memory and opens with the confirmation question. `POST /memories/confirm` handles the save-or-discard action including archiving the old memory.

**Tech Stack:** Node.js, Express, Pinecone (`findSimilarMemory`, `deleteMemory`), Supabase (`memories` table — `scope` field supports arbitrary string values), existing TTL cache (`cacheSet`/`cacheGet`), Jest.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `services/dataAccess/memoryRepo.js` | Add `updateById` call to repo (already in real repo — expose to agents) + `findByScope` |
| Modify | `tests/helpers/fakeRepos.js` | Add `updateById` + `findByScope` to `makeMemoryRepo` |
| Modify | `agents/memoryAgent.js` | New 3-type prompt, `findConflict()`, pending TTL cache, `saveSessionSummary()`, archive |
| Modify | `server.js` | Pending check at request start, `POST /memories/confirm`, session summary trigger |
| Modify | `agents/chatAgent.js` | `formatMemories()`, topK 8, lower Pinecone threshold, proactive instructions |
| Modify | `services/pineconeMemory.js` | Lower `SCORE_THRESHOLD` from 0.55 to 0.45 |
| Modify | `services/obsidianSync.js` | Topic-organized memory files (optional — only when `OBSIDIAN_VAULT_PATH` set) |

---

## Task 1: Repo Layer — `updateById` in fakeRepos + `findByScope` in real and fake repos

**Files:**
- Modify: `services/dataAccess/memoryRepo.js`
- Modify: `tests/helpers/fakeRepos.js`
- Test: `tests/unit/dataAccess/memoryRepo.test.js`

- [ ] **Step 1: Write the failing test**

Read `tests/unit/dataAccess/memoryRepo.test.js` to understand the existing test structure, then append these tests:

```javascript
describe('memoryRepo.findByScope', () => {
    test('returns rows matching scope', async () => {
        const supabase = makeSupabase([{ id: 1, content: '[fact] test', scope: 'archive' }]);
        const repo = createMemoryRepo(supabase);
        const rows = await repo.findByScope('archive');
        expect(rows).toHaveLength(1);
        expect(rows[0].content).toBe('[fact] test');
    });

    test('returns empty array when no rows match', async () => {
        const supabase = makeSupabase([]);
        const repo = createMemoryRepo(supabase);
        const rows = await repo.findByScope('archive');
        expect(rows).toEqual([]);
    });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/dataAccess/memoryRepo.test.js --verbose 2>&1 | tail -20
```

Expected: FAIL — `repo.findByScope is not a function`

- [ ] **Step 3: Add `findByScope` to `memoryRepo.js`**

In `services/dataAccess/memoryRepo.js`, add after `expiredByScope`:

```javascript
        // All memories with a given scope (used for archive queries and pending checks).
        async findByScope(scope, limit = 500) {
            const { data, error } = await supabase.from(M)
                .select('id, content, scope, created_at')
                .eq('scope', scope)
                .order('created_at', { ascending: false })
                .limit(limit);
            if (error) throw error;
            return data || [];
        },
```

- [ ] **Step 4: Add `updateById` and `findByScope` to `makeMemoryRepo` in `tests/helpers/fakeRepos.js`**

Find `function makeMemoryRepo` and replace the returned object to include two new methods:

```javascript
function makeMemoryRepo(opts = {}) {
    const { rows = [], insertResult, updateResult, updateByIdResult } = opts;
    return {
        findByContent:   jest.fn(async () => rows),
        allContents:     jest.fn(async () => rows.map(r => r.content)),
        recentByCreated: jest.fn(async () => rows),
        insert:          jest.fn(async () => insertResult || rows),
        update:          jest.fn(async () => updateResult || { error: null }),
        updateById:      jest.fn(async () => updateByIdResult || [rows[0] || { id: 1 }]),
        findByScope:     jest.fn(async () => rows),
        deleteByContent: jest.fn(async () => rows),
        expiredByScope:  jest.fn(async () => rows),
        deleteMany:      jest.fn(async () => ({ error: null })),
    };
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/dataAccess/memoryRepo.test.js --verbose 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add services/dataAccess/memoryRepo.js tests/helpers/fakeRepos.js tests/unit/dataAccess/memoryRepo.test.js
git commit -m "feat: add findByScope + updateById to memory repo"
```

---

## Task 2: Improved Extraction Prompt + Conflict Detection

**Files:**
- Modify: `agents/memoryAgent.js`
- Test: `tests/unit/memoryAgent.test.js`

This task replaces `AUTO_EXTRACT_PROMPT`, relaxes skip conditions, and adds a `findConflict()` helper.

- [ ] **Step 1: Write failing tests**

Append to `tests/unit/memoryAgent.test.js`:

```javascript
// ─── findConflict ──────────────────────────────────────────────────────────────

describe('findConflict', () => {
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('returns "new" when no similar memory found', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        const { findConflict } = require('../../agents/memoryAgent');
        const result = await findConflict('[fact] גר בירושלים');
        expect(result.type).toBe('new');
    });

    test('returns "duplicate" when similarity > 0.92', async () => {
        pinecone.findSimilarMemory.mockResolvedValue({ id: '5', content: '[fact] גר בירושלים', score: 0.95 });
        const { findConflict } = require('../../agents/memoryAgent');
        const result = await findConflict('[fact] גר בירושלים');
        expect(result.type).toBe('duplicate');
    });

    test('returns "update" when similarity is 0.70-0.92', async () => {
        pinecone.findSimilarMemory.mockResolvedValue({ id: '3', content: '[fact] גר בתל אביב', score: 0.80 });
        const { findConflict } = require('../../agents/memoryAgent');
        const result = await findConflict('[fact] גר בירושלים');
        expect(result.type).toBe('update');
        expect(result.existingId).toBe('3');
        expect(result.existingContent).toBe('[fact] גר בתל אביב');
    });
});

// ─── autoExtractMemory: new prompt types ─────────────────────────────────────

describe('autoExtractMemory — 3-type extraction', () => {
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('does NOT skip reminder intent (relaxed skip)', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        callGemma4.mockResolvedValue('{"memories":[{"type":"fact","content":"[fact] גר בתל אביב"}]}');
        const repos = makeRepos();
        // "תזמין לי פיצה" has reminder keyword but is ≥20 chars — should not skip
        await autoExtractMemory('תזמין לי פיצה לרחוב הרצל 5 בתל אביב', 'הזמנתי!', repos);
        expect(callGemma4).toHaveBeenCalled();
    });

    test('skips messages shorter than 20 chars', async () => {
        const repos = makeRepos();
        await autoExtractMemory('תודה', 'בשמחה', repos);
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('pending stored when new fact detected', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        callGemma4.mockResolvedValue('{"memories":[{"type":"fact","content":"[fact] גר בירושלים"}]}');
        const repos = makeRepos();
        const result = await autoExtractMemory(
            'אני גר בירושלים בשכונת גילה', 'נהדר!', repos, {}, 'chat-1'
        );
        // Should NOT save immediately — returns pending object
        expect(repos.memories.insert).not.toHaveBeenCalled();
        expect(result).toMatchObject({ type: 'new', content: '[fact] גר בירושלים' });
    });

    test('[context] type is saved directly (no confirmation needed)', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        callGemma4.mockResolvedValue('{"memories":[{"type":"context","content":"[context] עובד על מצגת"}]}');
        const repos = makeRepos({ memories: [{ id: 9 }] });
        await autoExtractMemory('מחר יש לי הצגה של המצגת לצוות', 'בהצלחה!', repos, {}, 'chat-2');
        expect(repos.memories.insert).toHaveBeenCalledWith({ content: '[context] עובד על מצגת', scope: 'session' });
    });
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/memoryAgent.test.js --verbose 2>&1 | grep -E "FAIL|PASS|findConflict|3-type" | head -20
```

Expected: multiple FAIL lines.

- [ ] **Step 3: Replace `AUTO_EXTRACT_PROMPT` and add `findConflict` in `memoryAgent.js`**

Replace the old `AUTO_EXTRACT_PROMPT` constant (lines 72-87) with:

```javascript
const AUTO_EXTRACT_PROMPT = `אתה מנתח שיחה ומחלץ עובדות אישיות חשובות לשמירה.

הודעת המשתמש: "{message}"
תגובת העוזר: "{answer}"

חלץ עד 3 פריטי מידע בעלי ערך לזיכרון ארוך טווח.
סווג כל פריט לאחת מהקטגוריות:
- [fact]: עובדה יציבה — משפחה, מקום מגורים, בריאות, עבודה, גיל
- [pref]: העדפה או דפוס התנהגות — מה אוהב, איך עובד, שגרת יום
- [context]: הקשר פעיל — פרויקט עכשווי, החלטה השבוע, מטרה קרובה

החזר JSON בלבד:
{ "memories": [ { "type": "fact|pref|context", "content": "[tag] תוכן בעברית" } ] }

כללים:
- רק מידע אישי ספציפי (לא שאלות כלליות)
- משפט אחד קצר לכל פריט
- אם אין מידע ראוי — החזר { "memories": [] }`;
```

- [ ] **Step 4: Add `findConflict` function after `checkDuplicate`**

After the `checkDuplicate` function (around line 52), add:

```javascript
/**
 * Determine how a new memory candidate relates to existing memories.
 * Returns:
 *   { type: 'duplicate' }                                        — similarity > 0.92
 *   { type: 'update', existingId, existingContent, score }       — 0.70 ≤ sim ≤ 0.92
 *   { type: 'new' }                                              — sim < 0.70 or Pinecone unavailable
 */
async function findConflict(content) {
    if (!pinecone.isReady()) return { type: 'new' };
    const similar = await pinecone.findSimilarMemory(content, 0.70);
    if (!similar) return { type: 'new' };
    if (similar.score > 0.92) return { type: 'duplicate' };
    return { type: 'update', existingId: similar.id, existingContent: similar.content, score: similar.score };
}
```

- [ ] **Step 5: Update `autoExtractMemory` to use the new prompt and `findConflict`**

Replace the entire `autoExtractMemory` function (lines 89-140) with:

```javascript
// Pending memory TTL cache (key: chatId, value: pending candidate).
// Consumed by server.js at the start of the next request for that chatId.
const _pendingMemories = new Map();
const PENDING_TTL_MS = 10 * 60 * 1000; // 10 minutes

function getPendingMemory(chatId) {
    const entry = _pendingMemories.get(chatId);
    if (!entry) return null;
    if (Date.now() > entry.expiresAt) { _pendingMemories.delete(chatId); return null; }
    return entry.data;
}

function clearPendingMemory(chatId) {
    _pendingMemories.delete(chatId);
}

async function autoExtractMemory(userMessage, assistantAnswer, repos, settings = {}, chatId = null) {
    const memories = repos.memories;
    try {
        // Skip on very short messages.
        if (!userMessage || userMessage.trim().length < 20) return null;
        // Skip weather/sports/news/stocks — no personal facts there.
        if (/מזג האוויר|תחזית|חדשות|כותרות|ספורט|תוצאות|מניות|שוק המניות|מה אתה יודע|מה ידוע לך|מחק זיכרון|הסר זיכרון/i.test(userMessage)) return null;

        const prompt = AUTO_EXTRACT_PROMPT
            .replace('{message}', userMessage)
            .replace('{answer}', (assistantAnswer || '').slice(0, 200));

        const aiText = await withRetry(() => callGemma4(
            [{ role: 'user', content: prompt }],
            settings.useLocalModel === true,
            400,
        ));

        const firstOpen = aiText.indexOf('{');
        const lastClose = aiText.lastIndexOf('}');
        if (firstOpen === -1 || lastClose === -1) return null;

        let parsed;
        try { parsed = JSON.parse(aiText.substring(firstOpen, lastClose + 1)); } catch { return null; }

        const items = Array.isArray(parsed.memories) ? parsed.memories : [];
        if (items.length === 0) return null;

        for (const item of items.slice(0, 3)) {
            const content = (item.content || '').trim();
            const type    = item.type || 'fact'; // 'fact' | 'pref' | 'context'
            if (!content) continue;

            // [context] memories are auto-saved without confirmation.
            if (type === 'context') {
                const dup = await checkDuplicate(content, memories);
                if (dup.duplicate) continue;
                const inserted = await memories.insert({ content, scope: 'session' });
                obsidianSync.dbToVault('memories', { content, scope: 'session' });
                if (inserted?.[0]?.id) pinecone.upsertMemory(inserted[0].id, content).catch(() => {});
                console.log('🧠 AutoExtract [context] saved:', content);
                _invalidateMemoryCache();
                continue;
            }

            // [fact] and [pref]: conflict detection → pending cache.
            const conflict = await findConflict(content);
            if (conflict.type === 'duplicate') {
                console.log('🧠 AutoExtract: duplicate skipped:', content);
                continue;
            }

            // Store as pending (new or update) — user must confirm.
            if (chatId) {
                _pendingMemories.set(chatId, {
                    data: { content, type, ...( conflict.type === 'update' && {
                        replacesId:      conflict.existingId,
                        replacesContent: conflict.existingContent,
                    })},
                    expiresAt: Date.now() + PENDING_TTL_MS,
                });
                console.log(`🧠 AutoExtract: pending [${type}] for chatId ${chatId}:`, content);
                return { type: conflict.type, content, ...( conflict.type === 'update' && {
                    replacesId: conflict.existingId, replacesContent: conflict.existingContent,
                })};
            }
        }
        return null;
    } catch (err) {
        console.error('AutoExtract error (suppressed):', err.message);
        return null;
    }
}
```

- [ ] **Step 6: Export the new functions**

Replace the `module.exports` line at the bottom of `memoryAgent.js`:

```javascript
module.exports = {
    runMemoryAgent, autoExtractMemory, checkDuplicate, findConflict,
    getPendingMemory, clearPendingMemory,
    setMemoryCacheInvalidator, deleteMemory, updateMemory,
};
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/memoryAgent.test.js --verbose 2>&1 | tail -25
```

Expected: All new tests pass; existing tests pass.

- [ ] **Step 8: Commit**

```bash
git add agents/memoryAgent.js tests/unit/memoryAgent.test.js
git commit -m "feat: 3-type extraction prompt, findConflict(), pending TTL cache in memoryAgent"
```

---

## Task 3: Session Summary

**Files:**
- Modify: `agents/memoryAgent.js`
- Test: `tests/unit/memoryAgent.test.js`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/memoryAgent.test.js`:

```javascript
// ─── saveSessionSummary ───────────────────────────────────────────────────────

describe('saveSessionSummary', () => {
    test('saves [context] summary when history has ≥5 turns', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        callGemma4.mockResolvedValue('השיחה עסקה בתכנון טיול לאילת ובבחירת מלון.');
        const repos = makeRepos({ memories: [{ id: 7 }] });
        const history = [
            { sender: 'user', text: 'תכנן לי טיול' },
            { sender: 'jarvis', text: 'לאן?' },
            { sender: 'user', text: 'אילת' },
            { sender: 'jarvis', text: 'מתי?' },
            { sender: 'user', text: 'בחודש הבא' },
        ];
        const { saveSessionSummary } = require('../../agents/memoryAgent');
        await saveSessionSummary('chat-99', repos, history);
        expect(repos.memories.insert).toHaveBeenCalledWith(
            expect.objectContaining({ content: expect.stringContaining('[context]'), scope: 'session' })
        );
    });

    test('does nothing when history has <5 turns', async () => {
        const repos = makeRepos();
        const { saveSessionSummary } = require('../../agents/memoryAgent');
        await saveSessionSummary('chat-99', repos, [{ sender: 'user', text: 'שלום' }]);
        expect(repos.memories.insert).not.toHaveBeenCalled();
    });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/memoryAgent.test.js -t "saveSessionSummary" --verbose 2>&1 | tail -15
```

Expected: FAIL — `saveSessionSummary is not a function`

- [ ] **Step 3: Add `saveSessionSummary` to `memoryAgent.js`**

Add before `module.exports`:

```javascript
async function saveSessionSummary(chatId, repos, history) {
    if (!history || history.length < 5) return;
    try {
        const turns = history.slice(-10)
            .map(m => `${m.sender === 'user' ? 'משתמש' : 'ג׳רביס'}: ${m.text}`)
            .join('\n');
        const prompt = `סכם בשני משפטים קצרים את נושאי השיחה הבאה (בעברית):\n${turns}\nהחזר רק את הסיכום, ללא הסברים.`;
        const summary = await callGemma4([{ role: 'user', content: prompt }], false, 200);
        if (!summary || summary.trim().length < 5) return;
        const content = `[context] ${summary.trim()}`;
        const inserted = await repos.memories.insert({ content, scope: 'session' });
        if (inserted?.[0]?.id) pinecone.upsertMemory(inserted[0].id, content).catch(() => {});
        _invalidateMemoryCache();
        console.log('🧠 Session summary saved for', chatId);
    } catch (err) {
        console.error('saveSessionSummary error (suppressed):', err.message);
    }
}
```

Update `module.exports` to include `saveSessionSummary`:

```javascript
module.exports = {
    runMemoryAgent, autoExtractMemory, checkDuplicate, findConflict,
    getPendingMemory, clearPendingMemory, saveSessionSummary,
    setMemoryCacheInvalidator, deleteMemory, updateMemory,
};
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/memoryAgent.test.js --verbose 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add agents/memoryAgent.js tests/unit/memoryAgent.test.js
git commit -m "feat: add saveSessionSummary for auto [context] after 5+ turn conversations"
```

---

## Task 4: `POST /memories/confirm` + Server.js Integration

**Files:**
- Modify: `server.js`
- Test: `tests/unit/parseDocument.test.js` ← reuse pattern, create `tests/unit/memoriesConfirm.test.js`

This task wires the pending check into the request start, adds the confirm endpoint, and triggers `saveSessionSummary`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/memoriesConfirm.test.js`:

```javascript
'use strict';

jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({ createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn() }) }));
jest.mock('openai', () => ({ OpenAI: jest.fn().mockImplementation(() => ({ audio: { transcriptions: { create: jest.fn() } } })), toFile: jest.fn() }));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: '' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({ initSync: jest.fn(), fullSyncFromDb: jest.fn(), appendChatMessage: jest.fn(), syncAll: jest.fn() }));
jest.mock('../../services/weatherSource', () => ({ getWeatherSummary: jest.fn().mockResolvedValue(null) }));
jest.mock('../../services/newsSource', () => ({ getNewsSummary: jest.fn().mockResolvedValue(null), getTopicHeadlines: jest.fn().mockResolvedValue(null) }));
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn(), callGemma4Stream: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
    upsertMemory: jest.fn().mockResolvedValue(true),
    searchMemories: jest.fn().mockResolvedValue(null),
    findSimilarMemory: jest.fn().mockResolvedValue(null),
    deleteMemory: jest.fn().mockResolvedValue(),
    isReady: jest.fn().mockReturnValue(false),
    syncFromSupabase: jest.fn(),
}));

const request = require('supertest');
const pinecone = require('../../services/pineconeMemory');
const memoryAgent = require('../../agents/memoryAgent');
const { app } = require('../../server');

describe('POST /memories/confirm', () => {
    beforeEach(() => jest.clearAllMocks());

    it('returns 400 when chatId missing', async () => {
        const res = await request(app).post('/memories/confirm').send({ action: 'save' });
        expect(res.status).toBe(400);
    });

    it('returns 404 when no pending memory for chatId', async () => {
        jest.spyOn(memoryAgent, 'getPendingMemory').mockReturnValue(null);
        const res = await request(app).post('/memories/confirm').send({ chatId: 'chat-x', action: 'save' });
        expect(res.status).toBe(404);
    });

    it('action=discard clears pending and returns ok', async () => {
        const clearSpy = jest.spyOn(memoryAgent, 'clearPendingMemory');
        jest.spyOn(memoryAgent, 'getPendingMemory').mockReturnValue({ content: '[fact] test', type: 'fact' });
        const res = await request(app).post('/memories/confirm').send({ chatId: 'chat-1', action: 'discard' });
        expect(res.status).toBe(200);
        expect(res.body.ok).toBe(true);
        expect(clearSpy).toHaveBeenCalledWith('chat-1');
    });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/memoriesConfirm.test.js --verbose 2>&1 | tail -15
```

Expected: FAIL — 404 on POST /memories/confirm

- [ ] **Step 3: Update `server.js` imports**

Find the existing memory imports line (around line 49):

```javascript
const { runMemoryAgent, autoExtractMemory, setMemoryCacheInvalidator } = require('./agents/memoryAgent');
```

Replace with:

```javascript
const {
    runMemoryAgent, autoExtractMemory, setMemoryCacheInvalidator,
    getPendingMemory, clearPendingMemory, saveSessionSummary,
} = require('./agents/memoryAgent');
```

- [ ] **Step 4: Update the `autoExtractMemory` call in `server.js` to pass `chatId`**

Find (around line 1146):

```javascript
            shouldExtract
                ? autoExtractMemory(originalMessage, answer, repos, settings).catch(e => { systemLog.logError('autoExtractMemory', e).catch(() => {}); return null; })
                : Promise.resolve(null),
```

Replace with:

```javascript
            shouldExtract
                ? autoExtractMemory(originalMessage, answer, repos, settings, chatId).catch(e => { systemLog.logError('autoExtractMemory', e).catch(() => {}); return null; })
                : Promise.resolve(null),
```

- [ ] **Step 5: Add session summary trigger in `server.js`**

Find the block after `Promise.all` (around line 1151):

```javascript
        // Summary update (fire-and-forget after response)
        if (shouldExtract) {
            setImmediate(() => {
                loadChatHistory(chatId).then(freshHistory => {
                    conversationSummary.updateSummaryIfNeeded(chatId, freshHistory, repos, settings).catch(e => systemLog.logError('updateSummaryIfNeeded', e).catch(() => {}));
                }).catch(e => systemLog.logError('loadChatHistory:postChat', e).catch(() => {}));
            });
        }
```

Replace with:

```javascript
        // Summary update + session memory summary (fire-and-forget after response)
        if (shouldExtract) {
            setImmediate(() => {
                loadChatHistory(chatId).then(freshHistory => {
                    conversationSummary.updateSummaryIfNeeded(chatId, freshHistory, repos, settings).catch(e => systemLog.logError('updateSummaryIfNeeded', e).catch(() => {}));
                    saveSessionSummary(chatId, repos, freshHistory).catch(e => systemLog.logError('saveSessionSummary', e).catch(() => {}));
                }).catch(e => systemLog.logError('loadChatHistory:postChat', e).catch(() => {}));
            });
        }
```

- [ ] **Step 6: Inject pending memory into chat context**

Find the section in `POST /ask-jarvis` that loads long-term memories (around line 500 in `fetchLongTermMemories`). Just before the main agent dispatch (look for `const result = await dispatch...` or similar), add:

```javascript
        // Inject pending memory confirmation question if one exists for this chatId.
        const pendingMemory = chatId ? getPendingMemory(chatId) : null;
        if (pendingMemory) {
            const isUpdate = !!pendingMemory.replacesId;
            const question = isUpdate
                ? `שמתי לב שציינת "${pendingMemory.content.replace(/^\[\w+\]\s*/, '')}" — זה שונה ממה שרשמתי (${pendingMemory.replacesContent?.replace(/^\[\w+\]\s*/, '') || '?'}). לעדכן?`
                : `שמתי לב שציינת "${pendingMemory.content.replace(/^\[\w+\]\s*/, '')}" — האם לשמור לזיכרון?`;
            settings = { ...settings, _pendingMemoryQuestion: question };
        }
```

Then in `chatAgent.js` `buildSystemPrompt`, add handling for `settings._pendingMemoryQuestion` — just before the `return` statement, prepend the question to the user message:

```javascript
    // Prepend pending memory confirmation question if one exists.
    const pendingQ = settings._pendingMemoryQuestion
        ? `[שים לב: לפני שתענה, פתח את תגובתך עם השאלה הזו: "${settings._pendingMemoryQuestion}"]\n`
        : '';

    return `You are ${name}...`; // existing return — prepend pendingQ inside the return
```

Specifically, change the return from:

```javascript
    return `You are ${name}, a personal AI assistant for ${userName}. Respond in Hebrew only.
```

to:

```javascript
    return `${pendingQ}You are ${name}, a personal AI assistant for ${userName}. Respond in Hebrew only.
```

- [ ] **Step 7: Add `POST /memories/confirm` endpoint to `server.js`**

Find `// ─── Document Parser` (the endpoint added in the chat-screen plan) and add BEFORE it:

```javascript
// ─── Memory Confirm ────────────────────────────────────────────────────────────

app.post('/memories/confirm', async (req, res) => {
    const { chatId, action } = req.body;
    if (!chatId) return res.status(400).json({ error: 'chatId required' });

    const pending = getPendingMemory(chatId);
    if (!pending) return res.status(404).json({ error: 'no pending memory for this chat' });

    clearPendingMemory(chatId);

    if (action === 'discard') return res.json({ ok: true });

    // action === 'save'
    try {
        const memories = repos.memories;
        const inserted = await memories.insert({ content: pending.content, scope: 'long_term' });
        if (inserted?.[0]?.id) {
            await pinecone.upsertMemory(inserted[0].id, pending.content).catch(() => {});
        }

        // Archive the old memory if this was an update.
        if (pending.replacesId) {
            await memories.updateById(pending.replacesId, { scope: 'archive' });
            await pinecone.deleteMemory(pending.replacesId).catch(() => {});
            console.log('🧠 Archived old memory:', pending.replacesId);
        }

        cacheInvalidate('memories');
        res.json({ ok: true, saved: pending.content });
    } catch (err) {
        console.error('❌ memories/confirm error:', err.message);
        res.status(500).json({ error: 'שגיאה בשמירת הזיכרון' });
    }
});
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/memoriesConfirm.test.js --verbose 2>&1 | tail -15
```

Expected: All 3 tests pass.

- [ ] **Step 9: Run full suite**

```bash
cd /home/user/jarvis-server-nadav && npm test 2>&1 | tail -10
```

Expected: All suites pass.

- [ ] **Step 10: Commit**

```bash
git add server.js agents/memoryAgent.js agents/chatAgent.js tests/unit/memoriesConfirm.test.js
git commit -m "feat: POST /memories/confirm, pending memory injection, session summary trigger"
```

---

## Task 5: chatAgent — Type-Aware Memory Formatting + Proactive Injection

**Files:**
- Modify: `agents/chatAgent.js`
- Modify: `services/pineconeMemory.js`
- Test: `tests/unit/chatAgent.test.js`

- [ ] **Step 1: Write the failing test**

Find `tests/unit/chatAgent.test.js`. Append:

```javascript
// ─── formatMemories ───────────────────────────────────────────────────────────

describe('formatMemories', () => {
    const { formatMemories } = require('../../agents/chatAgent');

    test('groups fact/pref/context into labeled sections', () => {
        const memories = [
            { content: '[fact] גר בירושלים' },
            { content: '[pref] מעדיף תשובות קצרות' },
            { content: '[context] עובד על מצגת' },
        ];
        const result = formatMemories(memories);
        expect(result).toContain('📌 עובדות:');
        expect(result).toContain('⭐ העדפות:');
        expect(result).toContain('🕐 הקשר אחרון:');
        expect(result).toContain('גר בירושלים');
        expect(result).not.toContain('[fact]');
    });

    test('returns empty string when no memories', () => {
        expect(formatMemories([])).toBe('');
    });

    test('handles legacy memories without prefix as facts', () => {
        const memories = [{ content: 'אוהב פיצה' }];
        const result = formatMemories(memories);
        // Legacy content has no prefix — should still appear
        expect(result).toContain('אוהב פיצה');
    });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/chatAgent.test.js -t "formatMemories" --verbose 2>&1 | tail -15
```

Expected: FAIL — `formatMemories is not a function`

- [ ] **Step 3: Add `formatMemories` to `chatAgent.js`**

After the `filterRelevantMemories` function (around line 173), add:

```javascript
/**
 * Formats a list of memory objects into a type-aware block for the system prompt.
 * Memories with [fact]/[pref]/[context] prefixes are grouped into labeled sections.
 * Legacy memories (no prefix) fall into the facts section.
 */
function formatMemories(memories) {
    if (!memories || memories.length === 0) return '';
    const clean = s => s.replace(/^\[(fact|pref|context)\]\s*/i, '').trim();
    const facts = memories.filter(m => /^\[fact\]/i.test(m.content) || !/^\[/.test(m.content));
    const prefs = memories.filter(m => /^\[pref\]/i.test(m.content));
    const ctx   = memories.filter(m => /^\[context\]/i.test(m.content));
    const lines = [];
    if (facts.length) lines.push(`📌 עובדות: ${facts.map(m => clean(m.content)).join(' · ')}`);
    if (prefs.length) lines.push(`⭐ העדפות: ${prefs.map(m => clean(m.content)).join(' · ')}`);
    if (ctx.length)   lines.push(`🕐 הקשר אחרון: ${ctx.map(m => clean(m.content)).join(' · ')}`);
    return lines.join('\n');
}
```

- [ ] **Step 4: Update `filterRelevantMemoriesAsync` topK from 5 to 8**

Find (line ~141):

```javascript
async function filterRelevantMemoriesAsync(memoriesText, userMessage, topK = 5) {
```

Change to:

```javascript
async function filterRelevantMemoriesAsync(memoriesText, userMessage, topK = 8) {
```

- [ ] **Step 5: Update `buildSystemPrompt` to use `formatMemories` and add proactive instructions**

In `buildSystemPrompt`, find the memories section (around line 255-274):

```javascript
    // Cap memories to 2000 chars (~650 tokens) so a large memory bank can't
    // flood the context budget. The most relevant lines are already ranked first
    // by filterRelevantMemoriesAsync, so the tail is the least useful content.
    // Cap at 1200 chars (~400 tokens). Relevant memories are ranked first by
    // filterRelevantMemoriesAsync, so the trimmed tail is the least useful content.
    const memoriesCapped = (longTermMemories || '').length > 1200
        ? longTermMemories.slice(0, 1200) + '\n(ועוד…)'
        : (longTermMemories || '');
```

Replace with:

```javascript
    // Format memories by type (fact/pref/context) for richer injection.
    // longTermMemories can be either a plain string (legacy) or array of objects.
    let formattedMemories;
    if (Array.isArray(longTermMemories)) {
        formattedMemories = formatMemories(longTermMemories);
    } else {
        const memStr = (longTermMemories || '').slice(0, 1200);
        formattedMemories = memStr ? memStr + (longTermMemories.length > 1200 ? '\n(ועוד…)' : '') : '';
    }
    const memoriesCapped = formattedMemories;
```

Then find the memories section in the returned prompt string (around line 273):

```javascript
--- Permanent Memories About ${userName} ---
${memoriesCapped}
--------------------------------------
```

Replace with:

```javascript
--- זיכרונות אישיים על ${userName} ---
${memoriesCapped}

הנחיות שימוש בזיכרון:
- שלב עובדות רלוונטיות בתשובה בצורה טבעית, ללא הכרזה מיוחדת.
- כשמתאים, הזכר מה שנאמר בשיחות קודמות ("כמו שאמרת...").
- כשיש ספק לגבי העדפה, שאל ("אתה מעדיף תשובה קצרה כרגיל?").
--------------------------------------
```

- [ ] **Step 6: Lower Pinecone `SCORE_THRESHOLD` in `pineconeMemory.js`**

Find line 8 in `services/pineconeMemory.js`:

```javascript
const SCORE_THRESHOLD   = 0.55;
```

Change to:

```javascript
const SCORE_THRESHOLD   = 0.45;
```

- [ ] **Step 7: Export `formatMemories` from `chatAgent.js`**

Find the `module.exports` line at the bottom of `chatAgent.js` and add `formatMemories`:

```javascript
module.exports = {
    runChatAgent, buildSystemPrompt, buildLocalMessages,
    detectFollowUp, filterRelevantMemories, filterRelevantMemoriesAsync,
    formatMemories,
    getMemoryRecallStats,
};
```

- [ ] **Step 8: Run tests**

```bash
cd /home/user/jarvis-server-nadav && npx jest tests/unit/chatAgent.test.js --verbose 2>&1 | tail -20
```

Expected: All tests pass including new `formatMemories` tests.

- [ ] **Step 9: Run full suite**

```bash
cd /home/user/jarvis-server-nadav && npm test 2>&1 | tail -10
```

Expected: All suites pass.

- [ ] **Step 10: Commit**

```bash
git add agents/chatAgent.js services/pineconeMemory.js
git commit -m "feat: type-aware memory formatting, proactive injection, topK=8, Pinecone threshold 0.45"
```

---

## Task 6: [context] Expiry + Obsidian Topic Files (Optional)

**Files:**
- Modify: `server.js` (cron job for [context] expiry)
- Modify: `services/obsidianSync.js` (topic-organized files)

- [ ] **Step 1: Add `[context]` expiry cron job to `server.js`**

Find the cron jobs section (look for `node-cron` `schedule` calls). Add a new daily job at 03:00:

```javascript
// Daily at 03:00 — expire [context] memories older than 7 days.
cron.schedule('0 3 * * *', async () => {
    try {
        const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
        const expired = await repos.memories.expiredByScope('session', cutoff);
        const contextExpired = expired.filter(m => m.content.startsWith('[context]'));
        if (contextExpired.length === 0) return;
        const ids = contextExpired.map(m => m.id);
        await repos.memories.deleteMany(ids);
        await Promise.allSettled(ids.map(id => pinecone.deleteMemory(id)));
        cacheInvalidate('memories');
        console.log(`🧠 Expired ${ids.length} [context] memories older than 7 days`);
    } catch (err) {
        console.error('❌ context expiry cron error:', err.message);
    }
}, { timezone: 'Asia/Jerusalem' });
```

- [ ] **Step 2: Update `obsidianSync.js` to write topic-organized memory files (when vault configured)**

Find `async function writeEntityFile(entity, record)` in `obsidianSync.js`. After the existing `if (entity === 'memories')` block (around line 115), update the `filePathForRecord` function to organize by type:

Find `function filePathForRecord(entity, record)` and update the memories section (around line 81):

```javascript
    if (entity === 'memories') {
        const content = record.content || '';
        let subdir = 'General';
        if (/^\[fact\]/i.test(content))    subdir = 'Facts';
        else if (/^\[pref\]/i.test(content)) subdir = 'Preferences';
        else if (/^\[context\]/i.test(content)) subdir = 'Recent';
        return path.join('Memories', subdir + '.md');
    }
```

- [ ] **Step 3: Run full suite to confirm no regressions**

```bash
cd /home/user/jarvis-server-nadav && npm test 2>&1 | tail -10
```

Expected: All suites pass.

- [ ] **Step 4: Commit and push**

```bash
git add server.js services/obsidianSync.js
git commit -m "feat: [context] memory expiry cron (7 days) + Obsidian topic-organized files"
git push -u origin claude/plugins-installation-ka1skx
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|----------------|------|
| 3-type extraction prompt ([fact]/[pref]/[context]) | Task 2 |
| Relaxed skip (reminder/notes no longer skipped) | Task 2 |
| `findConflict()` → new / update (0.70–0.92) / duplicate (>0.92) | Task 2 |
| Pending memory TTL cache, [context] auto-saved | Task 2 |
| `saveSessionSummary` after ≥5 turns | Task 3 |
| `POST /memories/confirm` endpoint | Task 4 |
| Pending injected into next chat request | Task 4 |
| Archive old memory on update (scope='archive', removed from Pinecone) | Task 4 |
| `formatMemories()` type-aware sections | Task 5 |
| Pinecone topK 8, threshold 0.45 | Task 5 |
| Proactive memory usage instructions in system prompt | Task 5 |
| `[context]` expiry after 7 days | Task 6 |
| Obsidian topic-organized files | Task 6 |
| `updateById` + `findByScope` repo methods | Task 1 |
| `makeMemoryRepo` updated in fakeRepos | Task 1 |

All spec requirements covered. No placeholders. Method names consistent: `findConflict`, `getPendingMemory`, `clearPendingMemory`, `saveSessionSummary`, `formatMemories` — used the same way in tests and implementation.
