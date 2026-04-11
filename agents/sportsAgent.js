require('dotenv').config();
const { callGeminiWithSearch } = require('./models');

const SPORTS_PROMPT = `אתה מומחה לפרמייר ליג האנגלי. ענה תמיד בעברית בלבד.
ספק מידע עדכני על: תוצאות משחקים, טבלת הליגה, כובשים, קבוצות ושחקנים.

שאלת המשתמש: `;

async function runSportsAgent(userMessage) {
    try {
        const answer = await callGeminiWithSearch(SPORTS_PROMPT + userMessage);
        console.log('⚽ SportsAgent answered');
        return { answer: answer || 'לא הצלחתי למצוא מידע עדכני על הפרמייר ליג.' };

    } catch (err) {
        console.error('SportsAgent Error:', err.message);
    }

    return { answer: 'סליחה, לא הצלחתי להביא נתוני כדורגל כרגע.' };
}

module.exports = { runSportsAgent };
