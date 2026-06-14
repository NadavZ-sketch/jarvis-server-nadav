'use strict';

// Sprint repository — data-access seam for the `project_sprints` table (Scrum
// endpoints). All mutations are scoped to the parent project. `releaseTasks`
// detaches a sprint's open tasks on completion.

const SP = 'project_sprints';
const T = 'tasks';

function createSprintRepo(supabase) {
    return {
        // Sprints for a project, newest start first; throws on error.
        async listForProject(projectId) {
            const { data, error } = await supabase.from(SP)
                .select('*')
                .eq('project_id', projectId)
                .order('start_date', { ascending: false });
            if (error) throw error;
            return data || [];
        },

        async create(row) {
            return supabase.from(SP).insert([row]).select().single();
        },

        async updateScoped(sprintId, projectId, updates) {
            return supabase.from(SP).update(updates)
                .eq('id', sprintId)
                .eq('project_id', projectId)
                .select()
                .single();
        },

        async removeScoped(sprintId, projectId) {
            return supabase.from(SP).delete().eq('id', sprintId).eq('project_id', projectId);
        },

        // Other active sprints in the project (start guard); swallows errors.
        async activeOthers(projectId, sprintId) {
            const { data } = await supabase.from(SP)
                .select('id')
                .eq('project_id', projectId)
                .eq('status', 'active')
                .neq('id', sprintId);
            return data || [];
        },

        // Detach a sprint's still-open tasks (on sprint completion).
        async releaseTasks(sprintId) {
            return supabase.from(T).update({ sprint_id: null }).eq('sprint_id', sprintId).eq('done', false);
        },
    };
}

module.exports = { createSprintRepo };
