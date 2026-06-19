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

        // Recent memory rows, newest first (proposal/context builder).
        async recentByCreated(limit) {
            const { data } = await supabase.from(M)
                .select('content')
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        // Full rows for the /memories CRUD endpoints.
        // Falls back progressively if columns are missing in PostgREST schema cache.
        async listAll() {
            const { data, error } = await supabase.from(M)
                .select('id, content, scope, created_at')
                .order('created_at', { ascending: false });
            if (!error) return data || [];
            // created_at or scope may not exist — try without scope
            const { data: data2, error: err2 } = await supabase.from(M)
                .select('id, content, created_at')
                .order('created_at', { ascending: false });
            if (!err2) return data2 || [];
            // Last resort: minimal columns only, order by id
            const { data: data3, error: err3 } = await supabase.from(M)
                .select('id, content')
                .order('id', { ascending: false });
            if (err3) throw err3;
            return data3 || [];
        },

        // Insert returning the full row (endpoints want it echoed back).
        // Falls back to without scope if the column doesn't exist yet.
        async create(row) {
            const { data, error } = await supabase.from(M)
                .insert([row])
                .select('id, content, scope, created_at')
                .limit(1);
            if (!error) return data || [];
            if (error.message?.includes('scope') || error.code === '42703') {
                const { scope: _s, ...rowWithoutScope } = row;
                const { data: d2, error: err2 } = await supabase.from(M)
                    .insert([rowWithoutScope])
                    .select('id, content, created_at')
                    .limit(1);
                if (err2) throw err2;
                return d2 || [];
            }
            throw error;
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

        // All memories of a given scope, newest first; throws on error.
        async findByScope(scope, limit = 500) {
            const { data, error } = await supabase.from(M)
                .select('id, content, scope, created_at')
                .eq('scope', scope)
                .order('created_at', { ascending: false })
                .limit(limit);
            if (error) throw error;
            return data || [];
        },

        // Expired memories of a scope (older than cutoff); throws on error.
        async expiredByScope(scope, cutoffISO, limit = 500) {
            const { data, error } = await supabase.from(M)
                .select('id, content')
                .eq('scope', scope)
                .lt('created_at', cutoffISO)
                .limit(limit);
            if (error) throw error;
            return data || [];
        },

        async deleteMany(ids) {
            return supabase.from(M).delete().in('id', ids);
        },

        // Insert one memory, returning [{ id }] so the caller can embed it.
        // Falls back to insert without scope if the scope column doesn't exist.
        async insert(row) {
            const { data, error } = await supabase.from(M).insert([row]).select('id').limit(1);
            if (!error) return data || [];
            if (error.message?.includes('scope') || error.code === '42703') {
                const { scope: _s, ...rowWithoutScope } = row;
                const { data: d2 } = await supabase.from(M).insert([rowWithoutScope]).select('id').limit(1);
                return d2 || [];
            }
            throw error;
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
