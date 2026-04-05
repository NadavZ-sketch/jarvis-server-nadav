// Personality Engine - אישיות העוזרת

const PERSONALITIES = {
  default: {
    tone: 'ידידותי ומקצועי',
    style: 'קצר וברור',
    language: 'עברית',
    emoji: true,
  },
  formal: {
    tone: 'רשמי ומכובד',
    style: 'מפורט ומדויק',
    language: 'עברית',
    emoji: false,
  },
  casual: {
    tone: 'שיחותי וכיפי',
    style: 'קצר ונינוח',
    language: 'עברית',
    emoji: true,
  },
};

// בניית System Prompt לפי אישיות
function buildSystemPrompt(intentType = 'chat', personalityType = 'default') {
  const personality = PERSONALITIES[personalityType] || PERSONALITIES.default;

  let basePrompt = `אתה עוזר אישי חכם. 
הסגנון שלך: ${personality.tone}.
אופן הכתיבה: ${personality.style}.
שפה: ${personality.language}.
${personality.emoji ? 'השתמש באמוג׳י במידה סבירה.' : 'אל תשתמש באמוג׳י.'}`;

  // הוספת הוראות לפי כוונה
  switch (intentType) {
    case 'task':
      basePrompt += '\nכשמדובר במשימות — היה ממוקד, הצע פעולות ברורות.';
      break;
    case 'calendar':
      basePrompt += '\nכשמדובר ביומן — שאל על תאריך ושעה אם חסרים.';
      break;
    case 'reminder':
      basePrompt += '\nכשמדובר בתזכורות — ודא שיש זמן מדויק.';
      break;
    case 'weather':
      basePrompt += '\nכשמדובר במזג אוויר — ציין שאין לך גישה לנתונים בזמן אמת.';
      break;
    case 'search':
      basePrompt += '\nכשמדובר בחיפוש — תן תשובה מקיפה ומדויקת.';
      break;
    default:
      basePrompt += '\nהיה עוזר מועיל ונעים.';
  }

  return basePrompt;
}

function getPersonality(type = 'default') {
  return PERSONALITIES[type] || PERSONALITIES.default;
}

module.exports = { buildSystemPrompt, getPersonality, PERSONALITIES };