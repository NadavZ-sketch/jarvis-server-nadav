'use strict';

// Telemetry repository — data-access seam for the `smart_telemetry_events`
// table (the feedback loop's event log). recentEvents throws on error so
// aggregateEvents can return its safe empty shape; record returns the raw result.

const E = 'smart_telemetry_events';

function createTelemetryRepo(supabase) {
    return {
        record(row) {
            return supabase.from(E).insert([row]);
        },

        async recentEvents(userId, sinceISO, limit) {
            let q = supabase.from(E)
                .select('event_name,event_value,metadata,created_at')
                .gte('created_at', sinceISO)
                .order('created_at', { ascending: false })
                .limit(limit);
            if (userId) q = q.eq('user_id', String(userId));
            const { data, error } = await q;
            if (error) throw error;
            return data || [];
        },
    };
}

module.exports = { createTelemetryRepo };
