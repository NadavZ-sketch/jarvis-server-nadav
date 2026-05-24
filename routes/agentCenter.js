'use strict';

const express = require('express');
const path = require('path');
const { getAgentRegistry, setAgentStatus, setAgentRisk, isProtectedAgent } = require('../services/agentRegistryService');

function detectCategory(text) {
  const t = text.toLowerCase();
  if (/פרומפט|prompt|הנחיה|system prompt/.test(t)) return 'prompt';
  if (/הרשאה|כלי|tool|permission|api/.test(t)) return 'permissions';
  if (/חיבור|סוכן אחר|handoff|העבר|coordinate/.test(t)) return 'connections';
  if (/בטיחות|סיכון|אישור|security|guard|approve/.test(t)) return 'safety';
  return 'behavior';
}

const CATEGORY_LABELS = {
  prompt: 'שינוי פרומפט',
  permissions: 'שינוי הרשאות',
  connections: 'שינוי חיבורים',
  safety: 'אבטחה ובטיחות',
  behavior: 'שינוי התנהגות',
};

function detectRiskSignals(text, agent) {
  const t = text.toLowerCase();
  const signals = [];
  if (/עצמאי|אוטונומי|autonomous|ללא אישור/.test(t)) signals.push('autonomy_increase');
  if (/הרשאה|כלי|tool|permission/.test(t)) signals.push('permissions_change');
  if (/מחיקה|delete|מחק|drop/.test(t)) signals.push('destructive_action');
  if (/חיצוני|webhook|api|http|external/.test(t)) signals.push('external_access');
  if (agent && agent.risk === 'high') signals.push('high_risk_agent');
  return signals;
}

const RISK_SIGNAL_LABELS = {
  autonomy_increase: 'הגדלת אוטונומיה',
  permissions_change: 'שינוי הרשאות',
  destructive_action: 'פעולה הרסנית',
  external_access: 'גישה חיצונית',
  high_risk_agent: 'סוכן בסיכון גבוה',
};

// P2: Agent health score 0-100. Higher is healthier.
function _computeHealthScore(agent) {
  let score = 100;
  if (agent.status === 'disabled') return 0;
  const m = agent.metrics;
  if (m) {
    if (m.avgMs !== null) {
      if (m.avgMs > 3000) score -= 30;
      else if (m.avgMs > 1500) score -= 15;
      else if (m.avgMs > 800) score -= 5;
    }
    // Never called = unknown; slight penalty for observer agents that never fired
    if (m.count === 0 && agent.mode !== 'guard') score -= 10;
    // Stale: last call over 7 days ago
    if (m.lastCalledAt) {
      const daysSince = (Date.now() - new Date(m.lastCalledAt).getTime()) / 86400000;
      if (daysSince > 14) score -= 20;
      else if (daysSince > 7) score -= 10;
    }
  }
  if (agent.risk === 'high') score -= 5;
  return Math.max(0, Math.min(100, score));
}

