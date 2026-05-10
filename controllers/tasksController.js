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
        const { content } = req.body;
        if (!content) return res.status(400).json({ error: 'content required' });
        const { data, error } = await supabase.from('tasks').insert([{ content }]).select().single();
        if (error) throw error;
        res.json({ task: data });
      } catch (err) {
        console.error('POST /tasks error:', err.message);
        res.status(500).json({ error: err.message });
      }
    },
    async update(req, res) {
      try {
        const { done, due_date, content } = req.body;
        const updates = {};
        if (done !== undefined) updates.done = done;
        if (due_date !== undefined) updates.due_date = due_date;
        if (content !== undefined) updates.content = content;
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
