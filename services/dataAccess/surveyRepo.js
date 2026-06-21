'use strict';

// Survey repository — data-access seam for the `user_surveys` table behind the
// /survey-* endpoints. The cooldown/exclude/smart reads swallow errors (the
// endpoints proceed without filtering on failure); history/insights reads throw;
// insertGraceful tolerates the cooldown columns being absent on older schemas.

const U = 'user_surveys';

function createSurveyRepo(supabase) {
    return {
        // Cooldown: any completed survey since the cutoff.
        async recentCompleted(userName, sinceISO) {
            const { data } = await supabase.from(U)
                .select('id, completed_at')
                .eq('user_name', userName)
                .gte('completed_at', sinceISO)
                .limit(1);
            return data || [];
        },

        // Question ids answered within the exclude window.
        async recentQuestionIds(userName, sinceISO) {
            const { data } = await supabase.from(U)
                .select('question_ids')
                .eq('user_name', userName)
                .gte('completed_at', sinceISO)
                .limit(20);
            return data || [];
        },

        // Insert; retry without the cooldown columns if the migration is absent.
        async insertGraceful(row) {
            let { error } = await supabase.from(U).insert([row]);
            if (error && /completed_at|question_ids/i.test(error.message || '')) {
                const { completed_at, question_ids, ...minimal } = row;
                ({ error } = await supabase.from(U).insert([minimal]));
            }
            return { error };
        },

        async historyForUser(userName) {
            const { data, error } = await supabase.from(U)
                .select('id, created_at, summary, responses')
                .eq('user_name', userName)
                .order('created_at', { ascending: false })
                .limit(50);
            if (error) throw error;
            return data || [];
        },

        async responsesForUser(userName) {
            const { data, error } = await supabase.from(U)
                .select('responses, created_at')
                .eq('user_name', userName)
                .order('created_at', { ascending: false })
                .limit(50);
            if (error) throw error;
            return data || [];
        },

        // Smart-check / impact read by user_id (preserves the existing column).
        async recentResponsesById(userId, limit = 5) {
            const { data } = await supabase.from(U)
                .select('responses')
                .eq('user_id', userId)
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        async recentResponsesWithDateById(userId, limit = 20) {
            const { data } = await supabase.from(U)
                .select('responses, created_at')
                .eq('user_id', userId)
                .order('created_at', { ascending: false })
                .limit(limit);
            return data || [];
        },

        // Most recent survey timestamp for a user (control-center reminder).
        async lastForUser(userName) {
            const { data } = await supabase.from(U)
                .select('created_at')
                .eq('user_name', userName)
                .order('created_at', { ascending: false })
                .limit(1);
            return data || [];
        },

        // Export all survey rows (no user filter) for dashboard CSV export.
        async listAll() {
            const { data, error } = await supabase.from(U)
                .select('*')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        },
    };
}

module.exports = { createSurveyRepo };
