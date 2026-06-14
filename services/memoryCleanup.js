'use strict';

// Periodically prune session/recent memories that have outlived their scope window.
// Schema: memories.scope ∈ { 'long_term' | 'recent' | 'session' }
//   session  → 24h TTL
//   recent   → 7d  TTL
//   long_term → never expires here
//
// Also removes the corresponding Pinecone vectors so semantic search stays clean.

const pinecone      = require('./pineconeMemory');
const obsidianSync  = require('./obsidianSync');

const SESSION_TTL_MS = 24 * 60 * 60 * 1000;
const RECENT_TTL_MS  = 7 * 24 * 60 * 60 * 1000;

async function cleanupExpiredMemories(repos) {
    if (!repos) return { deleted: 0, error: 'no repos' };
    const nowIso = (msAgo) => new Date(Date.now() - msAgo).toISOString();

    let totalDeleted = 0;
    const errors = [];

    for (const { scope, cutoff } of [
        { scope: 'session', cutoff: nowIso(SESSION_TTL_MS) },
        { scope: 'recent',  cutoff: nowIso(RECENT_TTL_MS)  },
    ]) {
        try {
            // Fetch id + content so we can remove both vectors and vault entries.
            const rows = await repos.memories.expiredByScope(scope, cutoff, 500);
            if (!rows || rows.length === 0) continue;

            const ids = rows.map(r => r.id);
            const { error: delErr } = await repos.memories.deleteMany(ids);
            if (delErr) throw delErr;

            // Best-effort vector + vault cleanup; ignore individual failures.
            await Promise.allSettled([
                ...rows.map(r => pinecone.deleteMemory(r.id)),
                ...rows.map(r => Promise.resolve(obsidianSync.removeFromVault('memories', r))),
            ]);
            totalDeleted += ids.length;
            console.info(`[memoryCleanup] deleted ${ids.length} ${scope} memories older than ${cutoff}`);
        } catch (err) {
            errors.push(`${scope}: ${err.message}`);
        }
    }

    return { deleted: totalDeleted, errors };
}

module.exports = { cleanupExpiredMemories, SESSION_TTL_MS, RECENT_TTL_MS };
