const { callGemma4 } = require('../agents/models');
const { extractJSON } = require('../agents/utils');
const pinecone = require('../services/pineconeMemory');
const obsidianSync = require('../services/obsidianSync');
const memoryContext = require('../services/memoryContext');
// Referenced (not destructured) so jest.spyOn(memoryAgent, ...) in tests can
// intercept calls — a destructured reference would bypass the spy.
const memoryAgent = require('../agents/memoryAgent');

const REBUILD_EXTRACT_PROMPT = `אתה מנתח שיחה ומחלץ עובדות אישיות חשובות לשמירה.

הודעת המשתמש: "{message}"
תגובת העוזר: "{answer}"

חלץ עד 3 פריטי מידע בעלי ערך לזיכרון ארוך טווח.
סווג: [fact] עובדה יציבה (משפחה, עבודה, גיל, מגורים), [pref] העדפה (מה אוהב, שגרה)
החזר JSON בלבד: { "memories": [ { "type": "fact|pref", "content": "[tag] תוכן בעברית" } ] }
רק מידע אישי ספציפי. אם אין — { "memories": [] }`;

const REBUILD_SKIP_RE = /מזג האוויר|תחזית|חדשות|כותרות|ספורט|תוצאות|מניות|שלום|היי|בוקר טוב/i;

