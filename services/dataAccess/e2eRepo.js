'use strict';

// E2E-report repository — data-access seam for the `e2e_reports` table behind
// the /e2e-reports endpoints and the control-center bug context. Endpoint reads
// throw on error (handlers map to 500); the best-effort context reads swallow.

const T = 'e2e_reports';

function createE2eRepo(supabase) {
    return {
        async listRecent(limit = 2000) {
            const { data, error } = await supabase.from(T)
                .select('*')
                .order('created_at', { ascending: false })
                .limit(limit);
            if (error) throw error;
            return data || [];
        },

        async byRun(runId) {
            const { data, error } = await supabase.from(T)
                .select('*')
                .eq('run_id', runId)
                .order('severity', { ascending: true });
            if (error) throw error;
            return data || [];
        },

        async byRunAndFingerprints(runId, fingerprints) {
            const { data, error } = await supabase.from(T)
                .select('*')
                .eq('run_id', runId)
                .in('fingerprint', fingerprints);
            if (error) throw error;
            return data || [];
        },

        deleteRun(runId) {
            return supabase.from(T).delete().eq('run_id', runId);
        },

        markDone(runId, fingerprints) {
            return supabase.from(T).update({ status: 'done' }).eq('run_id', runId).in('fingerprint', fingerprints);
        },

        // Best-effort dashboard reads (callers ignore errors → []).
        async recentScores(limit = 5) {
            const { data } = await supabase.from(T)
                .select('run_id, score, critical, high, created_at')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        // Chunked insert with column-stripping retry for older schemas.
        // Throws only after both insert attempts fail (caller decides how to surface).
        async insertChunked(rows) {
            const insert = async (rs) => {
                for (let i = 0; i < rs.length; i += 50) {
                    const { error } = await supabase.from(T).insert(rs.slice(i, i + 50));
                    if (error) throw new Error(error.message || 'insert failed');
                }
            };
            try {
                await insert(rows);
            } catch (err) {
                if (/kind|source|column/i.test(err.message || '')) {
                    const stripped = rows.map(({ kind: _k, source: _s, ...r }) => r);
                    await insert(stripped);
                } else {
                    throw err;
                }
            }
        },

        async recentFailures(limit = 3) {
            const { data } = await supabase.from(T)
                .select('summary, created_at')
                .eq('status', 'fail')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },
    };
}

module.exports = { createE2eRepo };
