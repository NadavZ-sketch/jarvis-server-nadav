'use strict';

// Task repository — the deep head of the data-access seam for the `tasks` table.
// Absorbs the query construction, sanitizeLike usage, and graceful-degradation
// (drop-unknown-column, fallback-without-relation) that were re-written inline
// across agents/taskAgent.js and controllers/tasksController.js.
//
// Convention: read methods return rows (or []); write methods return the raw
// Supabase {data,error} so callers branch on error exactly as before.

const { sanitizeLike } = require('../../agents/utils');

const T = 'tasks';

function createTaskRepo(supabase) {
    return {
        // ── reads ──────────────────────────────────────────────────────────
        async listAll() {
            const { data } = await supabase.from(T)
                .select('*')
                .order('due_date', { ascending: true, nullsFirst: false });
            return data || [];
        },

        // content + created_at for every task (profile learning).
        async allBasic() {
            const { data } = await supabase.from(T).select('content, created_at');
            return data || [];
        },

        // All dated tasks, soonest first (calendar view).
        async datedAll() {
            const { data } = await supabase.from(T)
                .select('id, content, due_date, done')
                .not('due_date', 'is', null)
                .order('due_date', { ascending: true });
            return data || [];
        },

        // Open dated tasks within [fromISO, toISO], soonest first, limited.
        async upcomingDated(fromISO, toISO, limit) {
            const { data } = await supabase.from(T)
                .select('id, content, due_date, done')
                .not('due_date', 'is', null)
                .eq('done', false)
                .lte('due_date', toISO)
                .gte('due_date', fromISO)
                .order('due_date', { ascending: true })
                .limit(limit);
            return data || [];
        },

        // Top open tasks by priority (briefing / nudge).
        async topByPriority(limit) {
            const { data } = await supabase.from(T)
                .select('id, content, priority')
                .eq('done', false)
                .order('priority', { ascending: false })
                .limit(limit);
            return data || [];
        },

        // tasks + embedded subtasks; falls back to a plain select when the
        // subtasks relation isn't present on this environment.
        async listWithSubtasks() {
            let { data, error } = await supabase.from(T)
                .select('*, subtasks(id, content, done, created_at)')
                .order('created_at', { ascending: false });
            if (error) {
                ({ data } = await supabase.from(T)
                    .select('*')
                    .order('created_at', { ascending: false }));
            }
            return data || [];
        },

        async listDueUpTo(dateISO) {
            const { data } = await supabase.from(T)
                .select('*')
                .eq('done', false)
                .lte('due_date', dateISO)
                .order('due_date', { ascending: true });
            return data || [];
        },

        async listOverdue(todayISO) {
            const { data } = await supabase.from(T)
                .select('*')
                .eq('done', false)
                .lt('due_date', todayISO);
            return data || [];
        },

        async recentTop(n) {
            const { data } = await supabase.from(T)
                .select('*')
                .order('created_at', { ascending: false })
                .limit(n);
            return data || [];
        },

        async firstOpen() {
            const { data } = await supabase.from(T)
                .select('content, due_date')
                .eq('done', false)
                .limit(1);
            return data || [];
        },

        async findByContent(q, { openOnly = false, columns = 'id, content' } = {}) {
            let query = supabase.from(T).select(columns).ilike('content', `%${sanitizeLike(q)}%`);
            if (openOnly) query = query.eq('done', false);
            const { data } = await query;
            return data || [];
        },

        // ── route-view reads (GET /tasks/today, POST /tasks/:id/suggest) ───────
        async listOpenByCreated() {
            const { data } = await supabase.from(T)
                .select('id, content, done, due_date, priority, created_at')
                .eq('done', false)
                .order('created_at', { ascending: false });
            return data || [];
        },

        async getBasic(id) {
            const { data } = await supabase.from(T).select('content, priority').eq('id', id).single();
            return data || null;
        },

        async openExcluding(id, limit) {
            const { data } = await supabase.from(T)
                .select('content')
                .eq('done', false)
                .neq('id', id)
                .limit(limit);
            return data || [];
        },

        // Open tasks (oldest first) for the proactive-nudge engine.
        async openForNudge(limit = 50) {
            const { data } = await supabase.from(T)
                .select('content, priority, due_date, created_at')
                .eq('done', false)
                .order('created_at', { ascending: true })
                .limit(limit);
            return data || [];
        },

        // ── writes ─────────────────────────────────────────────────────────
        // Insert that tolerates optional columns missing from the schema: on a
        // category/recurrence column error it retries with those dropped.
        async addGraceful(row) {
            const { error } = await supabase.from(T).insert([row]);
            if (error) {
                if (/column "(category|recurrence)"/.test(error.message || '')) {
                    const { category, recurrence, ...minimal } = row;
                    await supabase.from(T).insert([minimal]);
                } else {
                    console.error('taskRepo.addGraceful error:', error.message);
                }
            }
        },

        // Plain insert returning the created row (controllers want the row back).
        async create(row) {
            return supabase.from(T).insert([row]).select().single();
        },

        // Insert the next occurrence of a recurring task (caller checks .error).
        async insertNext(row) {
            return supabase.from(T).insert([row]);
        },

        async complete(id) {
            return supabase.from(T).update({ done: true }).eq('id', id);
        },

        async setCategory(id, category) {
            return supabase.from(T).update({ category }).eq('id', id);
        },

        async update(id, fields) {
            return supabase.from(T).update(fields).eq('id', id).select().single();
        },

        async deleteById(id) {
            return supabase.from(T).delete().eq('id', id);
        },
    };
}

module.exports = { createTaskRepo };
