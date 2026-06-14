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

        deleteForChat(chatId) {
            return supabase.from(H).delete().eq('chat_id', chatId);
        },

        // Count of user messages since a cutoff (analytics; swallows errors → 0).
        async countUserSince(sinceISO) {
            const { count } = await supabase.from(H)
                .select('id', { count: 'exact', head: true })
                .gte('created_at', sinceISO)
                .eq('role', 'user');
            return count || 0;
        },

        // Count of messages since a cutoff on the legacy `timestamp` column.
        async countSinceTimestamp(sinceISO) {
            const { count } = await supabase.from(H)
                .select('id', { count: 'exact', head: true })
                .gte('timestamp', sinceISO);
            return count || 0;
        },

        // role + created_at for messages since a cutoff (analytics series).
        async rolesSince(sinceISO, limit) {
            const { data } = await supabase.from(H)
                .select('role, created_at')
                .gte('created_at', sinceISO)
                .limit(limit);
            return data || [];
        },

        // Recent user-message contents since a cutoff (proposal context).
        async recentUserContent(sinceISO, limit) {
            const { data } = await supabase.from(H)
                .select('content')
                .eq('role', 'user')
                .gte('created_at', sinceISO)
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
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
