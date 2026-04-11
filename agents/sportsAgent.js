require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const SPORTS_PROMPT = `אתה מומחה לפרמייר ליג האנגלי. ענה תמיד בעברית בלבד.
ספק מידע עדכני על: תוצאות משחקים, טבלת הליגה, כובשים, קבוצות ושחקנים.

שאלת המשתמש: `;

async function runSportsAgent(userMessage) {
    try {
        let answer;
        try {
            answer = await callGeminiWithSearch(SPORTS_PROMPT + userMessage);
        } catch (geminiErr) {
            console.warn('⚠️ Gemini Search failed, falling back to Groq:', geminiErr.message);
            answer = await callGemma4(SPORTS_PROMPT + userMessage, false);
        }
        console.log('⚽ SportsAgent answered');
        return { answer: answer || 'לא הצלחתי למצוא מידע עדכני על הפרמייר ליג.' };

    } catch (err) {
        console.error('SportsAgent Error:', err.message);
    }

    return { answer: 'סליחה, לא הצלחתי להביא נתוני כדורגל כרגע.' };
}

module.exports = { runSportsAgent };
