const { callGemma4 } = require('../agents/models');
const { buildProjectsBriefing } = require('../agents/projectAgent');

// Short-lived caches for the two LLM-backed endpoints below — same behavior
// as when this lived inline in server.js (per-process, no TTL sweep needed).
const _methodRecCache = new Map(); // key: name::description, value: {data, ts}
const _projectInsightsCache = new Map(); // key: `${projectId}:${methodology}`, value: {text, ts}

function createProjectsController({ repos }) {
  return {
    async list(_req, res) {
      try {
        const projects = await repos.projects.listAll();

        // Enrich each project with aggregate task/milestone counts + progress.
        // Single-user app: 3 queries total (projects + tasks + milestones), no N+1.
        const ids = projects.map(p => p.id);
        if (ids.length > 0) {
          const { tasks, milestones } = await repos.projects.countsForProjects(ids);

          const stats = {}; // projectId -> { open, total, done, mTotal, mDone }
          for (const id of ids) stats[id] = { open: 0, total: 0, done: 0, mTotal: 0, mDone: 0 };
          for (const t of tasks || []) {
            const s = stats[t.project_id];
            if (!s) continue;
            s.total++;
            if (t.done) s.done++; else s.open++;
          }
          for (const m of milestones || []) {
            const s = stats[m.project_id];
            if (!s) continue;
            s.mTotal++;
            if (m.completed) s.mDone++;
          }
          for (const p of projects) {
            const s = stats[p.id] || { open: 0, total: 0, done: 0, mTotal: 0, mDone: 0 };
            const totalItems = s.total + s.mTotal;
            const doneItems = s.done + s.mDone;
            p.open_tasks = s.open;
            p.total_tasks = s.total;
            p.done_count = doneItems;
            p.milestones_total = s.mTotal;
            p.milestones_done = s.mDone;
            p.progress = totalItems > 0 ? doneItems / totalItems : 0;
          }
        }

        res.json({ projects });
      } catch (err) {
        console.error('GET /projects error:', err.message);
        res.json({ projects: [] });
      }
    },

    async create(req, res) {
      try {
        const { name, description, status, priority, start_date, due_date, color, methodology, method_config } = req.body;
        if (!name) return res.status(400).json({ error: 'name is required' });
        const validStatuses = ['active', 'planning', 'paused', 'completed', 'archived'];
        const safeStatus = validStatuses.includes(status) ? status : 'active';
        const { data, error } = await repos.projects.create({
          name, description,
          status: safeStatus,
          priority: priority || 'medium',
          start_date, due_date,
          color: color || '#6366f1',
          methodology: methodology || 'kanban',
          method_config: method_config || {},
        });
        if (error) throw error;
        res.json({ project: data });
      } catch (err) {
        console.error('POST /projects error:', err.message, err.details || '');
        res.status(500).json({ error: err.message || 'Internal server error' });
      }
    },

    async briefing(req, res) {
      try {
        const userName = req.query.userName || 'נדב';
        const result = await buildProjectsBriefing(repos.projects, userName);
        res.json(result);
      } catch (err) {
        console.error('GET /projects/briefing error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async getById(req, res) {
      try {
        const project = await repos.projects.getById(req.params.id);
        if (!project) return res.status(404).json({ error: 'Not found' });

        const { milestones, tasks, reminders, notes, sprints } = await repos.projects.detail(project.id);

        res.json({ project, milestones, tasks, reminders, notes, sprints });
      } catch (err) {
        console.error('GET /projects/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async update(req, res) {
      try {
        const updates = { ...req.body, updated_at: new Date().toISOString() };
        delete updates.id;
        const { data, error } = await repos.projects.update(req.params.id, updates);
        if (error) throw error;
        res.json({ project: data });
      } catch (err) {
        console.error('PUT /projects/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async remove(req, res) {
      try {
        const { error } = await repos.projects.remove(req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /projects/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async listMilestones(req, res) {
      try {
        const data = await repos.projects.listMilestones(req.params.id);
        res.json({ milestones: data });
      } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async createMilestone(req, res) {
      try {
        const { title, due_date } = req.body;
        if (!title) return res.status(400).json({ error: 'title is required' });
        const { data, error } = await repos.projects.createMilestone({ project_id: req.params.id, title, due_date: due_date || null });
        if (error) throw error;
        res.json({ milestone: data });
      } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async updateMilestone(req, res) {
      try {
        const updates = { ...req.body };
        if (updates.completed && !updates.completed_at) updates.completed_at = new Date().toISOString();
        if (!updates.completed) updates.completed_at = null;
        const { data, error } = await repos.projects.updateMilestoneScoped(req.params.mId, req.params.id, updates);
        if (error) throw error;
        res.json({ milestone: data });
      } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async removeMilestone(req, res) {
      try {
        const { error } = await repos.projects.removeMilestoneScoped(req.params.mId, req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async listSprints(req, res) {
      try {
        const data = await repos.sprints.listForProject(req.params.id);
        res.json({ sprints: data });
      } catch (err) {
        console.error('GET /projects/:id/sprints error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async createSprint(req, res) {
      try {
        const { name, goal, start_date, end_date, capacity_points } = req.body;
        if (!name || !start_date || !end_date) {
          return res.status(400).json({ error: 'name, start_date ו-end_date נדרשים' });
        }
        const { data, error } = await repos.sprints.create({
          project_id: req.params.id, name, goal, start_date, end_date, capacity_points: capacity_points || 0,
        });
        if (error) throw error;
        res.json({ sprint: data });
      } catch (err) {
        console.error('POST /projects/:id/sprints error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async updateSprint(req, res) {
      try {
        const updates = { ...req.body, updated_at: new Date().toISOString() };
        delete updates.id;
        delete updates.project_id;
        const { data, error } = await repos.sprints.updateScoped(req.params.sId, req.params.id, updates);
        if (error) throw error;
        res.json({ sprint: data });
      } catch (err) {
        console.error('PUT /projects/:id/sprints/:sId error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async removeSprint(req, res) {
      try {
        const { error } = await repos.sprints.removeScoped(req.params.sId, req.params.id);
        if (error) throw error;
        res.json({ ok: true });
      } catch (err) {
        console.error('DELETE /projects/:id/sprints/:sId error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async startSprint(req, res) {
      try {
        const existing = await repos.sprints.activeOthers(req.params.id, req.params.sId);
        if (existing && existing.length > 0) {
          return res.status(409).json({ error: 'כבר קיים ספרינט פעיל לפרויקט זה' });
        }
        const { data, error } = await repos.sprints.updateScoped(req.params.sId, req.params.id, { status: 'active', updated_at: new Date().toISOString() });
        if (error) throw error;
        res.json({ sprint: data });
      } catch (err) {
        if (err.status === 409) return res.status(409).json({ error: err.message });
        console.error('POST .../start error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async completeSprint(req, res) {
      try {
        await repos.sprints.releaseTasks(req.params.sId);
        const { data, error } = await repos.sprints.updateScoped(req.params.sId, req.params.id, { status: 'completed', updated_at: new Date().toISOString() });
        if (error) throw error;
        res.json({ sprint: data });
      } catch (err) {
        console.error('POST .../complete error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async recommendMethodology(req, res) {
      try {
        const { name = '', description = '' } = req.body || {};
        const key = `${name}::${description}`.slice(0, 300);
        const cached = _methodRecCache.get(key);
        if (cached && (Date.now() - cached.ts) < 30 * 60 * 1000) {
          return res.json({ ...cached.data, cached: true });
        }
        const prompt = `הפרויקט: ${name}. ${description}. איזו שיטת עבודה תמליץ: kanban/scrum/eisenhower/gantt? הסבר בקצרה. החזר JSON: {"methodology":"...","reason":"..."} בלבד.`;
        const raw = await callGemma4(prompt, false, 150);
        const match = raw.match(/\{[\s\S]*\}/);
        let data = { methodology: '', reason: '' };
        if (match) {
          try {
            const p = JSON.parse(match[0]);
            data = {
              methodology: (p.methodology || '').toLowerCase(),
              reason: p.reason || '',
            };
          } catch (_) {}
        }
        _methodRecCache.set(key, { data, ts: Date.now() });
        res.json({ ...data, cached: false });
      } catch (err) {
        console.error('POST /projects/recommend-methodology error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async aiInsights(req, res) {
      try {
        const { methodology } = req.body || {};
        const cacheKey = `${req.params.id}:${methodology || 'general'}`;
        const cached = _projectInsightsCache.get(cacheKey);
        if (cached && (Date.now() - cached.ts) < 30 * 60 * 1000) {
          return res.json({ insights: cached.text, cached: true });
        }

        const project = await repos.projects.getById(req.params.id);
        if (!project) return res.status(404).json({ error: 'פרויקט לא נמצא' });

        const { tasks, milestones, sprints } = await repos.projects.insightsData(req.params.id);

        const openTasks = (tasks || []).filter(t => !t.done).length;
        const doneTasks = (tasks || []).filter(t => t.done).length;
        const activeSprint = (sprints || []).find(s => s.status === 'active');

        let contextLines = [
          `פרויקט: "${project.name}". מתודולוגיה: ${methodology || project.methodology || 'kanban'}.`,
          `משימות פתוחות: ${openTasks}, הושלמו: ${doneTasks}.`,
        ];
        if (methodology === 'scrum' || project.methodology === 'scrum') {
          if (activeSprint) {
            const sprintDone = (tasks || []).filter(t => t.done && t.sprint_id === activeSprint.id).reduce((s, t) => s + (t.story_points || 1), 0);
            const sprintTotal = (tasks || []).filter(t => t.sprint_id === activeSprint.id).reduce((s, t) => s + (t.story_points || 1), 0);
            contextLines.push(`ספרינט פעיל: "${activeSprint.name}", נקודות שהושלמו: ${sprintDone}/${sprintTotal}.`);
          } else {
            contextLines.push('אין ספרינט פעיל כרגע.');
          }
        } else if (methodology === 'kanban' || project.methodology === 'kanban') {
          const cols = { todo: 0, in_progress: 0, review: 0, done: 0 };
          (tasks || []).forEach(t => { if (cols[t.kanban_column] !== undefined) cols[t.kanban_column]++; });
          contextLines.push(`עמודות Kanban: לביצוע=${cols.todo}, בתהליך=${cols.in_progress}, בבדיקה=${cols.review}, הושלם=${cols.done}.`);
        } else if (methodology === 'eisenhower' || project.methodology === 'eisenhower') {
          const quads = { q1: 0, q2: 0, q3: 0, q4: 0, null: 0 };
          (tasks || []).forEach(t => { const k = t.eisenhower_quad || 'null'; if (quads[k] !== undefined) quads[k]++; });
          contextLines.push(`מטריצה: Q1(דחוף+חשוב)=${quads.q1}, Q2(חשוב)=${quads.q2}, Q3(דחוף)=${quads.q3}, Q4(שאר)=${quads.q4}, לא מסווג=${quads.null}.`);
        }

        const prompt = contextLines.join('\n') + '\nתן 3 תובנות קצרות בעברית על מצב הפרויקט ומה כדאי לשפר. החזר JSON: {"insights":["...","...","..."]}';
        const raw = await callGemma4(prompt, false, 300);
        const match = raw.match(/\{[\s\S]*\}/);
        let insights = [];
        if (match) {
          try { insights = JSON.parse(match[0]).insights || []; } catch (_) {}
        }
        if (!insights.length) insights = [raw.trim()];

        _projectInsightsCache.set(cacheKey, { text: insights, ts: Date.now() });
        res.json({ insights, cached: false });
      } catch (err) {
        console.error('POST /projects/:id/ai-insights error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
  };
}

module.exports = { createProjectsController };
