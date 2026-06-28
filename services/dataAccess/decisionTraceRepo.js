'use strict';

// Decision-trace repository — data-access seam for the `decision_trace` table.
// Records every /ask-jarvis routing decision (input, intent, candidates,
// ambiguous flag, route mode, agent, model, latency) for the control-center
// Decision Trace slice. insert() is fire-and-forget with error swallowing so
// tracing never blocks agent responses.

const T = 'decision_trace';

function createDecisionTraceRepo(supabase) {
    return {
        async recent(limit = 50) {
            const { data } = await supabase.from(T)
                .select('id,chat_id,input,intent,candidates,ambiguous,route_mode,agent,model,duration_ms,created_at')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        async insert({ chatId, input, intent, candidates, ambiguous, route_mode, agent, model, duration_ms }) {
            await supabase.from(T).insert({
                chat_id:     String(chatId || '').slice(0, 80),
                input:       String(input || '').slice(0, 300),
                intent:      String(intent || '').slice(0, 80),
                candidates:  JSON.stringify(Array.isArray(candidates) ? candidates : []),
                ambiguous:   !!ambiguous,
                route_mode:  String(route_mode || '').slice(0, 20),
                agent:       String(agent || '').slice(0, 80),
                model:       String(model || '').slice(0, 80),
                duration_ms: Number.isFinite(duration_ms) ? duration_ms : 0,
            }).catch(() => {});
        },
    };
}

module.exports = { createDecisionTraceRepo };