function createMemoriesController({ repos }) {
  return {
    async list(req, res) {
      try {
        const { q } = req.query;
        if (q && pinecone.isReady()) {
          const hits = await pinecone.searchMemories(q, 20);
          if (hits) return res.json({ memories: hits.map(content => ({ content })) });
        }
        const data = await repos.memories.listAll();
        console.info(`[GET /memories] returning ${data.length} memories`);
        res.json({ memories: data });
      } catch (err) {
        console.error('GET /memories error:', err.message, err.code);
        res.json({ memories: [] });
      }
    },

    async create(req, res) {
      try {
        const { content, scope = 'long_term' } = req.body;
        if (!content || typeof content !== 'string' || !content.trim()) {
          return res.status(400).json({ error: 'content is required' });
        }
        const data = await repos.memories.create({ content: content.trim(), scope });
        const row = data?.[0];
        if (row?.id) {
          pinecone.upsertMemory(row.id, row.content).catch(() => {});
          obsidianSync.dbToVault('memories', row);
        }
        memoryContext.invalidateCache();
        res.json({ memory: row });
      } catch (err) {
        console.error('POST /memories error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async pending(req, res) {
      try {
        const data = await repos.memories.listByStatus('pending', 50);
        res.json({ memories: data });
      } catch (err) {
        console.error('GET /memories/pending error:', err.message);
        res.json({ memories: [] });
      }
    },

    async approve(req, res) {
      try {
        const row = await repos.memories.setStatus(req.params.id, 'approved');
        if (!row) return res.status(404).json({ error: 'Memory not found or status column missing' });
        if (row.content) {
          pinecone.upsertMemory(row.id, row.content).catch(() => {});
        }
        memoryContext.invalidateCache();
        res.json({ ok: true, memory: row });
      } catch (err) {
        console.error('POST /memories/:id/approve error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async update(req, res) {
      try {
        const { id } = req.params;
        const { content, scope } = req.body;
        if (!content || typeof content !== 'string' || !content.trim()) {
          return res.status(400).json({ error: 'content is required' });
        }
        const patch = { content: content.trim() };
        if (scope) patch.scope = scope;
        const data = await repos.memories.updateById(id, patch);
        if (!data || data.length === 0) return res.status(404).json({ error: 'Memory not found' });
        pinecone.upsertMemory(data[0].id, data[0].content).catch(() => {});
        obsidianSync.dbToVault('memories', data[0]);
        memoryContext.invalidateCache();
        res.json({ memory: data[0] });
      } catch (err) {
        console.error('PUT /memories/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async remove(req, res) {
      try {
        const { id } = req.params;
        const data = await repos.memories.removeById(id);
        if (!data || data.length === 0) return res.status(404).json({ error: 'Memory not found' });
        await pinecone.deleteMemory(id);
        obsidianSync.removeFromVault('memories', data[0]);
        memoryContext.invalidateCache();
        res.json({ deleted: true, memory: data[0] });
      } catch (err) {
        console.error('DELETE /memories/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    // Rebuild memories by re-running extraction over recent chat history
    async rebuildFromChat(_req, res) {
      try {
        const rows = await repos.chat.recentForSearch(400);
        rows.reverse();

        const pairs = [];
        for (let i = 0; i < rows.length - 1; i++) {
          if (rows[i].role === 'user' && rows[i + 1]?.role === 'assistant') {
            pairs.push({ user: rows[i].text, assistant: rows[i + 1].text });
            i++;
          }
        }

        const toProcess = pairs
          .filter(p => p.user && p.user.length >= 25 && !REBUILD_SKIP_RE.test(p.user))
          .slice(-60);

        const existing = await repos.memories.allContents().catch(() => []);
        const seen = new Set(existing.map(c => c.toLowerCase().trim()));

        let saved = 0;
        for (const pair of toProcess) {
          try {
            const prompt = REBUILD_EXTRACT_PROMPT
              .replace('{message}', pair.user.slice(0, 300))
              .replace('{answer}', (pair.assistant || '').slice(0, 150));
            const aiText = await callGemma4([{ role: 'user', content: prompt }], false, 300);
            const parsed = extractJSON(aiText);
            if (!parsed) continue;
            for (const item of (parsed.memories || [])) {
              const content = (item.content || '').trim();
              if (!content || item.type === 'context') continue;
              if (seen.has(content.toLowerCase().trim())) continue;
              seen.add(content.toLowerCase().trim());
              const inserted = await repos.memories.insert({ content, scope: 'long_term' }).catch(() => []);
              if (inserted?.[0]?.id) pinecone.upsertMemory(inserted[0].id, content).catch(() => {});
              saved++;
            }
          } catch { /* skip failed extractions */ }
        }

        memoryContext.invalidateCache();
        res.json({ ok: true, saved, processed: toProcess.length });
      } catch (err) {
        console.error('POST /memories/rebuild-from-chat error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
      }
    },

    // Recover memories from Pinecone back into Supabase (for schema migration recovery)
    async recoverFromPinecone(_req, res) {
      try {
        if (!pinecone.isReady()) return res.json({ ok: false, reason: 'Pinecone not configured' });
        const pineconeRecords = await pinecone.listAll();
        console.info(`[recover] Pinecone returned ${pineconeRecords.length} records with text`);
        if (!pineconeRecords.length) return res.json({ ok: true, recovered: 0, total: 0 });
        const existing = await repos.memories.listAll().catch(() => []);
        const existingContents = new Set(existing.map(m => m.content?.trim()));
        let recovered = 0;
        for (const rec of pineconeRecords) {
          if (!rec.content || existingContents.has(rec.content.trim())) continue;
          await repos.memories.insert({ content: rec.content }).catch(e =>
            console.warn('[recover] insert failed:', e.message));
          recovered++;
        }
        memoryContext.invalidateCache();
        res.json({ ok: true, recovered, total: pineconeRecords.length });
      } catch (err) {
        console.error('POST /memories/recover-from-pinecone error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
      }
    },

    async confirm(req, res) {
      const { chatId, action } = req.body;
      if (!chatId) return res.status(400).json({ error: 'chatId required' });

      const pending = memoryAgent.getPendingMemory(chatId);
      if (!pending) return res.status(404).json({ error: 'no pending memory for this chat' });

      memoryAgent.clearPendingMemory(chatId);
      if (action === 'discard') return res.json({ ok: true });

      try {
        const result = await memoryContext.savePendingData(pending, repos);
        res.json({ ok: true, saved: result.content });
      } catch (err) {
        console.error('❌ memories/confirm error:', err.message);
        res.status(500).json({ error: 'שגיאה בשמירת הזיכרון' });
      }
    },
  };
}

module.exports = { createMemoriesController };
