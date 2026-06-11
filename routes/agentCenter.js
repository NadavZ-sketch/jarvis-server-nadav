'use strict';

const express = require('express');
const path = require('path');
const { getAgentRegistry, setAgentStatus, setAgentRisk, isProtectedAgent, saveAgentCustomization, getAgentCustomizations } = require('../services/agentRegistryService');

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

// Generic words that appear in (almost) every agent name and must not, on their
// own, resolve a match — otherwise "כבה את הסוכן" would hit a random agent.
const AGENT_STOPWORDS = new Set(['סוכן', 'agent', 'the', 'את']);

// Map a free-text fragment to an agent in the registry, by id or Hebrew/English
// name. Returns the matched agent or null. Used by the NL command router so we
// can resolve "כבה את סוכן החדשות" → newsAgent without an LLM round-trip.
// Matching is word-level and tolerant of the Hebrew definite article (the noun
// "חדשות" still matches inside "החדשות"), and scores by the longest distinctive
// word so the specific noun beats the generic "סוכן".
function matchAgent(text, registry) {
  const t = text.toLowerCase();
  let best = null;
  for (const a of registry) {
    const candidates = [a.id, a.name, a.nameHe].filter(Boolean).map(s => String(s).toLowerCase());
    let score = 0;
    for (const c of candidates) {
      // Whole-id substring (e.g. "newsagent") is the strongest signal.
      if (c.length >= 4 && !c.includes(' ') && t.includes(c)) score = Math.max(score, c.length + 4);
      for (const w of c.split(/\s+/)) {
        if (w.length >= 4 && !AGENT_STOPWORDS.has(w) && t.includes(w)) score = Math.max(score, w.length);
      }
    }
    if (score > 0 && (!best || score > best.score)) best = { agent: a, score };
  }
  return best ? best.agent : null;
}

