require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const NEWS_PROMPT = `אתה עוזר חדשות ישראלי. ענה תמיד בעברית בלבד.
הבא חדשות עדכניות וחשובות מישראל ומהעולם.
תאר 3-5 כותרות עיקריות בצורה קצרה וברורה, כל כותרת בשורה חדשה.
אם המשתמש ביקש נושא ספציפי — התמקד בו בלבד.
תאריך היום: ${new Date().toLocaleDateString('he-IL')}.

שאלת המשתמש: `;

async function runNewsAgent(userMessage) {
    try {
        let answer;
        try {
            answer = await callGeminiWithSearch(NEWS_PROMPT + userMessage);
        } catch (geminiErr) {
            console.warn('⚠️ Gemini Search failed (news), falling back to Groq:', geminiErr.message);
            answer = await callGemma4(NEWS_PROMPT + userMessage, false);
        }
        console.log('📰 NewsAgent answered');
        return { answer: answer || 'לא הצלחתי לטעון חדשות כרגע.' };
    } catch (err) {
        console.error('NewsAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי להביא חדשות כרגע.' };
    }
}

module.exports = { runNewsAgent };
