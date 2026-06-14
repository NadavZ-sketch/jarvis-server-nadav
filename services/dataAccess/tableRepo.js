'use strict';

// Generic table repository — the shallow tail of the hybrid data-access seam.
// Hot tables (tasks, reminders, memories) get their own deep repo with named
// domain methods; the simple CRUD tables (notes, shopping, …) ride this helper.
//
// Reads swallow the {data,error} envelope and return rows (or []), matching the
// `const { data } = await supabase.from(...)…; data || []` pattern callers used
// inline. Writes return the raw Supabase result so callers can branch on error.

const { sanitizeLike } = require('../../agents/utils');

function createTableRepo(supabase, table) {
    return {
        async all({ order } = {}) {
            let q = supabase.from(table).select('*');
            if (order) q = q.order(order.column, { ascending: order.ascending !== false });
            const { data } = await q;
            return data || [];
        },
        async findLike(column, q) {
            const { data } = await supabase.from(table).select('*').ilike(column, `%${sanitizeLike(q)}%`);
            return data || [];
        },
        // Arbitrary column selection with optional ascending order (swallows errors).
        async select(columns = '*', order = null) {
            let q = supabase.from(table).select(columns);
            if (order) q = q.order(order, { ascending: true });
            const { data } = await q;
            return data || [];
        },
        async insert(row) {
            return supabase.from(table).insert([row]).select().single();
        },
        async update(id, fields) {
            return supabase.from(table).update(fields).eq('id', id).select().single();
        },
        async remove(id) {
            return supabase.from(table).delete().eq('id', id);
        },
    };
}

module.exports = { createTableRepo };
