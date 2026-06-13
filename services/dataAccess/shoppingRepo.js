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
