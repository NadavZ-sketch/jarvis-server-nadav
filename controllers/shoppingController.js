function createShoppingController({ repos }) {
  const shopping = repos.shopping;
  return {
    async list(_req, res) {
      try {
        res.json({ items: await shopping.listAll() });
      } catch (err) {
        console.error('GET /shopping error:', err.message);
        res.status(500).json({ items: [] });
      }
    },
    async create(req, res) {
      try {
        const { item } = req.body;
        if (!item) return res.status(400).json({ error: 'item required' });
        const { data, error } = await shopping.create(item);
        if (error) throw error;
        res.json({ item: data });
      } catch (err) {
        console.error('POST /shopping error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
    async update(req, res) {
      try {
        const { done, item } = req.body;
        const updates = {};
        if (done !== undefined) updates.done = done;
        if (item !== undefined) updates.item = item;
        if (Object.keys(updates).length === 0)
          return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await shopping.updateById(req.params.id, updates);
        if (error) throw error;
        res.json({ item: data });
      } catch (err) {
        console.error('PATCH /shopping/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
    async remove(req, res) {
      try {
        const { error } = await shopping.removeById(req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /shopping/:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
      }
    },
  };
}

module.exports = { createShoppingController };
