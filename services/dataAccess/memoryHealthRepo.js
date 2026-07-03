'use strict';

// Thin data-access layer over memory_health_findings. Business logic (when to
// upsert vs. leave a resolved finding alone, content-hash comparisons) lives
// in services/memoryHealthCheck.js — this repo only talks to Supabase.

const H = 'memory_health_findings';

function createMemoryHealthRepo(supabase) {
    return {
        async listFindings({ status = 'pending', type } = {}) {
            let query = supabase.from(H).select('*');
            if (status) query = query.eq('status', status);
            if (type) query = query.eq('type', type);
            const { data, error } = await query.order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        async findExisting(type, memoryId, relatedMemoryId) {
            let query = supabase.from(H).select('*').eq('type', type).eq('memory_id', memoryId);
            query = relatedMemoryId
                ? query.eq('related_memory_id', relatedMemoryId)
                : query.is('related_memory_id', null);
            const { data, error } = await query.limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async insertFinding(row) {
            const { data, error } = await supabase.from(H).insert([row]).select('*').limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async updateFinding(id, patch) {
            const { data, error } = await supabase.from(H).update(patch).eq('id', id).select('*').limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async getById(id) {
            const { data, error } = await supabase.from(H).select('*').eq('id', id).limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },

        async setStatus(id, status) {
            const patch = { status };
            if (status !== 'pending') patch.resolved_at = new Date().toISOString();
            const { data, error } = await supabase.from(H).update(patch).eq('id', id).select('*').limit(1);
            if (error) throw error;
            return (data && data[0]) || null;
        },
    };
}

module.exports = { createMemoryHealthRepo };
