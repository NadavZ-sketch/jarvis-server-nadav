require('dotenv').config();
const { callGemma4 } = require('./models');

// Survey question templates based on user actions
const SURVEY_QUESTIONS = {
  taskUsage: {
    question: 'איך הרגשת בהשימוש במשימות?',
    options: ['מעניין וצריך לשפר', 'נוח וטוב', 'לא כל כך שימושי']
  },
  reminderUsage: {
    question: 'תזכורות עזרו לך?',
    options: ['כן מאוד', 'בחלקם', 'לא כל כך']
  },
  responseQuality: {
    question: 'איכות התשובות שקיבלת?',
    options: ['מעולה', 'טובה', 'בינונית', 'יש מקום לשיפור']
  },
  memoryUsage: {
    question: 'האם ג\'רביס זוכר עובדות עליך?',
    options: ['כן זוכר בדיוק', 'לפעמים', 'לא זוכר']
  },
  communicationStyle: {
    question: 'אתה מעדיף:',
    options: ['תשובות קצרות וקולעות', 'הסברים מפורטים', 'כמו עכשיו בסדר']
  },
  dailyValue: {
    question: 'כמה ג\'רביס עזר לך בעבודה יומית?',
    options: ['מאוד', 'במידה מסוימת', 'קצת', 'לא במיוחד']
  },
  featureImportance: {
    question: 'איזו תכונה הכי חשובה לך?',
    options: ['שיחה משכלת', 'משימות וזיכרונות', 'דיוקי קול', 'קצוב הודעות']
  },
  improvementSuggestion: {
    question: 'מה אתה רוצה לשפר הכי הרבה?',
    options: ['מהירות', 'דיוק', 'ממשק המשתמש', 'יותר תכונות']
  },
};

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

// Generate summary from responses
async function generateSurveySummary(survey, responses, userName) {
  const responsesText = survey
    .map(q => `${q.question} → ${responses[q.id] || 'ללא תשובה'}`)
    .join('\n');

  const prompt = `נתונים משאל חוויית משתמש:
${responsesText}

כתוב סיכום קצר (2-3 משפטים בעברית) של חוויית המשתמש ${userName}, כולל:
1. כללי תחת של רציונות
2. תחום אחד לשיפור
3. עצה אחת קטנה לשימוש טוב יותר

דוח סיכום:`;

  try {
    const result = await callGemma4(prompt);
    return result.trim();
  } catch (err) {
    return `${userName}, תודה על ההשתתפות בסקר! תשובותיך עוזרות לנו לשפר את ג'רביס.`;
  }
}

module.exports = {
  SURVEY_QUESTIONS,
  selectSurveyQuestions,
  buildSurveyJson,
  generateSurveySummary,
};
