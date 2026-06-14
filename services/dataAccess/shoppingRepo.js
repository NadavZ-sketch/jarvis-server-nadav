'use strict';

// Shopping repository — data-access seam for the `shopping_items` table.
// Absorbs the queries in agents/shoppingAgent.js (add / list-open / delete).
//
// Reads return rows; deleteMatching returns the deleted rows. Errors propagate
// to the agent's try/catch (Hebrew fallback). sanitizeLike lives here now.

const { sanitizeLike } = require('../../agents/utils');

const S = 'shopping_items';

function createShoppingRepo(supabase) {
    return {
        async add(item) {
            return supabase.from(S).insert([{ item }]);
        },

        async listOpen() {
            const { data } = await supabase.from(S)
                .select('*')
                .eq('done', false)
                .order('created_at', { ascending: true });
            return data || [];
        },

        // ── REST endpoint variants (GET/POST/PATCH/DELETE /shopping) ───────────
        async listAll() {
            const { data, error } = await supabase.from(S).select('*').order('created_at', { ascending: true });
            if (error) throw error;
            return data || [];
        },
        async create(item) {
            return supabase.from(S).insert([{ item }]).select().single();
        },
        async updateById(id, updates) {
            return supabase.from(S).update(updates).eq('id', id).select().single();
        },
        async removeById(id) {
            return supabase.from(S).delete().eq('id', id);
        },

        async deleteMatching(item) {
            const { data } = await supabase.from(S)
                .delete()
                .ilike('item', `%${sanitizeLike(item)}%`)
                .select();
            return data || [];
        },
    };
}

module.exports = { createShoppingRepo };
