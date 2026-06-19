'use strict';
require('dotenv').config();
const { Pinecone } = require('@pinecone-database/pinecone');

const PINECONE_API_KEY  = process.env.PINECONE_API_KEY;
const PINECONE_HOST     = process.env.PINECONE_INDEX_HOST;
const INDEX_NAME        = 'jarvis-memory';
const SCORE_THRESHOLD   = 0.45;

let _index       = null;
let _ready       = false;
let _initPromise = null;

// ─── Init (lazy, singleton) ───────────────────────────────────────────────────

async function _init() {
    if (!PINECONE_API_KEY) {
        console.info('[Pinecone] PINECONE_API_KEY not set — semantic search disabled');
        return;
    }
    try {
        const pc = new Pinecone({ apiKey: PINECONE_API_KEY });
        _index = PINECONE_HOST ? pc.index(INDEX_NAME, PINECONE_HOST) : pc.index(INDEX_NAME);
        _ready = true;
        console.info('[Pinecone] ready');
    } catch (err) {
        console.error('🔵 Pinecone: init failed —', err.message, '— falling back to keyword search');
    }
}

function ensureInit() {
    if (!_initPromise) _initPromise = _init();
    return _initPromise;
}

// ─── Public API ───────────────────────────────────────────────────────────────

async function upsertMemory(id, content) {
    await ensureInit();
    if (!_ready) return false;
    try {
        await _index.upsertRecords({ records: [{ id: String(id), text: content }] });
        return true;
    } catch (err) {
        const src = err.config?.url?.includes('generativelanguage') ? '[Google Embed]' : '[Pinecone]';
        console.error(`🔵 Pinecone upsert error ${src}:`, err.message);
        return false;
    }
}

async function searchMemories(query, topK = 12) {
    await ensureInit();
    if (!_ready) return null;
    try {
        const result = await _index.searchRecords({
            query: { inputs: { text: query }, topK },
            fields: ['text'],
        });
        return (result.result?.hits || [])
            .filter(h => h._score >= SCORE_THRESHOLD)
            .map(h => h.fields?.text || '');
    } catch (err) {
        const src = err.config?.url?.includes('generativelanguage') ? '[Google Embed]' : '[Pinecone]';
        console.error(`🔵 Pinecone search error ${src}:`, err.message);
        return null;
    }
}

async function findSimilarMemory(content, threshold = 0.92) {
    await ensureInit();
    if (!_ready) return null;
    try {
        const result = await _index.searchRecords({
            query: { inputs: { text: content }, topK: 1 },
            fields: ['text'],
        });
        const top = result.result?.hits?.[0];
        if (!top || top._score < threshold) return null;
        return { id: String(top._id), content: top.fields?.text || '', score: top._score };
    } catch (err) {
        console.error('🔵 Pinecone findSimilar error:', err.message);
        return null;
    }
}

async function searchMemoriesDetailed(query, topK = 12) {
    await ensureInit();
    if (!_ready) return null;
    try {
        const result = await _index.searchRecords({
            query: { inputs: { text: query }, topK },
            fields: ['text'],
        });
        return (result.result?.hits || [])
            .filter(h => h._score >= SCORE_THRESHOLD)
            .map(h => ({ id: String(h._id), content: h.fields?.text || '', score: h._score }));
    } catch (err) {
        console.error('🔵 Pinecone search detailed error:', err.message);
        return null;
    }
}

async function deleteMemory(id) {
    await ensureInit();
    if (!_ready) return;
    try {
        await _index.deleteOne(String(id));
    } catch (err) {
        console.error('🔵 Pinecone delete error:', err.message);
    }
}

async function syncFromSupabase(supabase) {
    await ensureInit();
    if (!_ready) return;
    try {
        const { data } = await supabase.from('memories').select('id, content');
        const memories = data || [];
        const supabaseIds = new Set(memories.map(m => String(m.id)));

        console.info(`[Pinecone] syncing ${memories.length} memories...`);
        for (let i = 0; i < memories.length; i += 10) {
            const batch = memories.slice(i, i + 10);
            await Promise.allSettled(batch.map(m => upsertMemory(m.id, m.content)));
        }

        // Remove orphaned vectors
        try {
            const orphanIds = [];
            let paginationToken;
            do {
                const res = await _index.listPaginated({ limit: 100, paginationToken });
                for (const v of (res.vectors || [])) {
                    if (!supabaseIds.has(v.id)) orphanIds.push(v.id);
                }
                paginationToken = res.pagination?.next;
            } while (paginationToken);

            if (orphanIds.length > 0) {
                console.info(`[Pinecone] removing ${orphanIds.length} orphaned vector(s)...`);
                for (let i = 0; i < orphanIds.length; i += 100) {
                    await _index.deleteMany(orphanIds.slice(i, i + 100));
                }
            }
        } catch (orphanErr) {
            console.warn('🔵 Pinecone: orphan cleanup skipped —', orphanErr.message);
        }

        console.info('[Pinecone] sync complete');
    } catch (err) {
        console.error('🔵 Pinecone sync error:', err.message);
    }
}

async function listAll() {
    await ensureInit();
    if (!_ready) return [];
    try {
        const ids = [];
        let paginationToken;
        do {
            const res = await _index.listPaginated({ limit: 100, paginationToken });
            for (const v of (res.vectors || [])) ids.push(v.id);
            paginationToken = res.pagination?.next;
        } while (paginationToken);

        if (!ids.length) return [];

        // Fetch records in batches of 100 to get text content
        const records = [];
        for (let i = 0; i < ids.length; i += 100) {
            const batch = ids.slice(i, i + 100);
            try {
                const fetched = await _index.fetch(batch);
                for (const [id, vec] of Object.entries(fetched?.records || fetched?.vectors || {})) {
                    const text = vec.fields?.text || vec.metadata?.text || '';
                    if (text) records.push({ id, content: text });
                }
            } catch (fetchErr) {
                console.warn('🔵 Pinecone fetch batch error:', fetchErr.message);
            }
        }
        return records;
    } catch (err) {
        console.error('🔵 Pinecone listAll error:', err.message);
        return [];
    }
}



function isReady() { return _ready; }

module.exports = {
    upsertMemory, searchMemories, searchMemoriesDetailed, findSimilarMemory,
    deleteMemory, syncFromSupabase, listAll, ensureInit, isReady,
};
