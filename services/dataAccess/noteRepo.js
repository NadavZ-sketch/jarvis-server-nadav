'use strict';

// Note repository — data-access seam for the `notes` table. The notes queries
// use a title/content `.or(...)` search that the generic tableRepo can't
// express, so notes gets its own small deep repo.
//
// Reads return rows (or the inserted row); errors propagate to the agent's
// try/catch (which returns the Hebrew fallback).

const { sanitizeLike } = require('../../agents/utils');

const N = 'notes';

// "title.ilike.%q%,content.ilike.%q%" — matches either column.
function orFilter(q) {
    const safe = sanitizeLike(q);
    return `title.ilike.%${safe}%,content.ilike.%${safe}%`;
}

function createNoteRepo(supabase) {
    return {
        // Insert one note, returning the created row (or null).
        async add(row) {
            const { data } = await supabase.from(N).insert([row]).select().single();
            return data || null;
        },

        async listRecent(limit = 10) {
            const { data } = await supabase.from(N)
                .select('*')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        // ── REST endpoint variants (GET/PUT/DELETE /notes) ─────────────────────
        async listAll() {
            const { data, error } = await supabase.from(N).select('*').order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },
        async updateById(id, updates) {
            return supabase.from(N).update(updates).eq('id', id).select().single();
        },
        async removeById(id) {
            return supabase.from(N).delete().eq('id', id);
        },

        async search(q, limit = 5) {
            const { data } = await supabase.from(N).select('*').or(orFilter(q)).limit(limit);
            return data || [];
        },

        // Delete notes matching the query; returns the deleted rows.
        async deleteMatching(q) {
            const { data } = await supabase.from(N).delete().or(orFilter(q)).select();
            return data || [];
        },
    };
}

module.exports = { createNoteRepo };
