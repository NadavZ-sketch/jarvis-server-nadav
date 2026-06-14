'use strict';

// Reminder repository — deep head of the data-access seam for the `reminders`
// table. Absorbs the queries spread across agents/reminderAgent.js and
// controllers/remindersController.js.
//
// Read methods throw on a Supabase error (the reminder agent and controller
// both rely on that to surface "DB unavailable" rather than "no reminders").
// Write methods return the raw Supabase result so callers branch on .error.

const { sanitizeLike } = require('../../agents/utils');

const R = 'reminders';

function createReminderRepo(supabase) {
    return {
        // ── reads ──────────────────────────────────────────────────────────
        async listUpcoming() {
            const { data, error } = await supabase.from(R)
                .select('*')
                .eq('fired', false)
                .order('scheduled_time', { ascending: true });
            if (error) throw error;
            return data || [];
        },

        async nextUpcoming() {
            const { data, error } = await supabase.from(R)
                .select('id, text, scheduled_time')
                .eq('fired', false)
                .order('scheduled_time', { ascending: true })
                .limit(1);
            if (error) throw error;
            return data || [];
        },

        async listUnfired() {
            const { data, error } = await supabase.from(R).select('*').eq('fired', false);
            if (error) throw error;
            return data || [];
        },

        // created_at for reminders since a cutoff (analytics series).
        async createdSince(sinceISO, limit) {
            const { data } = await supabase.from(R)
                .select('created_at')
                .gte('created_at', sinceISO)
                .limit(limit);
            return data || [];
        },

        // All reminders, soonest first (calendar view — includes fired).
        async allOrdered() {
            const { data } = await supabase.from(R)
                .select('id, text, scheduled_time, fired')
                .order('scheduled_time', { ascending: true });
            return data || [];
        },

        // Unfired reminders within [fromISO, toISO], soonest first, limited.
        async upcomingUnfired(fromISO, toISO, limit) {
            const { data } = await supabase.from(R)
                .select('id, text, scheduled_time, fired')
                .eq('fired', false)
                .lte('scheduled_time', toISO)
                .gte('scheduled_time', fromISO)
                .order('scheduled_time', { ascending: true })
                .limit(limit);
            return data || [];
        },

        // Unfired reminders inside a day window [startISO, endISO) (briefing).
        async inWindow(startISO, endISO) {
            const { data } = await supabase.from(R)
                .select('text, scheduled_time')
                .eq('fired', false)
                .gte('scheduled_time', startISO)
                .lt('scheduled_time', endISO)
                .order('scheduled_time', { ascending: true });
            return data || [];
        },

        // Unfired reminders due before toISO (nudge); newest-first, limited.
        async dueBefore(toISO, limit) {
            const { data } = await supabase.from(R)
                .select('id, text, scheduled_time')
                .eq('fired', false)
                .lte('scheduled_time', toISO)
                .order('scheduled_time', { ascending: true })
                .limit(limit);
            return data || [];
        },

        // Unfired reminders inside [startISO, endISO) — used by GET /tasks/today,
        // which ignores query errors (returns []), so this read swallows too.
        async dueWindow(startISO, endISO) {
            const { data } = await supabase.from(R)
                .select('id, text, scheduled_time, fired, recurrence')
                .eq('fired', false)
                .gte('scheduled_time', startISO)
                .lt('scheduled_time', endISO)
                .order('scheduled_time', { ascending: true });
            return data || [];
        },

        // ── writes ─────────────────────────────────────────────────────────
        // Unfired reminders due at/before nowISO (cron firing); throws on error.
        async dueNow(nowISO) {
            const { data, error } = await supabase.from(R)
                .select('id, text, scheduled_time, recurrence')
                .eq('fired', false)
                .lte('scheduled_time', nowISO);
            if (error) throw error;
            return data || [];
        },

        // Recurring reminder → advance to its next occurrence, un-fired.
        async rescheduleRecurring(id, iso) {
            return supabase.from(R).update({ scheduled_time: iso, fired: false }).eq('id', id);
        },

        async markFired(id) {
            return supabase.from(R).update({ fired: true }).eq('id', id);
        },

        async add(row) {
            return supabase.from(R).insert([row]);
        },

        async create(row) {
            return supabase.from(R).insert([row]).select().single();
        },

        async update(id, fields) {
            return supabase.from(R).update(fields).eq('id', id).select().single();
        },

        async reschedule(id, iso) {
            return supabase.from(R).update({ scheduled_time: iso }).eq('id', id);
        },

        async deleteById(id) {
            return supabase.from(R).delete().eq('id', id);
        },

        async deleteMany(ids) {
            return supabase.from(R).delete().in('id', ids);
        },

        // Delete unfired reminders whose text matches; returns the deleted rows.
        async deleteByText(text) {
            const { data, error } = await supabase.from(R)
                .delete()
                .eq('fired', false)
                .ilike('text', `%${sanitizeLike(text)}%`)
                .select();
            if (error) throw error;
            return data || [];
        },
    };
}

module.exports = { createReminderRepo };
