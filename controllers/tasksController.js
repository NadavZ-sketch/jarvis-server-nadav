function createTasksController({ repos }) {
  const tasks = repos.tasks;
  return {
    async list(_req, res) {
      try {
        // Repo embeds subtasks and falls back to a plain select internally when
        // the relation isn't present on this environment.
        res.json({ tasks: await tasks.listWithSubtasks() });
      } catch (err) {
        console.error('GET /tasks error:', err.message);
        res.status(500).json({ tasks: [] });
      }
    },
    async create(req, res) {
      try {
        const {
          content, priority, category, project_id, kanban_column,
          eisenhower_quad, sprint_id, story_points, task_start_date, due_date,
          recurrence, tags,
        } = req.body;
        if (!content) return res.status(400).json({ error: 'content required' });
        const row = { content };
        if (priority && ['high', 'medium', 'low'].includes(priority)) row.priority = priority;
        if (category && ['work', 'personal', 'financial', 'project', 'general'].includes(category)) row.category = category;
        if (recurrence !== undefined)
          row.recurrence = ['daily', 'weekly', 'monthly'].includes(recurrence) ? recurrence : null;
        if (project_id      !== undefined) row.project_id      = project_id;
        if (kanban_column   !== undefined) row.kanban_column   = kanban_column;
        if (eisenhower_quad !== undefined) row.eisenhower_quad = eisenhower_quad;
        if (sprint_id       !== undefined) row.sprint_id       = sprint_id;
        if (story_points    !== undefined) row.story_points    = story_points;
        if (task_start_date !== undefined) row.task_start_date = task_start_date;
        if (due_date        !== undefined) row.due_date        = due_date;
        if (Array.isArray(tags))
          row.tags = [...new Set(
            tags.filter(t => typeof t === 'string' && t.trim())
                .map(t => t.trim().slice(0, 30))
          )].slice(0, 10);
        const { data, error } = await tasks.create(row);
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
          done, due_date, content, priority, category, project_id, kanban_column,
          eisenhower_quad, sprint_id, story_points, task_start_date, recurrence, tags,
        } = req.body;
        const updates = {};
        if (done     !== undefined) updates.done     = done;
        if (due_date !== undefined) updates.due_date = due_date;
        if (content  !== undefined) updates.content  = content;
        if (priority !== undefined && ['high', 'medium', 'low'].includes(priority))
          updates.priority = priority;
        if (category !== undefined && ['work', 'personal', 'financial', 'project', 'general'].includes(category))
          updates.category = category;
        if (recurrence !== undefined)
          updates.recurrence = ['daily', 'weekly', 'monthly'].includes(recurrence) ? recurrence : null;
        if (project_id      !== undefined) updates.project_id      = project_id;
        if (kanban_column   !== undefined) updates.kanban_column   = kanban_column;
        if (eisenhower_quad !== undefined) updates.eisenhower_quad = eisenhower_quad;
        if (sprint_id       !== undefined) updates.sprint_id       = sprint_id;
        if (story_points    !== undefined) updates.story_points    = story_points;
        if (task_start_date !== undefined) updates.task_start_date = task_start_date;
        if (Array.isArray(tags))
          updates.tags = [...new Set(
            tags.filter(t => typeof t === 'string' && t.trim())
                .map(t => t.trim().slice(0, 30))
          )].slice(0, 10);
        if (Object.keys(updates).length === 0) return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await tasks.update(req.params.id, updates);
        if (error) throw error;
        res.json({ task: data });
      } catch (err) {
        console.error('PUT /tasks/:id error:', err.message);
        res.status(500).json({ error: err.message });
      }
    },
    async remove(req, res) {
      try {
        const { error } = await tasks.deleteById(req.params.id);
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
