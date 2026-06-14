'use strict';

// Conversation-summary repository — data-access seam for the `chat_summaries`
// table (rolling mid-term memory). The TTL cache and LLM summarisation stay in
// services/conversationSummary.js.

const S = 'chat_summaries';

function createSummaryRepo(supabase) {
    return {
        // Current summary string for a chat, '' when none (swallows errors).
        async get(chatId) {
            try {
                const { data } = await supabase.from(S).select('summary').eq('chat_id', chatId).maybeSingle();
                return data?.summary ?? '';
            } catch {
                return '';
            }
        },

        // { turns_covered, summary } for the chat, or {} when none.
        async getMeta(chatId) {
            const { data } = await supabase.from(S)
                .select('turns_covered, summary')
                .eq('chat_id', chatId)
                .maybeSingle();
            return data || {};
        },

        async upsert(row) {
            return supabase.from(S).upsert(row, { onConflict: 'chat_id' });
        },
    };
}

module.exports = { createSummaryRepo };
