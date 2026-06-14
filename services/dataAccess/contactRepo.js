'use strict';

// Contact repository — data-access seam for the `contacts` table (the
// policy-gated /contacts endpoints). Reads throw on error so the route returns
// 500; writes return the raw Supabase result.

const C = 'contacts';

function createContactRepo(supabase) {
    return {
        async listByName() {
            const { data, error } = await supabase.from(C).select('*').order('name', { ascending: true });
            if (error) throw error;
            return data || [];
        },
        async create(row) {
            return supabase.from(C).insert([row]).select().single();
        },
        async updateById(id, updates) {
            return supabase.from(C).update(updates).eq('id', id).select().single();
        },
        async removeById(id) {
            return supabase.from(C).delete().eq('id', id);
        },
    };
}

module.exports = { createContactRepo };
