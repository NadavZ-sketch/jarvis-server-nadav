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
        if (!match || match.score < CONFLICT_THRESHOLD || !match.content) continue;

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

        try {
            const outcome = await upsertFinding(repos, {
                type: isDuplicate ? 'duplicate' : 'conflict',
                memoryId: aId, relatedMemoryId: bId,
                suggestedAction: isDuplicate ? 'merge' : 'archive',
                suggestedPayload, score: match.score,
                contentHash: hashPair(mem.content, match.content),
            });
            tally(summary, outcome);
        } catch (err) {
            summary.errors.push(`duplicate-scan-write ${aId}:${bId}: ${err.message}`);
        }
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

        try {
            const outcome = await upsertFinding(repos, {
                type: 'category_mismatch', memoryId: String(mem.id),
                suggestedAction: 'move', suggestedPayload: { category: suggested },
                contentHash: hashContent(mem.content),
            });
            tally(summary, outcome);
        } catch (err) {
            summary.errors.push(`category-mismatch-write ${mem.id}: ${err.message}`);
        }
    }
}

async function scanStaleAndThin(memories, repos, summary) {
    const staleCutoff = Date.now() - STALE_MS;
    for (const mem of memories) {
        const core = (mem.content || '').replace(/^\[[^\]]+\]\s*/, '').trim();
        const wordCount = core ? core.split(/\s+/).length : 0;

        if (wordCount > 0 && wordCount < THIN_WORDS) {
            try {
                const outcome = await upsertFinding(repos, {
                    type: 'thin_content', memoryId: String(mem.id),
                    suggestedAction: 'delete', suggestedPayload: null,
                    contentHash: hashContent(mem.content),
                });
                tally(summary, outcome);
            } catch (err) {
                summary.errors.push(`thin-content-write ${mem.id}: ${err.message}`);
            }
            continue; // thin takes priority over stale for the same memory
        }

        if (mem.created_at && new Date(mem.created_at).getTime() < staleCutoff) {
            try {
                const outcome = await upsertFinding(repos, {
                    type: 'stale', memoryId: String(mem.id),
                    suggestedAction: 'archive', suggestedPayload: null,
                    contentHash: hashContent(mem.content),
                });
                tally(summary, outcome);
            } catch (err) {
                summary.errors.push(`stale-write ${mem.id}: ${err.message}`);
            }
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
            // Auto-resolved silently — no approval-needed finding row is written
            // for orphans, only counted in the summary.
            summary.autoResolved++;
        } catch (err) {
            summary.errors.push(`resync-row ${row.id}: ${err.message}`);
        }
    }

    for (const rec of pineconeRecords) {
        if (supabaseIds.has(String(rec.id))) continue;
        try {
            await pinecone.deleteMemory(rec.id);
            // Auto-resolved silently — no approval-needed finding row is written
            // for orphans, only counted in the summary.
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