// Control-center tab ids the NL router can navigate to, with Hebrew triggers.
const NAV_TABS = [
  { id: 'overview', kws: ['סקירה', 'בית', 'דשבורד', 'overview', 'בריאות'] },
  { id: 'agents', kws: ['סוכנים', 'סוכן', 'agents'] },
  { id: 'analytics', kws: ['אנליטיקה', 'נתונים', 'סטטיסטיקה', 'analytics', 'גרפים'] },
  { id: 'dev', kws: ['פיתוח', 'roadmap', 'backlog', 'הצעות', 'פיצרים'] },
  { id: 'qa', kws: ['בדיקות', 'סקרים', 'qa', 'e2e'] },
  { id: 'settings', kws: ['הגדרות', 'settings', 'הגדרה'] },
];

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
      const agents = await getAgentRegistry();
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
  router.post('/agents/:id/toggle', async (req, res) => {
    try {
      const agentId = req.params.id;
      const registry = await getAgentRegistry();
      const current = registry.find(a => a.id === agentId);
      if (!current) return res.status(404).json({ error: 'agent not found' });
      const explicit = req.body && typeof req.body.status === 'string' ? req.body.status : null;
      const nextStatus = explicit
        ? explicit
        : (current.status === 'disabled' ? 'active' : 'disabled');
      const override = await setAgentStatus(agentId, nextStatus);
      res.json({ id: agentId, status: nextStatus, updatedAt: override.updatedAt });
    } catch (err) {
      res.status(400).json({ error: err.message });
    }
  });

  // Set an agent's risk level (low|medium|high). Persisted as an override.
  router.post('/agents/:id/risk', async (req, res) => {
    try {
      const agentId = req.params.id;
      const registry = await getAgentRegistry();
      if (!registry.find(a => a.id === agentId)) return res.status(404).json({ error: 'agent not found' });
      const riskLevel = req.body && req.body.riskLevel;
      const override = await setAgentRisk(agentId, riskLevel);
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

      const agents = await getAgentRegistry();
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

      const agents = await getAgentRegistry();
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

  // ─── Agent chat: converse with a specific agent in its own domain ──────────
  // POST /progress-map/agents/:id/chat  { message, history[] }
  router.post('/agents/:id/chat', async (req, res) => {
    try {
      const { id } = req.params;
      const { message, history = [] } = req.body || {};
      if (!message) return res.status(400).json({ error: 'message required' });

      const agents = await getAgentRegistry();
      const agent = agents.find(a => a.id === id);
      if (!agent) return res.status(404).json({ error: 'agent not found' });

      const systemPrompt = `אתה ${agent.nameHe} (${agent.name}), סוכן AI חלק ממערכת ג'רביס.
תפקיד: ${agent.role}
משימה: ${agent.mission}
אחריות: ${(agent.responsibilities || []).join(', ')}
כלים: ${(agent.tools || []).join(', ')}
הנחיות פעולה: ${agent.prompt || 'לא מוגדרות'}
רמת סיכון: ${agent.risk} | מצב: ${agent.mode} | אוטונומיה: ${agent.autonomy}%

ענה על שאלות המשתמש לגבי יכולותיך ואופן פעולתך.
אם המשתמש מבקש לשנות את התנהגותך (תהיה יותר קצר, תמיד השתמש בכדורים, וכו'), אשר שהבנת ותסביר כיצד תפעל.
ענה תמיד בעברית.`;

      const messages = [
        { role: 'system', content: systemPrompt },
        ...history.slice(-6).map(h => ({ role: h.role, content: h.content })),
        { role: 'user', content: message },
      ];

      const answer = await callGemma4(messages, false, 500);

      // Detect customization intent and persist as a note.
      const isCustomization = /תהיה|אל תהיה|תמיד|אף פעם|שנה.{0,10}התנהגות|התנהג|הפסק לענות|התחל לענות/i.test(message);
      let savedCustomization = null;
      if (isCustomization) {
        const ok = await saveAgentCustomization(id, message);
        if (ok) savedCustomization = { text: message, at: new Date().toISOString() };
      }

      res.json({ answer, agentId: id, savedCustomization });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  // GET /progress-map/agents/:id/customizations
  router.get('/agents/:id/customizations', async (req, res) => {
    try {
      const customizations = await getAgentCustomizations(req.params.id);
      res.json({ customizations });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  // ─── Natural-language control bar ──────────────────────────────────────────
  // POST { text } → { intent, action, params, answer }. Deterministic-first
  // (regex) routing keeps common commands token-free; only genuinely ambiguous
  // questions fall through to the LLM. The frontend executes `action`:
  //   toggle_agent | navigate | run_scan | run_e2e | answer
  router.post('/command', async (req, res) => {
    try {
      const text = String((req.body && req.body.text) || '').trim();
      if (!text) return res.status(400).json({ error: 'text required' });
      const t = text.toLowerCase();
      const registry = await getAgentRegistry().catch(() => []);

      // 1) Toggle an agent on/off — needs both an on/off verb and an agent match.
      // NOTE: no \b anchors — JS word boundaries are ASCII-only and never match
      // adjacent to Hebrew letters, which would silently disable every command.
      const wantsOff = /(כבה|השבת|בטל|הפסק|turn off|disable|stop)/.test(t);
      const wantsOn = /(הדלק|הפעל|אפשר|הרץ את הסוכן|turn on|enable|activate)/.test(t);
      if (wantsOff || wantsOn) {
        const agent = matchAgent(text, registry);
        if (agent && !isProtectedAgent(agent.id)) {
          const nextStatus = wantsOff ? 'disabled' : 'active';
          try {
            await setAgentStatus(agent.id, nextStatus);
            return res.json({
              intent: 'toggle_agent',
              action: 'toggle_agent',
              params: { agentId: agent.id, status: nextStatus },
              answer: `${nextStatus === 'disabled' ? 'כיביתי' : 'הפעלתי'} את ${agent.nameHe || agent.id}.`,
            });
          } catch (err) {
            return res.status(500).json({
              error: `failed to ${nextStatus === 'disabled' ? 'disable' : 'enable'} agent: ${err.message}`,
              action: 'answer',
              answer: `לא הצלחתי ${nextStatus === 'disabled' ? 'לכבות' : 'להפעיל'} את ${agent.nameHe || agent.id} — שגיאת קובץ.`,
            });
          }
        }
        if (agent && isProtectedAgent(agent.id)) {
          return res.json({ intent: 'toggle_agent', action: 'answer', params: {}, answer: `לא ניתן לכבות את ${agent.nameHe || agent.id} — סוכן מוגן.` });
        }
      }

      // 2) Run a scan / E2E suite.
      if (/(סרוק|סריקה|בדוק קוד|scan)/.test(t)) {
        return res.json({ intent: 'run_scan', action: 'run_scan', params: {}, answer: 'מריץ סריקת קוד...' });
      }
      if (/(בדיקות e2e|הרץ בדיקות|run e2e|e2e)/.test(t)) {
        return res.json({ intent: 'run_e2e', action: 'run_e2e', params: {}, answer: 'מריץ בדיקות E2E...' });
      }

      // 3) Navigate to a tab — only when the user explicitly asks to go/show.
      if (/(עבור|פתח|הצג|הראה|לך ל|תראה|go to|open|show)/.test(t)) {
        for (const tab of NAV_TABS) {
          if (tab.kws.some(k => t.includes(k))) {
            return res.json({ intent: 'navigate', action: 'navigate', params: { tab: tab.id }, answer: `עובר ל${tab.kws[0]}.` });
          }
        }
      }

      // 4) Fall through to the LLM only for free-form questions about metrics.
      const snap = agentMetrics
        ? await agentMetrics.snapshot().catch(() => ({ latency: [], intent: { fast: 0, llm: 0 } }))
        : { latency: [], intent: { fast: 0, llm: 0 } };
      const metricsText = snap.latency.length
        ? snap.latency.map(r => `${r.agent}: ${r.avgMs}ms avg, ${r.count} calls`).join('\n')
        : 'אין נתוני מדדים זמינים';
      const answer = await callGemma4([
        { role: 'system', content: 'אתה עוזר שליטה ללוח הניהול של ג׳ארביס. ענה בעברית בקצרה על בסיס הנתונים בלבד. אם השאלה אינה על המדדים, אמור שאינך יכול לבצע את הפעולה הזו מהשורה.' },
        { role: 'user', content: `מדדי סוכנים (24ש'):\n${metricsText}\nסיווג intent: fast=${snap.intent.fast}, llm=${snap.intent.llm}\n\nבקשה: "${text}"` },
      ], false, 300).catch(() => 'לא הצלחתי לעבד את הבקשה.');
      return res.json({ intent: 'answer', action: 'answer', params: {}, answer });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return router;
}

module.exports = { createAgentCenterRouter };
