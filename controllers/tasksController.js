function createTasksController({ supabase }) {
  return {
    async list(_req, res) {
      try {
        const { data, error } = await supabase.from('tasks').select('*').order('created_at', { ascending: false });
        if (error) throw error;
        res.json({ tasks: data || [] });
      } catch (err) {
        console.error('GET /tasks error:', err.message);
        res.status(500).json({ tasks: [] });
      }
    },
    async create(req, res) {
      try {
        const {
          content, priority, project_id, kanban_column,
          eisenhower_quad, sprint_id, story_points, task_start_date, due_date,
        } = req.body;
        if (!content) return res.status(400).json({ error: 'content required' });
        const row = { content };
        if (priority && ['high', 'medium', 'low'].includes(priority)) row.priority = priority;
        if (project_id      !== undefined) row.project_id      = project_id;
        if (kanban_column   !== undefined) row.kanban_column   = kanban_column;
        if (eisenhower_quad !== undefined) row.eisenhower_quad = eisenhower_quad;
        if (sprint_id       !== undefined) row.sprint_id       = sprint_id;
        if (story_points    !== undefined) row.story_points    = story_points;
        if (task_start_date !== undefined) row.task_start_date = task_start_date;
        if (due_date        !== undefined) row.due_date        = due_date;
        const { data, error } = await supabase.from('tasks').insert([row]).select().single();
        if (error) throw error;
        res.json({ task: data });
      } catch (err) {
        console.error('POST /tasks error:', err.message);
        res.status(500).json({ error: err.message });
      }
    },
    async update(req, res) {
      try {
        const {
          done, due_date, content, priority, project_id, kanban_column,
          eisenhower_quad, sprint_id, story_points, task_start_date,
        } = req.body;
        const updates = {};
        if (done     !== undefined) updates.done     = done;
        if (due_date !== undefined) updates.due_date = due_date;
        if (content  !== undefined) updates.content  = content;
        if (priority !== undefined && ['high', 'medium', 'low'].includes(priority))
          updates.priority = priority;
        if (project_id      !== undefined) updates.project_id      = project_id;
        if (kanban_column   !== undefined) updates.kanban_column   = kanban_column;
        if (eisenhower_quad !== undefined) updates.eisenhower_quad = eisenhower_quad;
        if (sprint_id       !== undefined) updates.sprint_id       = sprint_id;
        if (story_points    !== undefined) updates.story_points    = story_points;
        if (task_start_date !== undefined) updates.task_start_date = task_start_date;
        if (Object.keys(updates).length === 0) return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await supabase.from('tasks').update(updates).eq('id', req.params.id).select().single();
        if (error) throw error;
        res.json({ task: data });
      } catch (err) {
        console.error('PUT /tasks/:id error:', err.message);
        res.status(500).json({ error: err.message });
      }
    },
    async remove(req, res) {
      try {
        const { error } = await supabase.from('tasks').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /tasks/:id error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
      }
    },
  };
}

module.exports = { createTasksController };
