'use strict';

// Habit repository — data-access seam over the `habits` and `habit_logs`
// tables. Absorbs the queries in agents/habitAgent.js (the streak math stays in
// the agent via computeStreak). sanitizeLike lives here now.

const { sanitizeLike } = require('../../agents/utils');

const H = 'habits';
const L = 'habit_logs';

function createHabitRepo(supabase) {
    return {
        // Active habits whose name matches the hint (returns [] when none).
        async findActiveByName(nameHint) {
            if (!nameHint) return [];
            const { data } = await supabase.from(H)
                .select('id, name, schedule')
                .eq('active', true)
                .ilike('name', `%${sanitizeLike(nameHint)}%`);
            return data || [];
        },

        async listActive() {
            const { data } = await supabase.from(H)
                .select('id, name, schedule')
                .eq('active', true)
                .order('created_at', { ascending: true });
            return data || [];
        },

        async add(row) {
            return supabase.from(H).insert([row]);
        },

        async deactivate(id) {
            return supabase.from(H).update({ active: false }).eq('id', id);
        },

        // Idempotent per-day log (UNIQUE habit_id,date).
        async logToday(habitId, date) {
            return supabase.from(L)
                .upsert([{ habit_id: habitId, date, done: true }], { onConflict: 'habit_id,date' });
        },

        // Completed-log dates for a habit, as a string array (for computeStreak).
        async doneDates(habitId) {
            const { data } = await supabase.from(L)
                .select('date')
                .eq('habit_id', habitId)
                .eq('done', true);
            return (data || []).map(l => l.date);
        },
    };
}

module.exports = { createHabitRepo };
