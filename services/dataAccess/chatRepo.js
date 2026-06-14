'use strict';

// Chat-history repository — data-access seam for the `chat_history` table's core
// read/write helpers (loadChatHistory, saveChatMessage, searchFullHistory, and
// the GET /chat-history controller). Token budgeting, caching, and the in-memory
// fallback stay in their callers.

const H = 'chat_history';

function createChatRepo(supabase) {
    return {
        // Most-recent-first tail for a chat; throws on error (callers fall back).
        async recentTail(chatId, { limit = 60, columns = 'role, text' } = {}) {
            const { data, error } = await supabase.from(H)
                .select(columns)
                .eq('chat_id', chatId)
                .order('created_at', { ascending: false })
                .limit(limit);
            if (error) throw error;
            return data || [];
        },

        async add(role, text, chatId) {
            return supabase.from(H).insert([{ role, text, chat_id: chatId }]);
        },

        // True total message count for a chat; throws on error.
        async countForChat(chatId) {
            const { count, error } = await supabase.from(H)
                .select('id', { count: 'exact', head: true })
                .eq('chat_id', chatId);
            if (error) throw error;
            return typeof count === 'number' ? count : null;
        },

        // Recent messages across all chats for full-history keyword search.
        async recentForSearch(limit = 200) {
            const { data } = await supabase.from(H)
                .select('role, text, created_at')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },
    };
}

module.exports = { createChatRepo };
