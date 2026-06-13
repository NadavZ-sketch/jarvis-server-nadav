const express = require('express');
const { createTasksController } = require('../controllers/tasksController');
const { createRepos } = require('../services/dataAccess');
const { callGemma4 } = require('../agents/models');

function createTasksRouter(deps) {
  const { supabase } = deps;
  // Controllers cross the data-access seam; the inline route handlers below
  // (today / suggest / subtasks) still query Supabase directly for now.
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createTasksController({ ...deps, repos });

  // ─── GET /tasks/today — tasks (overdue + due today) + reminders due today ──
  router.get('/today', async (_req, res) => {
    try {
      const now = new Date();
      const todayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
      const todayEnd   = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);

      const [tasksRes, remindersRes] = await Promise.all([
        supabase
          .from('tasks')
          .select('id, content, done, due_date, priority, created_at')
          .eq('done', false)
          .order('created_at', { ascending: false }),
        supabase
          .from('reminders')
          .select('id, text, scheduled_time, fired, recurrence')
          .eq('fired', false)
          .gte('scheduled_time', todayStart.toISOString())
          .lt('scheduled_time',  todayEnd.toISOString())
          .order('scheduled_time', { ascending: true }),
      ]);

      const taskItems = (tasksRes.data || []).map(t => {
        let section = 'no_due_date';
        if (t.due_date) {
          const due = new Date(t.due_date);
          section = due < todayStart ? 'overdue' : (due < todayEnd ? 'today' : null);
        }
        if (!section) return null; // future tasks — not shown in Today tab
        return {
          id:       `task-${t.id}`,
          sourceId: t.id,
          type:     'task',
          title:    t.content,
          time:     t.due_date,
          done:     t.done,
          priority: t.priority || 'medium',
          section,
        };
      }).filter(Boolean);

      const reminderItems = (remindersRes.data || []).map(r => ({
        id:         `reminder-${r.id}`,
        sourceId:   r.id,
        type:       'reminder',
        title:      r.text,
        time:       r.scheduled_time,
        done:       r.fired,
        recurrence: r.recurrence,
        section:    'reminder',
      }));

      res.json({ items: [...taskItems, ...reminderItems] });
    } catch (err) {
      console.error('GET /tasks/today error:', err.message);
      res.status(500).json({ items: [] });
    }
  });

  // ─── POST /tasks/:id/suggest — AI sub-task suggestions ────────────────────
  router.post('/:id/suggest', async (req, res) => {
    try {
      const [taskRes, otherRes] = await Promise.all([
        supabase.from('tasks').select('content, priority').eq('id', req.params.id).single(),
        supabase.from('tasks').select('content').eq('done', false).neq('id', req.params.id).limit(8),
      ]);

      if (!taskRes.data) return res.status(404).json({ suggestions: [] });

      const task       = taskRes.data;
      const otherTasks = (otherRes.data || []).map(t => `- ${t.content}`).join('\n');

      const prompt = `אתה עוזר ניהול משימות. קיבלת משימה ועליך להציע תת-משימות קונקרטיות שיעזרו להשלים אותה.

המשימה: "${task.content}" (עדיפות: ${task.priority || 'medium'})
משימות פתוחות אחרות:
${otherTasks || 'אין'}

החזר JSON בלבד בפורמט: {"suggestions":[{"text":"תיאור קצר","reason":"למה זה עוזר"}]}
3-4 הצעות בעברית. אל תוסיף שום טקסט לפני או אחרי ה-JSON.`;

      const raw = await callGemma4(prompt, false, 500);

      let suggestions = [];
      try {
        const start = raw.indexOf('{');
        const end   = raw.lastIndexOf('}');
        if (start !== -1 && end !== -1) {
          const parsed = JSON.parse(raw.substring(start, end + 1));
          suggestions = Array.isArray(parsed.suggestions) ? parsed.suggestions : [];
        }
      } catch (_) {}

      res.json({ suggestions });
    } catch (err) {
      console.error('POST /tasks/:id/suggest error:', err.message);
      res.status(500).json({ suggestions: [] });
    }
  });

  // ─── Subtasks — a one-level checklist under a parent task ─────────────────
  router.get('/:id/subtasks', async (req, res) => {
    try {
      const { data, error } = await supabase
        .from('subtasks')
        .select('*')
        .eq('parent_task_id', req.params.id)
        .order('created_at', { ascending: true });
      if (error) throw error;
      res.json({ subtasks: data || [] });
    } catch (err) {
      console.error('GET /tasks/:id/subtasks error:', err.message);
      res.status(500).json({ subtasks: [] });
    }
  });

  router.post('/:id/subtasks', async (req, res) => {
    try {
      const { content } = req.body;
      if (!content) return res.status(400).json({ error: 'content required' });
      const { data, error } = await supabase
        .from('subtasks')
        .insert([{ parent_task_id: req.params.id, content }])
        .select()
        .single();
      if (error) throw error;
      res.json({ subtask: data });
    } catch (err) {
      console.error('POST /tasks/:id/subtasks error:', err.message);
      res.status(500).json({ error: err.message });
    }
  });

  router.put('/:id/subtasks/:subId', async (req, res) => {
    try {
      const { content, done } = req.body;
      const updates = {};
      if (content !== undefined) updates.content = content;
      if (done    !== undefined) updates.done    = done;
      if (Object.keys(updates).length === 0) return res.status(400).json({ error: 'no fields to update' });
      const { data, error } = await supabase
        .from('subtasks')
        .update(updates)
        .eq('id', req.params.subId)
        .eq('parent_task_id', req.params.id)
        .select()
        .single();
      if (error) throw error;
      res.json({ subtask: data });
    } catch (err) {
      console.error('PUT /tasks/:id/subtasks/:subId error:', err.message);
      res.status(500).json({ error: err.message });
    }
  });

  router.delete('/:id/subtasks/:subId', async (req, res) => {
    try {
      const { error } = await supabase
        .from('subtasks')
        .delete()
        .eq('id', req.params.subId)
        .eq('parent_task_id', req.params.id);
      if (error) throw error;
      res.json({ ok: true });
    } catch (err) {
      console.error('DELETE /tasks/:id/subtasks/:subId error:', err.message);
      res.status(500).json({ ok: false, error: err.message });
    }
  });

  router.get('/',     controller.list);
  router.post('/',    controller.create);
  router.put('/:id',  controller.update);
  router.delete('/:id', controller.remove);

  return router;
}

module.exports = { createTasksRouter };
