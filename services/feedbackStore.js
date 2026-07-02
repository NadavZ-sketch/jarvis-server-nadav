'use strict';

/**
 * Lightweight writer/reader for the `smart_telemetry_events` table.
 *
 * This is the foundation of Jarvis's feedback loop: explicit feedback (👍/👎,
 * corrections) and — later — implicit signals are recorded here as events. The
 * table already existed in the schema (migration 20260511) but had no
 * server-side writer; this module fills that gap.
 *
 * All writes are fire-and-forget and never throw into the request path. The
 * server uses the service-role Supabase client, which bypasses the table's RLS,
 * so a constant `user_id` (single-user backend) is fine.
 */

// signal string → numeric event_value
const SIGNAL_VALUE = { up: 1, down: -1 };

/**
 * Insert a single telemetry event. Returns { ok } and never throws.
 * @param {object} supabase Supabase client
 * @param {{userId?:string, eventName:string, value?:number, metadata?:object}} evt
 */
async function recordEvent(repos, { userId = 'default', eventName, value = 1, metadata = {} } = {}) {
    if (!eventName) return { ok: false, reason: 'missing_event_name' };
    try {
        const { error } = await repos.telemetry.record({
            user_id: String(userId || 'default'),
            event_name: String(eventName),
            event_value: Number.isFinite(value) ? value : 0,
            metadata: metadata && typeof metadata === 'object' ? metadata : {},
        });
        if (error) throw error;
        return { ok: true };
    } catch (err) {
        console.error('⚠️ recordEvent failed (suppressed):', err.message);
        return { ok: false, reason: err.message };
    }
}

/**
 * Deterministic aggregation of recent events for a user — counts (summed
 * event_value) per event_name. No LLM. Used by the dashboard endpoint and, in a
 * later phase, by the profile learner.
 */
async function aggregateEvents(repos, { userId = 'default', sinceDays = 30, limit = 1000 } = {}) {
    try {
        const since = new Date(Date.now() - sinceDays * 86400000).toISOString();
        const rows = await repos.telemetry.recentEvents(userId, since, limit);
        const counts = {};
        for (const r of rows) counts[r.event_name] = (counts[r.event_name] || 0) + (r.event_value || 0);
        return { ok: true, counts, total: rows.length, events: rows };
    } catch (err) {
        return { ok: false, reason: err.message, counts: {}, total: 0, events: [] };
    }
}

function normalizeSnippet(text) {
    return String(text || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

/**
 * Closes the router feedback loop: turns repeated 👎 events into router-override
 * *proposals* a human can approve with one click (POST /router/keywords already
 * does the applying — this only does the detecting).
 *
 * `/feedback` links each 👎 to the intent that produced the reply via
 * `metadata.routedIntent` (server.js, routeTracker) whenever the routing
 * decision is still within its 10-minute TTL. This groups those rows by
 * (routedIntent, normalized message) and keeps only groups that recurred at
 * least `minOccurrences` times — a single bad reply is noise; the same message
 * getting mis-routed the same way repeatedly is a pattern worth a fix.
 *
 * Pure function over already-fetched rows (no db access) so it's unit-testable
 * without mocking Supabase — the caller is responsible for fetching
 * `event_name = 'feedback_down'` rows first.
 *
 * @param {Array<{metadata?: object, created_at?: string}>} rows
 * @param {{minOccurrences?: number}} [opts]
 * @returns {Array<{routedIntent:string, snippet:string, suggestedKeyword:string, count:number, correction:string|null, lastSeenAt:string|null}>}
 *   Sorted by occurrence count desc, then most-recent first.
 */
function computeMisroutePatterns(rows, { minOccurrences = 2 } = {}) {
    const groups = new Map();
    for (const row of rows || []) {
        const meta = row && row.metadata;
        if (!meta || !meta.routedIntent || !meta.snippet) continue;
        const normalized = normalizeSnippet(meta.snippet);
        if (!normalized) continue;
        const key = `${meta.routedIntent}::${normalized}`;
        const existing = groups.get(key);
        if (existing) {
            existing.count += 1;
            if (meta.correction && !existing.correction) existing.correction = meta.correction;
            if (row.created_at && (!existing.lastSeenAt || row.created_at > existing.lastSeenAt)) {
                existing.lastSeenAt = row.created_at;
            }
        } else {
            groups.set(key, {
                routedIntent: meta.routedIntent,
                snippet: meta.snippet,
                suggestedKeyword: normalized,
                count: 1,
                correction: meta.correction || null,
                lastSeenAt: row.created_at || null,
            });
        }
    }
    return Array.from(groups.values())
        .filter(g => g.count >= minOccurrences)
        .sort((a, b) => b.count - a.count || String(b.lastSeenAt).localeCompare(String(a.lastSeenAt)));
}

module.exports = { recordEvent, aggregateEvents, computeMisroutePatterns, SIGNAL_VALUE };
