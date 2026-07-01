const { runE2EAgent, buildClaudePrompt, countsBySeverity, computeScore } = require('../agents/e2eAgent');

function createE2EController({ repos, supabase, cacheInvalidate }) {
  return {
    async getSchedule(_req, res) {
      try {
        const rows = await repos.profile.latest();
        const prefs = rows[0]?.preferences || {};
        res.json({ schedule: prefs['e2e-schedule'] ?? null });
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    },

    // PUT /e2e-schedule — write e2e run schedule to user profile preferences
    async putSchedule(req, res) {
      try {
        const { schedule } = req.body || {};
        if (!schedule || typeof schedule !== 'object' || Array.isArray(schedule))
          return res.status(400).json({ error: 'schedule object required' });
        const rows = await repos.profile.latest();
        const existing = rows[0] || {};
        const prefs = { ...(existing.preferences || {}), 'e2e-schedule': schedule };
        if (existing.id) {
          await repos.profile.update(existing.id, { preferences: prefs });
        } else {
          await repos.profile.create({ preferences: prefs });
        }
        res.json({ ok: true, schedule });
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    },

    async listReports(_req, res) {
      try {
        const data = await repos.e2e.listRecent(2000);

        // Group by run_id and compute summary per run
        const byRun = new Map();
        for (const row of data || []) {
          if (!byRun.has(row.run_id)) {
            byRun.set(row.run_id, {
              run_id: row.run_id,
              kind: row.kind || 'e2e',
              created_at: row.created_at,
              count: 0,
              critical: 0, high: 0, medium: 0, low: 0,
              measured: 0, evaluated: 0,
              done: 0,
            });
          }
          const g = byRun.get(row.run_id);
          if (row.kind) g.kind = row.kind;
          if (row.created_at > g.created_at) g.created_at = row.created_at;
          if (row.status === 'done') { g.done++; continue; }
          g.count++;
          if (g[row.severity] !== undefined) g[row.severity]++;
          // 'source' may be absent on rows from before the migration → treat as measured.
          if (row.source === 'evaluated') g.evaluated++; else g.measured++;
        }
        const reports = Array.from(byRun.values())
          .map(r => {
            const w = { critical: 25, high: 10, medium: 4, low: 1 };
            const penalty = r.critical * w.critical + r.high * w.high + r.medium * w.medium + r.low * w.low;
            r.score = Math.max(0, 100 - penalty);
            return r;
          })
          .sort((a, b) => b.created_at.localeCompare(a.created_at));
        res.json({ reports });
      } catch (err) {
        console.error('GET /e2e-reports error:', err.message);
        res.status(500).json({ reports: [], error: 'Internal server error' });
      }
    },

    async getReport(req, res) {
      try {
        const findings = await repos.e2e.byRun(req.params.runId);

        const counts = countsBySeverity(findings);
        const score  = computeScore(findings);
        const claudePrompt = buildClaudePrompt({ runId: req.params.runId, findings, score, counts });
        res.json({
          run_id:  req.params.runId,
          kind:    findings[0]?.kind || 'e2e',
          findings,
          counts,
          score,
          claudePrompt,
        });
      } catch (err) {
        console.error('GET /e2e-reports/:id error:', err.message);
        res.status(500).json({ findings: [], error: 'Internal server error' });
      }
    },

    async deleteReport(req, res) {
      try {
        const { error } = await repos.e2e.deleteRun(req.params.runId);
        if (error) throw error;
        cacheInvalidate('chatHistory'); // not strictly needed but cheap
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /e2e-reports/:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
      }
    },

    // POST /e2e-reports/:runId/prompt — generate Claude prompt for selected findings
    async reportPrompt(req, res) {
      try {
        const { fingerprints } = req.body || {};
        if (!Array.isArray(fingerprints) || !fingerprints.length) {
          return res.status(400).json({ error: 'fingerprints array required' });
        }
        const findings = await repos.e2e.byRunAndFingerprints(req.params.runId, fingerprints);
        const counts   = countsBySeverity(findings);
        const score    = computeScore(findings);
        const claudePrompt = buildClaudePrompt({ runId: req.params.runId, findings, score, counts });
        res.json({ claudePrompt });
      } catch (err) {
        console.error('POST /e2e-reports/:id/prompt error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    // POST /e2e-reports/:runId/mark-done — mark specific findings as done
    async markDone(req, res) {
      try {
        const { fingerprints } = req.body || {};
        if (!Array.isArray(fingerprints) || !fingerprints.length) {
          return res.status(400).json({ error: 'fingerprints array required' });
        }
        const { error } = await repos.e2e.markDone(req.params.runId, fingerprints);
        if (error) throw error;
        res.json({ ok: true, updated: fingerprints.length });
      } catch (err) {
        console.error('POST /e2e-reports/:id/mark-done error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
      }
    },

    async trigger(_req, res) {
      try {
        // Fire-and-forget so the HTTP response is fast — the agent persists
        // its report when it finishes, which the next /control-center/events
        // poll will surface as a new badge.
        setImmediate(() => {
          try { runE2EAgent('הרץ סקירת קצה', supabase, false, {}); }
          catch (e) { console.error('e2e trigger run error:', e.message); }
        });
        res.json({ triggered: true, startedAt: new Date().toISOString() });
      } catch (err) {
        console.error('❌ /e2e/trigger:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
  };
}

module.exports = { createE2EController };
