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

// Select 5-8 random questions based on user actions
function selectSurveyQuestions(userActions) {
  const qKeys = Object.keys(SURVEY_QUESTIONS);
  const numQuestions = Math.floor(Math.random() * 4) + 5; // 5-8 questions

  // Always include responseQuality, vary the rest
  const selected = { responseQuality: SURVEY_QUESTIONS.responseQuality };

  const remaining = qKeys.filter(k => k !== 'responseQuality')
    .sort(() => Math.random() - 0.5)
    .slice(0, numQuestions - 1);

  remaining.forEach(k => {
    selected[k] = SURVEY_QUESTIONS[k];
  });

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
