'use strict';

// Periodically prune session/recent memories that have outlived their scope window.
// Schema: memories.scope ∈ { 'long_term' | 'recent' | 'session' }
//   session  → 24h TTL
//   recent   → 7d  TTL
//   long_term → never expires here
//
// Also removes the corresponding Pinecone vectors so semantic search stays clean.

const pinecone = require('./pineconeMemory');

const SESSION_TTL_MS = 24 * 60 * 60 * 1000;
const RECENT_TTL_MS  = 7 * 24 * 60 * 60 * 1000;

async function cleanupExpiredMemories(supabase) {
    if (!supabase) return { deleted: 0, error: 'no supabase client' };
    const nowIso = (msAgo) => new Date(Date.now() - msAgo).toISOString();

    let totalDeleted = 0;
    const errors = [];

    for (const { scope, cutoff } of [
        { scope: 'session', cutoff: nowIso(SESSION_TTL_MS) },
        { scope: 'recent',  cutoff: nowIso(RECENT_TTL_MS)  },
    ]) {
        try {
            // Fetch ids first so we can also remove vectors.
            const { data: rows, error } = await supabase
                .from('memories')
                .select('id')
                .eq('scope', scope)
                .lt('created_at', cutoff)
                .limit(500);
            if (error) throw error;
            if (!rows || rows.length === 0) continue;

            const ids = rows.map(r => r.id);
            const { error: delErr } = await supabase.from('memories').delete().in('id', ids);
            if (delErr) throw delErr;

            // Best-effort vector cleanup; ignore failures.
            await Promise.allSettled(ids.map(id => pinecone.deleteMemory(id)));
            totalDeleted += ids.length;
            console.log(`🧹 memoryCleanup: deleted ${ids.length} ${scope} memories older than ${cutoff}`);
        } catch (err) {
            errors.push(`${scope}: ${err.message}`);
        }
    }

    return { deleted: totalDeleted, errors };
}

module.exports = { cleanupExpiredMemories, SESSION_TTL_MS, RECENT_TTL_MS };
