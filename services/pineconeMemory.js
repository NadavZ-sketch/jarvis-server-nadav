'use strict';
require('dotenv').config();
const axios    = require('axios');
const { Pinecone } = require('@pinecone-database/pinecone');

const PINECONE_API_KEY = process.env.PINECONE_API_KEY;
const GOOGLE_KEY       = process.env.GOOGLE_API_KEY;
const INDEX_NAME       = 'jarvis-memories';
const EMBED_DIM        = 768;
const SCORE_THRESHOLD  = 0.55; // cosine similarity — above this = relevant

const EMBED_URL = `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${GOOGLE_KEY}`;

let _index  = null;
let _ready  = false;
let _initPromise = null;

// ─── Init (lazy, singleton) ───────────────────────────────────────────────────

async function _init() {
    if (!PINECONE_API_KEY) {
        console.log('🔵 Pinecone: PINECONE_API_KEY not set — semantic search disabled');
        return;
    }
    try {
        const pc = new Pinecone({ apiKey: PINECONE_API_KEY });

        // Auto-create index if it doesn't exist
        const listRes  = await pc.listIndexes();
        const existing = (listRes.indexes || []).some(i => i.name === INDEX_NAME);
        if (!existing) {
            console.log(`🔵 Pinecone: creating index "${INDEX_NAME}" (768 dims, cosine)...`);
            await pc.createIndex({
                name:   INDEX_NAME,
                dimension: EMBED_DIM,
                metric: 'cosine',
                spec:   { serverless: { cloud: 'aws', region: 'us-east-1' } },
            });
            // Wait for index to be ready (up to 60s)
            for (let i = 0; i < 12; i++) {
                await new Promise(r => setTimeout(r, 5000));
                const desc = await pc.describeIndex(INDEX_NAME);
                if (desc.status?.ready) break;
            }
        }

        _index = pc.index(INDEX_NAME);
        _ready = true;
        console.log('🔵 Pinecone: ready ✅');
    } catch (err) {
        console.error('🔵 Pinecone: init failed —', err.message, '— falling back to keyword search');
    }
}

function ensureInit() {
    if (!_initPromise) _initPromise = _init();
    return _initPromise;
}

// ─── Embedding ────────────────────────────────────────────────────────────────

async function embed(text) {
    const res = await axios.post(EMBED_URL, {
        model:   'models/text-embedding-004',
        content: { parts: [{ text: text.slice(0, 2000) }] },
    }, { timeout: 8000 });
    return res.data.embedding.values; // float[]  length=768
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Upsert a memory into Pinecone.
 * @param {string|number} id  — Supabase row id
 * @param {string}        content
 * @returns {boolean}  true on success
 */
async function upsertMemory(id, content) {
    await ensureInit();
    if (!_ready) return false;
    try {
        const values = await embed(content);
        await _index.upsert([{ id: String(id), values, metadata: { content } }]);
        return true;
    } catch (err) {
        console.error('🔵 Pinecone upsert error:', err.message);
        return false;
    }
}

/**
 * Semantic search — returns relevant memory strings.
 * Returns null if Pinecone is not available (caller should fall back).
 * @param {string} query
 * @param {number} topK
 * @returns {string[]|null}
 */
async function searchMemories(query, topK = 12) {
    await ensureInit();
    if (!_ready) return null;
    try {
        const values = await embed(query);
        const result = await _index.query({ vector: values, topK, includeMetadata: true });
        return (result.matches || [])
            .filter(m => m.score >= SCORE_THRESHOLD)
            .map(m => m.metadata.content);
    } catch (err) {
        console.error('🔵 Pinecone search error:', err.message);
        return null;
    }
}

/**
 * Delete a memory from Pinecone by Supabase id.
 */
async function deleteMemory(id) {
    await ensureInit();
    if (!_ready) return;
    try {
        await _index.deleteOne(String(id));
    } catch (err) {
        console.error('🔵 Pinecone delete error:', err.message);
    }
}

/**
 * One-time sync: push all existing Supabase memories to Pinecone.
 * Safe to call on startup — skips memories already in Pinecone.
 */
async function syncFromSupabase(supabase) {
    await ensureInit();
    if (!_ready) return;
    try {
        const { data } = await supabase.from('memories').select('id, content');
        if (!data || data.length === 0) return;
        console.log(`🔵 Pinecone: syncing ${data.length} existing memories...`);
        // Batch into groups of 10 to avoid rate limits
        for (let i = 0; i < data.length; i += 10) {
            const batch = data.slice(i, i + 10);
            await Promise.allSettled(batch.map(m => upsertMemory(m.id, m.content)));
        }
        console.log('🔵 Pinecone: sync complete');
    } catch (err) {
        console.error('🔵 Pinecone sync error:', err.message);
    }
}

/** Is Pinecone ready? (for health checks) */
function isReady() { return _ready; }

module.exports = { upsertMemory, searchMemories, deleteMemory, syncFromSupabase, ensureInit, isReady };
