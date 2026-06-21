'use strict';

// Prompt-library repository — CRUD for the `prompt_library` table.
// Stores versioned system/user prompts editable from the Dev Workshop tab.

const T = 'prompt_library';

function createPromptLibraryRepo(supabase) {
    return {
        async listAll() {
            const { data, error } = await supabase.from(T)
                .select('*')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        async create({ name, content }) {
            const { data, error } = await supabase.from(T)
                .insert({ name: String(name).slice(0, 120), content: String(content) })
                .select()
                .single();
            if (error) throw error;
            return data;
        },

        async update(id, { name, content, is_active }) {
            const patch = {};
            if (name !== undefined)      patch.name      = String(name).slice(0, 120);
            if (content !== undefined)   patch.content   = String(content);
            if (is_active !== undefined) patch.is_active = Boolean(is_active);
            if (Object.keys(patch).length === 0) throw new Error('nothing to update');

            if (patch.content) {
                const { data: cur } = await supabase.from(T).select('version').eq('id', id).single();
                patch.version = ((cur?.version) || 1) + 1;
            }

            const { data, error } = await supabase.from(T)
                .update(patch)
                .eq('id', id)
                .select()
                .single();
            if (error) throw error;
            return data;
        },

        async remove(id) {
            const { error } = await supabase.from(T).delete().eq('id', id);
            if (error) throw error;
        },
    };
}

module.exports = { createPromptLibraryRepo };
