// Intent Engine - מזהה מה המשתמש רוצה

const INTENTS = {
  CHAT: 'chat',
  TASK: 'task',
  CALENDAR: 'calendar',
  REMINDER: 'reminder',
  WEATHER: 'weather',
  SEARCH: 'search',
};

// מילות מפתח לכל כוונה
const INTENT_KEYWORDS = {
  task: ['משימה', 'מטלה', 'לעשות', 'todo', 'task', 'להוסיף', 'צור משימה', 'רשימה'],
  calendar: ['פגישה', 'יומן', 'אירוע', 'תאריך', 'מתי', 'לוח זמנים', 'calendar', 'schedule'],
  reminder: ['תזכיר', 'תזכורת', 'אל תשכח', 'reminder', 'להזכיר', 'בשעה', 'בעוד'],
  weather: ['מזג אוויר', 'גשם', 'חם', 'קר', 'weather', 'טמפרטורה', 'תחזית'],
  search: ['חפש', 'מצא', 'מה זה', 'תסביר', 'search', 'גוגל', 'מידע על'],
};

function detectIntent(message) {
  const lowerMessage = message.toLowerCase();

  for (const [intent, keywords] of Object.entries(INTENT_KEYWORDS)) {
    for (const keyword of keywords) {
      if (lowerMessage.includes(keyword)) {
        return {
          intent: intent,
          confidence: 'high',
          keyword: keyword,
        };
      }
    }
  }

  // ברירת מחדל - שיחה רגילה
  return {
    intent: INTENTS.CHAT,
    confidence: 'low',
    keyword: null,
  };
}

module.exports = { detectIntent, INTENTS };