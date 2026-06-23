'use strict';

// User-prompt repository — data-access seam for the `user_prompts` table
// (promptAgent). Separate from promptLibraryRepo which covers the system
// `prompt_library` table used by the Dev Workshop tab.

const T = 'user_prompts';

function createUserPromptRepo(supabase) {
    return {
        async listRecent(limit = 10) {
            const { data, error } = await supabase.from(T)
                .select('id, title, category, created_at')
                .order('created_at', { ascending: false })
                .limit(limit);
            if (error) throw error;
            return data || [];
        },

        async add(row) {
            return supabase.from(T).insert([row]);
        },
    };
}

module.exports = { createUserPromptRepo };
