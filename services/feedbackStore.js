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
async function recordEvent(supabase, { userId = 'default', eventName, value = 1, metadata = {} } = {}) {
    if (!eventName) return { ok: false, reason: 'missing_event_name' };
    try {
        const { error } = await supabase
            .from('smart_telemetry_events')
            .insert([{
                user_id: String(userId || 'default'),
                event_name: String(eventName),
                event_value: Number.isFinite(value) ? value : 0,
                metadata: metadata && typeof metadata === 'object' ? metadata : {},
            }]);
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
async function aggregateEvents(supabase, { userId = 'default', sinceDays = 30, limit = 1000 } = {}) {
    try {
        const since = new Date(Date.now() - sinceDays * 86400000).toISOString();
        let q = supabase
            .from('smart_telemetry_events')
            .select('event_name,event_value,metadata,created_at')
            .gte('created_at', since)
            .order('created_at', { ascending: false })
            .limit(limit);
        if (userId) q = q.eq('user_id', String(userId));
        const { data, error } = await q;
        if (error) throw error;
        const rows = data || [];
        const counts = {};
        for (const r of rows) counts[r.event_name] = (counts[r.event_name] || 0) + (r.event_value || 0);
        return { ok: true, counts, total: rows.length, events: rows };
    } catch (err) {
        return { ok: false, reason: err.message, counts: {}, total: 0, events: [] };
    }
}

module.exports = { recordEvent, aggregateEvents, SIGNAL_VALUE };
