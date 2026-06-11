require('dotenv').config();

// Survey question templates. Options are ordered best → worst where it makes
// sense, so the first option is treated as the most positive answer.
const SURVEY_QUESTIONS = {
  taskUsage: {
    question: 'איך הרגשת בשימוש במשימות?',
    options: ['נוח וטוב', 'מעניין וצריך לשפר', 'לא כל כך שימושי'],
  },
  reminderUsage: {
    question: 'תזכורות עזרו לך?',
    options: ['כן מאוד', 'בחלקם', 'לא כל כך'],
  },
  responseQuality: {
    question: 'איכות התשובות שקיבלת?',
    options: ['מעולה', 'טובה', 'בינונית', 'יש מקום לשיפור'],
  },
  memoryUsage: {
    question: 'האם ג\'רביס זוכר עובדות עליך?',
    options: ['כן זוכר בדיוק', 'לפעמים', 'לא זוכר'],
  },
  communicationStyle: {
    question: 'אתה מעדיף:',
    options: ['תשובות קצרות וקולעות', 'הסברים מפורטים', 'כמו עכשיו בסדר'],
  },
  dailyValue: {
    question: 'כמה ג\'רביס עזר לך בעבודה יומית?',
    options: ['מאוד', 'במידה מסוימת', 'קצת', 'לא במיוחד'],
  },
  featureImportance: {
    question: 'איזו תכונה הכי חשובה לך?',
    options: ['שיחה משכלת', 'משימות וזיכרונות', 'דיוקי קול', 'ניסוח הודעות'],
  },
  improvementSuggestion: {
    question: 'מה אתה רוצה לשפר הכי הרבה?',
    options: ['מהירות', 'דיוק', 'ממשק המשתמש', 'יותר תכונות'],
  },
};

// Answers that signal the user is NOT satisfied — used to derive an
// "area to improve" from real responses (deterministic, no LLM guessing).
const NEGATIVE_HINTS = ['לא ', 'מקום לשיפור', 'בינונית', 'קצת', 'במיוחד', 'לא זוכר', 'לא כל כך', 'צריך לשפר'];

function isNegativeAnswer(answer) {
  if (!answer) return false;
  return NEGATIVE_HINTS.some(h => answer.includes(h.trim()));
}

// Select 5-8 random questions based on user actions.
// `excludeIds` (Set | array) lists question keys to avoid — typically the
// questions the user already answered in recent surveys, to prevent the
// survey from feeling repetitive across sessions.
function selectSurveyQuestions(userActions, excludeIds = []) {
  const exclude = new Set(Array.isArray(excludeIds) ? excludeIds : [...excludeIds]);
  const qKeys = Object.keys(SURVEY_QUESTIONS).filter(k => !exclude.has(k));

  // Always include responseQuality if not excluded — it's the anchor question.
  const selected = {};
  let pool = qKeys;
  if (!exclude.has('responseQuality')) {
    selected.responseQuality = SURVEY_QUESTIONS.responseQuality;
    pool = qKeys.filter(k => k !== 'responseQuality');
  }

  // If we excluded too many, relax: re-include the least-recently-asked ones.
  if (pool.length === 0 && Object.keys(selected).length === 0) {
    const fallback = Object.keys(SURVEY_QUESTIONS).slice(0, 3);
    fallback.forEach(k => { selected[k] = SURVEY_QUESTIONS[k]; });
    return selected;
  }

  const numQuestions = Math.min(
    Math.max(3, Math.floor(Math.random() * 4) + 5), // aim 5-8, floor at 3
    pool.length + Object.keys(selected).length,
  );

  const remaining = pool
    .sort(() => Math.random() - 0.5)
    .slice(0, numQuestions - Object.keys(selected).length);

  remaining.forEach(k => { selected[k] = SURVEY_QUESTIONS[k]; });

  return selected;
}

// Build JSON-friendly survey format for Flutter
function buildSurveyJson(questions) {
  return Object.entries(questions).map(([id, q]) => ({
    id,
    question: q.question,
    options: q.options,
  }));
}

// Build a factual summary straight from the user's answers — NO LLM.
// Returns { text, breakdown } where `breakdown` lists each answer and whether
// it flags an area to improve. The summary is verifiable: it only restates
// what the user actually selected.
function buildSurveySummary(survey, responses, userName = '') {
  const answered = survey
    .map(q => ({
      id: q.id,
      question: q.question || SURVEY_QUESTIONS[q.id]?.question || q.id,
      answer: responses[q.id] || null,
    }))
    .filter(q => q.answer != null);

  const positives = answered.filter(q => !isNegativeAnswer(q.answer));
  const concerns  = answered.filter(q => isNegativeAnswer(q.answer));

  const hello = userName ? `תודה ${userName}! ` : 'תודה! ';
  const lines = [`${hello}קיבלנו ${answered.length} תשובות.`];

  if (positives.length) {
    lines.push(`👍 עובד טוב: ${positives.map(p => `${p.question} → ${p.answer}`).join(' · ')}`);
  }
  if (concerns.length) {
    lines.push(`🔧 לשיפור: ${concerns.map(c => `${c.question} → ${c.answer}`).join(' · ')}`);
  } else if (answered.length) {
    lines.push('🔧 לשיפור: לא סומנו תחומים לשיפור הפעם.');
  }

  return {
    text: lines.join('\n'),
    breakdown: answered.map(q => ({ ...q, concern: isNegativeAnswer(q.answer) })),
  };
}

