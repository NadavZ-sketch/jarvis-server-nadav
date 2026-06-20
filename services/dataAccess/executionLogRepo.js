'use strict';

const T = 'execution_log';

function createExecutionLogRepo(supabase) {
    return {
        async recent(limit = 50) {
            const { data } = await supabase.from(T)
                .select('id,cmd,agent,model,duration_ms,status,error,created_at')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        async insert({ cmd, agent, model, duration_ms, status, error }) {
            await supabase.from(T).insert({
                cmd: String(cmd || '').slice(0, 300),
                agent: String(agent || '').slice(0, 80),
                model: String(model || '').slice(0, 80),
                duration_ms: Number.isFinite(duration_ms) ? duration_ms : 0,
                status,
                error: error ? String(error).slice(0, 500) : null,
            }).catch(() => {});
        },
    };
}

module.exports = { createExecutionLogRepo };
