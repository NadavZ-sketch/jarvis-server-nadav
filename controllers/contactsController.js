function createContactsController({ repos }) {
  const contacts = repos.contacts;
  return {
    async list(_req, res) {
      try {
        res.json({ contacts: await contacts.listByName() });
      } catch (err) {
        console.error('GET /contacts error:', err.message);
        res.status(500).json({ contacts: [] });
      }
    },
    async create(req, res) {
      try {
        const { name, phone, email } = req.body;
        if (!name) return res.status(400).json({ error: 'name required' });
        const row = { name };
        if (phone) row.phone = phone;
        if (email) row.email = email;
        const { data, error } = await contacts.create(row);
        if (error) throw error;
        res.json({ contact: data });
      } catch (err) {
        console.error('POST /contacts error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
    async update(req, res) {
      try {
        const { name, phone, email } = req.body;
        const updates = {};
        if (name  !== undefined) updates.name  = name;
        if (phone !== undefined) updates.phone = phone;
        if (email !== undefined) updates.email = email;
        if (Object.keys(updates).length === 0)
          return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await contacts.updateById(req.params.id, updates);
        if (error) throw error;
        res.json({ contact: data });
      } catch (err) {
        console.error('PUT /contacts/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
    async remove(req, res) {
      try {
        const { error } = await contacts.removeById(req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /contacts/:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
      }
    },
  };
}

module.exports = { createContactsController };
