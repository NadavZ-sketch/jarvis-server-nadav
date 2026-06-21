'use strict';

// Test-cases repository — CRUD for the `test_cases` table.
// Test cases are recorded from real conversations (source='recorded') and
// replayed via /test-cases/:id/run to check for regressions.

const T = 'test_cases';

function createTestCasesRepo(supabase) {
    return {
        async listAll() {
            const { data, error } = await supabase.from(T)
                .select('*')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        async create({ name, turns, source = 'recorded', recorded_at }) {
            const { data, error } = await supabase.from(T)
                .insert({
                    name: String(name).slice(0, 120),
                    turns: JSON.stringify(turns),
                    source,
                    recorded_at: recorded_at || new Date().toISOString(),
                    last_status: 'pending',
                })
                .select()
                .single();
            if (error) throw error;
            return data;
        },

        async markResult(id, status, diffArray) {
            const { error } = await supabase.from(T)
                .update({
                    last_status:   status,
                    last_run:      new Date().toISOString(),
                    last_run_diff: JSON.stringify(diffArray),
                })
                .eq('id', id);
            if (error) throw error;
        },

        async byId(id) {
            const { data, error } = await supabase.from(T).select('*').eq('id', id).single();
            if (error) throw error;
            return data;
        },
    };
}

module.exports = { createTestCasesRepo };
