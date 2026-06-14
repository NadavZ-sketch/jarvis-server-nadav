'use strict';

// Memory repository — deep head of the data-access seam for the `memories`
// table. Absorbs the queries spread across agents/memoryAgent.js (save / recall
// / delete / update / dedup / passive extraction). Pinecone semantic search and
// the cache-invalidation hook stay in the agent — this repo owns only Supabase.
//
// Reads return rows (or content strings); deleteByContent throws on error to
// match the agent's existing "DB unavailable" handling. Writes return the raw
// Supabase result.

const { sanitizeLike } = require('../../agents/utils');

const M = 'memories';

function createMemoryRepo(supabase) {
    return {
        // Substring match on content; default returns id+content, one row.
        async findByContent(text, { columns = 'id, content', limit = 1 } = {}) {
            const { data } = await supabase.from(M)
                .select(columns)
                .ilike('content', `%${sanitizeLike(text)}%`)
                .limit(limit);
            return data || [];
        },

        // All stored memory contents (recall fallback when Pinecone is absent).
        async allContents() {
            const { data } = await supabase.from(M).select('content');
            return (data || []).map(m => m.content);
        },

        // Full rows for the /memories CRUD endpoints.
        async listAll() {
            const { data, error } = await supabase.from(M)
                .select('id, content, scope, created_at')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        // Insert returning the full row (endpoints want it echoed back).
        async create(row) {
            const { data, error } = await supabase.from(M)
                .insert([row])
                .select('id, content, scope, created_at')
                .limit(1);
            if (error) throw error;
            return data || [];
        },

        async updateById(id, patch) {
            const { data, error } = await supabase.from(M)
                .update(patch)
                .eq('id', id)
                .select('id, content, scope, created_at')
                .limit(1);
            if (error) throw error;
            return data || [];
        },

        async removeById(id) {
            const { data, error } = await supabase.from(M)
                .delete()
                .eq('id', id)
                .select('id, content');
            if (error) throw error;
            return data || [];
        },

        // Insert one memory, returning [{ id }] so the caller can embed it.
        async insert(row) {
            const { data } = await supabase.from(M).insert([row]).select('id').limit(1);
            return data || [];
        },

        async update(id, content) {
            return supabase.from(M).update({ content }).eq('id', id);
        },

        // Delete memories whose content matches; returns the deleted rows.
        async deleteByContent(text) {
            const { data, error } = await supabase.from(M)
                .delete()
                .ilike('content', `%${sanitizeLike(text)}%`)
                .select('id, content');
            if (error) throw error;
            return data || [];
        },
    };
}

module.exports = { createMemoryRepo };
