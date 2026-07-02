function createNotesController({ repos }) {
  const notes = repos.notes;
  return {
    async list(_req, res) {
      try {
        res.json({ notes: await notes.listAll() });
      } catch (err) {
        console.error('GET /notes error:', err.message);
        res.status(500).json({ notes: [] });
      }
    },
    async create(req, res) {
      try {
        const { title, content } = req.body;
        if (!content) return res.status(400).json({ error: 'content required' });
        const data = await notes.add({ title: title || '', content });
        res.json({ note: data });
      } catch (err) {
        console.error('POST /notes error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
    async update(req, res) {
      try {
        const { title, content } = req.body;
        const updates = {};
        if (title   !== undefined) updates.title   = title;
        if (content !== undefined) updates.content = content;
        if (Object.keys(updates).length === 0)
          return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await notes.updateById(req.params.id, updates);
        if (error) throw error;
        res.json({ note: data });
      } catch (err) {
        console.error('PUT /notes/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
    async remove(req, res) {
      try {
        const { error } = await notes.removeById(req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /notes/:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
      }
    },
  };
}

module.exports = { createNotesController };