// Aggregate real responses across many stored surveys (deterministic).
// `rows` = array of { responses: object|string, created_at }.
// Returns per-question answer distributions (counts + percentages), the count
// of surveys, and a chronological trend for the anchor question.
function aggregateSurveys(rows) {
  const surveys = (rows || []).map(r => {
    let resp = r.responses;
    if (typeof resp === 'string') {
      try { resp = JSON.parse(resp); } catch (_) { resp = {}; }
    }
    return { responses: resp || {}, created_at: r.created_at };
  });

  const byQuestion = {}; // qId -> { question, total, answers: { answer: count } }
  for (const s of surveys) {
    for (const [qId, answer] of Object.entries(s.responses)) {
      if (!byQuestion[qId]) {
        byQuestion[qId] = {
          question: SURVEY_QUESTIONS[qId]?.question || qId,
          total: 0,
          answers: {},
        };
      }
      const q = byQuestion[qId];
      q.total++;
      q.answers[answer] = (q.answers[answer] || 0) + 1;
    }
  }

  // Convert answer tallies to sorted distributions with percentages.
  const questions = Object.entries(byQuestion).map(([id, q]) => ({
    id,
    question: q.question,
    total: q.total,
    distribution: Object.entries(q.answers)
      .map(([answer, count]) => ({ answer, count, pct: Math.round((count / q.total) * 100) }))
      .sort((a, b) => b.count - a.count),
  }));

  // Anchor-question trend over time (oldest → newest).
  const trend = surveys
    .filter(s => s.responses.responseQuality)
    .sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))
    .map(s => ({ at: s.created_at, answer: s.responses.responseQuality }));

  return { surveyCount: surveys.length, questions, anchorTrend: trend };
}

// Turn an aggregation into plain factual Hebrew insight lines (no LLM).
// Only reports a question once it has a clearly dominant answer.
function insightsFromAggregation(agg) {
  const insights = [];
  for (const q of agg.questions) {
    const top = q.distribution[0];
    if (!top) continue;
    if (top.pct >= 50 && q.total >= 2) {
      insights.push(`ב-${top.pct}% מהסקרים (${top.count}/${q.total}) ענית "${top.answer}" על "${q.question}".`);
    }
  }
  return insights.slice(0, 5);
}

// Generate smart, personalised survey questions using LLM context.
// Falls back gracefully to static questions if the LLM call fails.
async function generateSmartSurvey(callGemma4Fn, context = {}) {
  const { topAgents = [], pastConcerns = [] } = context;

  const agentNames = topAgents.slice(0, 5)
    .map(a => `${a.agent} (${a.count} שימושים)`).join(', ');
  const concernText = pastConcerns.slice(0, 3)
    .map(c => `- ${c.area}: "${c.answer}"`).join('\n');

  const prompt = `אתה מנהל מוצר של ג'רביס, עוזר AI אישי בעברית.
המשתמש השתמש לאחרונה ב: ${agentNames || 'לא ידוע'}
${concernText ? `בסקרים קודמים ציין בעיות ב:\n${concernText}` : ''}

צור 4 שאלות סקר מותאמות אישית. הנחיות:
- כל שאלה צריכה להיות ספציפית לסוכנים שבהם נעשה שימוש
- אם יש בעיות קודמות — שאל האם הן טופלו
- כלול שאלה פתוחה אחת (open_text:true) לכתיבה חופשית
- הימנע משאלות גנריות

החזר JSON בלבד:
{"questions":[{"id":"q1","question":"...","options":["...","..."],"open_text":false}]}`;

  try {
    const raw = await callGemma4Fn(
      [{ role: 'user', content: prompt }],
      false,
      600,
    );
    const match = raw.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      if (Array.isArray(parsed?.questions) && parsed.questions.length >= 2) {
        const anchor = {
          id: 'responseQuality',
          question: SURVEY_QUESTIONS.responseQuality.question,
          options: SURVEY_QUESTIONS.responseQuality.options,
          open_text: false,
        };
        return [anchor, ...parsed.questions.slice(0, 4)];
      }
    }
  } catch (e) {
    console.error('[surveyAgent] generateSmartSurvey error:', e.message);
  }
  return buildSurveyJson(selectSurveyQuestions({}, []));
}

// Extract actionable concern objects from a response map.
function extractConcerns(responses) {
  return Object.entries(responses)
    .filter(([qId, answer]) => isNegativeAnswer(answer) && SURVEY_QUESTIONS[qId])
    .map(([qId, answer]) => ({
      area: SURVEY_QUESTIONS[qId].question,
      answer,
      questionId: qId,
      timestamp: new Date().toISOString(),
    }));
}

module.exports = {
  SURVEY_QUESTIONS,
  selectSurveyQuestions,
  buildSurveyJson,
  buildSurveySummary,
  aggregateSurveys,
  insightsFromAggregation,
  isNegativeAnswer,
  generateSmartSurvey,
  extractConcerns,
};
