function createRemindersController({ supabase, pinecone }) {
  return {
    async list(_req, res) {
      try {
        const { data, error } = await supabase
          .from('reminders')
          .select('id, text, scheduled_time, fired')
          .eq('fired', false)
          .order('scheduled_time', { ascending: true });
        if (error) throw error;
        res.json({ reminders: data || [] });
      } catch (err) {
        console.error('GET /reminders error:', err.message);
        res.status(500).json({ reminders: [] });
      }
    },
    async create(req, res) {
      try {
        const { text, scheduled_time, recurrence, project_id } = req.body;
        if (!text || !scheduled_time) return res.status(400).json({ error: 'text and scheduled_time required' });
        const row = { text, scheduled_time, fired: false };
        if (recurrence && ['daily', 'weekly', 'monthly'].includes(recurrence)) row.recurrence = recurrence;
        if (project_id) row.project_id = project_id;
        const { data, error } = await supabase.from('reminders').insert([row]).select().single();
        if (error) throw error;
        res.json({ reminder: data });
      } catch (err) {
        console.error('POST /reminders error:', err.message);
        res.status(500).json({ error: err.message });
      }
    },
    async update(req, res) {
      try {
        const { text, scheduled_time, recurrence, fired } = req.body;
        const updates = {};
        if (text !== undefined) updates.text = text;
        if (scheduled_time !== undefined) updates.scheduled_time = scheduled_time;
        if (fired !== undefined) updates.fired = !!fired;
        if (recurrence !== undefined) updates.recurrence = recurrence;
        if (Object.keys(updates).length === 0) return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await supabase.from('reminders').update(updates).eq('id', req.params.id).select().single();
        if (error) throw error;
        res.json({ reminder: data });
      } catch (err) {
        console.error('PUT /reminders/:id error:', err.message);
        res.status(500).json({ error: err.message });
      }
    },
    async remove(req, res) {
      try {
        const { error } = await supabase.from('reminders').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /reminders/:id error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
      }
    },
    async check(_req, res) {
      try {
        const now = new Date().toISOString();
        const { data, error } = await supabase.from('reminders').select('*').eq('fired', false);
        if (error) throw error;
        const dueReminders = (data || []).filter((r) => !r?.scheduled_time || r.scheduled_time <= now);
        if (dueReminders.length > 0) {
          const ids = dueReminders.map(r => r.id);
          await supabase.from('reminders').delete().in('id', ids);
          const enriched = await Promise.all(dueReminders.map(async (r) => {
            let context = '';
            if (pinecone?.isReady?.()) {
              try {
                const memories = await pinecone.searchMemories(r.text, 2);
                if (memories && memories.length > 0) context = ` (הקשר: ${memories[0].substring(0, 80)}...)`;
              } catch (_) {}
            }
            return { ...r, text: r.text + context };
          }));
          return res.json({ reminders: enriched });
        }
        res.json({ reminders: [] });
      } catch (err) {
        console.error('check-reminders error:', err.message);
        res.json({ reminders: [] });
      }
    },
  };
}

module.exports = { createRemindersController };
