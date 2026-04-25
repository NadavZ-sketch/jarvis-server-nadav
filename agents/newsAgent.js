require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const NEWS_PROMPT_BASE = `אתה עוזר חדשות ישראלי. ענה תמיד בעברית בלבד.
הבא חדשות עדכניות וחשובות מישראל ומהעולם.
תאר 3-5 כותרות עיקריות בצורה קצרה וברורה, כל כותרת בשורה חדשה.
אם המשתמש ביקש נושא ספציפי — התמקד בו בלבד.
תאריך היום: ${new Date().toLocaleDateString('he-IL')}.`;

async function runNewsAgent(userMessage, settings = {}) {
    try {
        const memBlock = settings.userMemories
            ? `\nהעדפות ותחומי עניין של המשתמש (השתמש בהם כדי להדגיש חדשות רלוונטיות): ${settings.userMemories}`
            : '';

        const prompt = NEWS_PROMPT_BASE + memBlock + '\n\nשאלת המשתמש: ' + userMessage;

        let answer;
        try {
            answer = await callGeminiWithSearch(prompt);
        } catch (geminiErr) {
            console.warn('⚠️ Gemini Search failed (news), falling back to Groq:', geminiErr.message);
            answer = await callGemma4(prompt, false);
        }
        console.log('📰 NewsAgent answered');
        return { answer: answer || 'לא הצלחתי לטעון חדשות כרגע.' };
    } catch (err) {
        console.error('NewsAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי להביא חדשות כרגע.' };
    }
}

module.exports = { runNewsAgent };
