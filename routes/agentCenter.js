'use strict';

const express = require('express');
const path = require('path');
const { getAgentRegistry, setAgentStatus } = require('../services/agentRegistryService');

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

function createAgentCenterRouter({ callGemma4 }) {
  const router = express.Router();

  router.get('/', (_req, res) => {
    res.sendFile(path.join(__dirname, '..', 'progress-map.html'),
      err => { if (err && !res.headersSent) res.status(404).send('progress-map.html not found'); });
  });

  router.get('/agents', (_req, res) => {
    try {
      res.json({ agents: getAgentRegistry() });
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
