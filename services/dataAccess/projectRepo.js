'use strict';

// Project repository — data-access seam for project management. Spans
// `projects`, `project_milestones`, and the project-scoped views of `tasks` and
// `reminders`. The progress math, briefing formatting, and sprint/conflict logic
// stay in agents/projectAgent.js — this repo owns only the Supabase queries.

const P = 'projects';
const M = 'project_milestones';
const T = 'tasks';
const R = 'reminders';

function createProjectRepo(supabase) {
    return {
        // ── projects ─────────────────────────────────────────────────────────
        async searchByName(nameHint) {
            if (!nameHint) return [];
            const { data } = await supabase.from(P).select('*').ilike('name', `%${nameHint.trim()}%`).limit(5);
            return data || [];
        },
        async create(row) {
            return supabase.from(P).insert([row]).select().single();
        },
        async listNonArchived() {
            const { data } = await supabase.from(P).select('*')
                .not('status', 'eq', 'archived')
                .order('created_at', { ascending: false });
            return data || [];
        },
        async listActive() {
            const { data } = await supabase.from(P).select('*').eq('status', 'active');
            return data || [];
        },
        async listActiveOrPaused() {
            const { data } = await supabase.from(P).select('*')
                .in('status', ['active', 'paused'])
                .order('priority', { ascending: false });
            return data || [];
        },
        async update(id, updates) {
            return supabase.from(P).update(updates).eq('id', id);
        },
        async remove(id) {
            return supabase.from(P).delete().eq('id', id);
        },

        // ── progress inputs ────────────────────────────────────────────────────
        async taskDoneFlags(projectId) {
            const { data } = await supabase.from(T).select('done').eq('project_id', projectId);
            return data || [];
        },
        async milestoneCompletedFlags(projectId) {
            const { data } = await supabase.from(M).select('completed').eq('project_id', projectId);
            return data || [];
        },

        // ── milestones ───────────────────────────────────────────────────────
        async listMilestones(projectId) {
            const { data } = await supabase.from(M).select('*').eq('project_id', projectId).order('due_date');
            return data || [];
        },
        async addMilestone(row) {
            return supabase.from(M).insert([row]);
        },
        async findOpenMilestones(projectId, titleHint) {
            const { data } = await supabase.from(M)
                .select('id, title')
                .eq('project_id', projectId)
                .eq('completed', false)
                .ilike('title', `%${titleHint || ''}%`);
            return data || [];
        },
        async completeMilestone(id) {
            return supabase.from(M)
                .update({ completed: true, completed_at: new Date().toISOString() })
                .eq('id', id);
        },
        async upcomingMilestones(fromISO, toISO) {
            const { data } = await supabase.from(M)
                .select('title, due_date, project_id')
                .not('due_date', 'is', null)
                .eq('completed', false)
                .gte('due_date', fromISO)
                .lte('due_date', toISO);
            return data || [];
        },

        // ── tasks (project-scoped) ─────────────────────────────────────────────
        async listTasks(projectId) {
            const { data } = await supabase.from(T)
                .select('content,done,due_date')
                .eq('project_id', projectId)
                .order('created_at');
            return data || [];
        },
        async addTask(row) {
            return supabase.from(T).insert([row]);
        },
        async sprintBacklog(projectId) {
            const { data } = await supabase.from(T)
                .select('id, content, story_points, priority')
                .eq('project_id', projectId)
                .is('sprint_id', null)
                .eq('done', false);
            return data || [];
        },
        async upcomingTasks(fromISO, toISO) {
            const { data } = await supabase.from(T)
                .select('content, due_date, project_id')
                .not('due_date', 'is', null)
                .eq('done', false)
                .gte('due_date', fromISO)
                .lte('due_date', toISO);
            return data || [];
        },

        // ── reminders (project-linked) ─────────────────────────────────────────
        async addReminder(row) {
            return supabase.from(R).insert([row]);
        },
    };
}

module.exports = { createProjectRepo };
