'use strict';

// Agent-metrics repository — data-access seam for the `agent_metrics` table.
// In-memory buffering, batching, and aggregation stay in services/agentMetrics.

const M = 'agent_metrics';

function createMetricsRepo(supabase) {
    return {
        insertBatch(rows) {
            return supabase.from(M).insert(rows);
        },

        // Upsert per-agent health alerts (best-effort; table may not exist).
        upsertAlerts(rows) {
            return supabase.from('agent_metrics_alerts').upsert(rows, { onConflict: 'agent' });
        },

        async recentSince(sinceISO, limit) {
            const { data, error } = await supabase.from(M)
                .select('agent, ms, intent_mode, created_at')
                .gte('created_at', sinceISO)
                .order('created_at', { ascending: false })
                .limit(limit);
            if (error) throw error;
            return data || [];
        },
    };
}

module.exports = { createMetricsRepo };