function createAgentCenterRouter({ callGemma4, agentMetrics }) {
  const router = express.Router();

  router.get('/', (_req, res) => {
    // Dashboard uses inline scripts/styles — override strict global CSP for this route only
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self' 'unsafe-inline' unpkg.com cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' unpkg.com cdn.jsdelivr.net; connect-src 'self'; img-src 'self' data:",
    );
    res.sendFile(path.join(__dirname, '..', 'progress-map.html'),
      err => { if (err && !res.headersSent) res.status(404).send('progress-map.html not found'); });
  });

  router.get('/agents', async (_req, res) => {
    try {
      const agents = getAgentRegistry();
      // Attach live metrics + health scores if available.
      if (agentMetrics) {
        const snap = await agentMetrics.snapshot().catch(() => ({ latency: [], intent: { fast: 0, llm: 0 } }));
        const byAgent = new Map(snap.latency.map(r => [r.agent, r]));
        for (const a of agents) {
          const m = byAgent.get(a.id);
          if (m) {
            a.metrics = { avgMs: m.avgMs, count: m.count, lastCalledAt: m.lastCalledAt || null };
          } else {
            a.metrics = { avgMs: null, count: 0, lastCalledAt: null };
          }
          a.healthScore = _computeHealthScore(a);
        }
      }
      res.json({ agents });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  // Enable/disable an agent. Toggles status if no explicit value sent.
  router.post('/agents/:id/toggle', (req, res) => {
    try {
      const agentId = req.params.id;
      const registry = getAgentRegistry();
      const current = registry.find(a => a.id === agentId);
      if (!current) return res.status(404).json({ error: 'agent not found' });
      const explicit = req.body && typeof req.body.status === 'string' ? req.body.status : null;
      const nextStatus = explicit
        ? explicit
        : (current.status === 'disabled' ? 'active' : 'disabled');
      const override = setAgentStatus(agentId, nextStatus);
      res.json({ id: agentId, status: nextStatus, updatedAt: override.updatedAt });
    } catch (err) {
      res.status(400).json({ error: err.message });
    }
  });

  // Set an agent's risk level (low|medium|high). Persisted as an override.
  router.post('/agents/:id/risk', (req, res) => {
    try {
      const agentId = req.params.id;
      const registry = getAgentRegistry();
      if (!registry.find(a => a.id === agentId)) return res.status(404).json({ error: 'agent not found' });
      const riskLevel = req.body && req.body.riskLevel;
      const override = setAgentRisk(agentId, riskLevel);
      res.json({ id: agentId, riskLevel, updatedAt: override.updatedAt });
    } catch (err) {
      res.status(400).json({ error: err.message });
    }
  });

  // Live per-agent latency + intent-classification metrics.
  router.get('/metrics', async (_req, res) => {
    try {
      const snap = agentMetrics ? await agentMetrics.snapshot() : { latency: [], intent: { fast: 0, llm: 0 } };
      res.json(snap);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  // P2: Natural-language metrics query. POST { question } → { answer }
  router.post('/metrics/query', async (req, res) => {
    try {
      const { question } = req.body || {};
      if (!question) return res.status(400).json({ error: 'question required' });
      const snap = agentMetrics ? await agentMetrics.snapshot().catch(() => ({ latency: [], intent: { fast: 0, llm: 0 } })) : { latency: [], intent: { fast: 0, llm: 0 } };
      const metricsText = snap.latency.length
        ? snap.latency.map(r => `${r.agent}: ${r.avgMs}ms avg, ${r.count} calls${r.lastCalledAt ? ', last: ' + r.lastCalledAt : ''}`).join('\n')
        : 'אין נתוני מדדים זמינים';
      const prompt = `נתוני מדדי סוכנים (24 שעות אחרונות):
${metricsText}
סיווג intent: fast=${snap.intent.fast}, llm=${snap.intent.llm}

שאלה: "${question}"

ענה בעברית בקצרה ובצורה ברורה על בסיס הנתונים בלבד.`;
      const answer = await callGemma4([
        { role: 'system', content: 'אתה מנתח מדדי ביצועים של סוכני AI. ענה בעברית.' },
        { role: 'user', content: prompt },
      ], false, 300).catch(() => 'לא ניתן לעבד את השאלה');
      res.json({ answer, metrics: snap });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  router.post('/analyze', async (req, res) => {
    try {
      const { agentId, changeRequest } = req.body || {};
      if (!changeRequest) return res.status(400).json({ error: 'changeRequest required' });

      const agents = getAgentRegistry();
      const agent = agents.find(a => a.id === agentId);

      const category = detectCategory(changeRequest);
      const riskSignals = detectRiskSignals(changeRequest, agent);

      const systemMsg = `אתה מנתח בקשות שינוי לסוכני AI. ענה תמיד ב-JSON בלבד.`;
      const agentCtx = agent
        ? `הסוכן: ${agent.nameHe} (${agent.id}), risk: ${agent.risk}, mode: ${agent.mode}, autonomy: ${agent.autonomy}%`
        : 'הסוכן לא זוהה';

      const prompt = `${agentCtx}
בקשת השינוי: "${changeRequest}"
קטגוריה זוהתה: ${CATEGORY_LABELS[category]}

צור 2-4 שאלות הבהרה בעברית כ-JSON array:
[{"label":"שאלה קצרה","reason":"למה חשוב","options":[{"value":"opt1","label":"אפשרות 1"},{"value":"opt2","label":"אפשרות 2"}]}]
כל אובייקט options חייב לכלול תמיד גם {"value":"other","label":"אחר"}.
ענה ב-JSON array בלבד, ללא טקסט נוסף.`;

      let questions = [];
      let intent = changeRequest;
      let confidence = 0.75;

      try {
        const raw = await callGemma4([
          { role: 'system', content: systemMsg },
          { role: 'user', content: prompt },
        ], false, 400);
        const match = raw.match(/\[[\s\S]*\]/);
        if (match) {
          const parsed = JSON.parse(match[0]);
          if (Array.isArray(parsed)) questions = parsed;
        }
      } catch (_) {}

      if (riskSignals.length > 0) confidence = Math.max(0.5, confidence - riskSignals.length * 0.05);

      res.json({
        category,
        categoryLabel: CATEGORY_LABELS[category],
        intent,
        confidence,
        riskSignals: riskSignals.map(s => ({ key: s, label: RISK_SIGNAL_LABELS[s] })),
        missingContext: questions.length === 0 ? ['לא ברור היקף השינוי'] : [],
        questions,
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  router.post('/build-prompt', async (req, res) => {
    try {
      const { agentId, changeRequest, analysis, answers, notes } = req.body || {};
      if (!changeRequest) return res.status(400).json({ error: 'changeRequest required' });

      const agents = getAgentRegistry();
      const agent = agents.find(a => a.id === agentId);
      const agentCtx = agent
        ? `שם: ${agent.nameHe} (${agent.id})
תפקיד: ${agent.role}
מצב הפרומפט הנוכחי: ${agent.prompt || 'לא זמין'}
רמת סיכון: ${agent.risk} | מצב: ${agent.mode} | אוטונומיה: ${agent.autonomy}%
כלים: ${(agent.tools || []).join(', ')}
הרשאות: ${(agent.permissions || []).join(', ')}`
        : 'סוכן לא זוהה';

      const answersText = answers && Object.keys(answers).length
        ? Object.entries(answers).map(([q, a]) => `- ${q}: ${a}`).join('\n')
        : 'לא סופקו';

      const systemMsg = `אתה מהנדס פרומפטים מומחה. בנה פרומפט מפורט לשינוי סוכן AI. ענה ב-JSON בלבד.`;

      const prompt = `הקשר הסוכן:
${agentCtx}

בקשת השינוי: "${changeRequest}"
קטגוריה: ${analysis?.categoryLabel || 'לא ידועה'}
סיכונים שזוהו: ${(analysis?.riskSignals || []).map(r => r.label).join(', ') || 'אין'}

תשובות לשאלות הבהרה:
${answersText}

הערות נוספות:
${notes || 'אין'}

צור JSON עם:
{
  "reviewText": "סיכום קצר בעברית (3-5 נקודות bullet) של מה שJarvis הבין, סוג השינוי, רמת הסיכון, ומה הכלי צריך לעשות",
  "prompt": "פרומפט מלא ומפורט בעברית שמהנדס יוכל להשתמש בו ישירות לשינוי הסוכן"
}
ענה ב-JSON בלבד.`;

      let reviewText = '';
      let fullPrompt = '';

      try {
        const raw = await callGemma4([
          { role: 'system', content: systemMsg },
          { role: 'user', content: prompt },
        ], false, 800);
        const match = raw.match(/\{[\s\S]*\}/);
        if (match) {
          const parsed = JSON.parse(match[0]);
          reviewText = parsed.reviewText || '';
          fullPrompt = parsed.prompt || '';
        }
      } catch (_) {}

      if (!fullPrompt) {
        fullPrompt = `# שינוי סוכן: ${agent?.nameHe || agentId}

## בקשה
${changeRequest}

## הקשר
${agentCtx}

## תשובות
${answersText}

## הערות
${notes || 'אין'}

## הנחיות לביצוע
1. עדכן את קובץ agents/${agentId}.js
2. שמור על ממשק הפונקציה הקיים
3. בדוק עם npm test לאחר השינוי`;
      }

      if (!reviewText) {
        reviewText = `• מה Jarvis הבין: ${changeRequest}\n• סוג שינוי: ${analysis?.categoryLabel || 'לא ידוע'}\n• רמת סיכון: ${agent?.risk || 'לא ידועה'}\n• פעולה נדרשת: עדכון הסוכן`;
      }

      res.json({ prompt: fullPrompt, reviewText });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return router;
}

module.exports = { createAgentCenterRouter };
