'use strict';

const pinecone     = require('./pineconeMemory');
const obsidianSync = require('./obsidianSync');

// ── In-process TTL cache (keyword-fallback when Pinecone is absent) ───────────
const _cache    = new Map();
const CACHE_TTL = 30_000; // 30 s — short so newly-saved memories surface quickly

function _cacheGet(key) {
    const e = _cache.get(key);
    if (!e || Date.now() > e.expiresAt) { _cache.delete(key); return null; }
    return e.value;
}
function _cacheSet(key, val) {
    _cache.set(key, { value: val, expiresAt: Date.now() + CACHE_TTL });
}
function invalidateCache() { _cache.delete('memories'); }

// ── Pending TTL store (fact/pref candidates awaiting user confirmation) ────────
const _pending     = new Map();
const PENDING_TTL  = 10 * 60 * 1000; // 10 min per chatId

function setPending(chatId, data) {
    _pending.set(String(chatId), { data, expiresAt: Date.now() + PENDING_TTL });
}

function getPending(chatId) {
    const e = _pending.get(String(chatId));
    if (!e) return null;
    if (Date.now() > e.expiresAt) { _pending.delete(String(chatId)); return null; }
    return e.data;
}

function clearPending(chatId) { _pending.delete(String(chatId)); }

// ── Raw fetch: Pinecone semantic → Supabase keyword (TTL cached) ──────────────
async function _fetchRaw(userMessage, repos) {
    if (userMessage && pinecone.isReady()) {
        try {
            const hits = await pinecone.searchMemories(userMessage, 12);
            if (hits !== null) return hits.map(c => ({ content: c }));
        } catch { /* fall through */ }
    }

    const cached = _cacheGet('memories');
    if (cached) return cached;

    try {
        const contents = await repos.memories.allContents();
        const result = contents.map(c => ({ content: c }));
        _cacheSet('memories', result);
        return result;
    } catch (err) {
        console.error('[memoryContext] allContents error (returning empty):', err.message);
        return [];
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Load structured memories + pending state for a single request.
 * Returns { memories: [{ content: string }], pending: object | null }
 * Ranking is the caller's responsibility (chatAgent uses rankMemories; others use formatAsText).
 */
async function loadForRequest(userMessage, chatId, repos) {
    const memories = await _fetchRaw(userMessage || null, repos);
    const pending  = chatId ? getPending(chatId) : null;
    return { memories, pending };
}

/**
 * Simple text block for non-chat agents that need a formatted string.
 */
function formatAsText(memories) {
    if (!memories || memories.length === 0) return 'אין עדיין זיכרונות שמורים.';
    return memories.map(m => `- ${m.content}`).join('\n');
}

/**
 * Persist a pending-memory object that the caller already retrieved and cleared.
 * Separated so the endpoint can use spyable wrappers for the check/clear step.
 * Returns { saved: true, content: string }.
 */
async function savePendingData(pending, repos) {
    const inserted = await repos.memories.insert({ content: pending.content, scope: 'long_term' });
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

/**
 * Convenience: look up, clear, and save in one call.
 * For callers that don't need to spy on the lookup/clear separately.
 */
async function confirmPending(chatId, repos) {
    const pending = getPending(chatId);
    if (!pending) return { saved: false };
    clearPending(chatId);
    return savePendingData(pending, repos);
}

module.exports = {
    loadForRequest,
    formatAsText,
    savePendingData,
    confirmPending,
    setPending,
    getPending,
    clearPending,
    invalidateCache,
};
