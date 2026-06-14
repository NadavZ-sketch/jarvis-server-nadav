'use strict';

// Subtask repository — data-access seam for the `subtasks` table (a one-level
// checklist under a parent task). All operations are scoped to the parent.

const S = 'subtasks';

function createSubtaskRepo(supabase) {
    return {
        // Throws on error so the route returns 500 (matches the inline handler).
        async listForParent(parentId) {
            const { data, error } = await supabase.from(S)
                .select('*')
                .eq('parent_task_id', parentId)
                .order('created_at', { ascending: true });
            if (error) throw error;
            return data || [];
        },

        async add(parentId, content) {
            return supabase.from(S).insert([{ parent_task_id: parentId, content }]).select().single();
        },

        async updateScoped(subId, parentId, updates) {
            return supabase.from(S).update(updates)
                .eq('id', subId)
                .eq('parent_task_id', parentId)
                .select()
                .single();
        },

        async removeScoped(subId, parentId) {
            return supabase.from(S).delete().eq('id', subId).eq('parent_task_id', parentId);
        },
    };
}

module.exports = { createSubtaskRepo };
