require('dotenv').config();
const { callGemma4 } = require('./models');

const SPORTS_PROMPT = `אתה מומחה לפרמייר ליג האנגלי. ענה תמיד בעברית בלבד.
ספק מידע עדכני על: תוצאות משחקים, טבלת הליגה, כובשים, קבוצות ושחקנים.
אם אין לך מידע עדכני מספיק — ציין זאת בכנות.

שאלת המשתמש: `;

async function runSportsAgent(userMessage) {
    try {
        const answer = await callGemma4(SPORTS_PROMPT + userMessage);
        console.log('⚽ SportsAgent answered');
        return { answer: answer || 'לא הצלחתי למצוא מידע עדכני על הפרמייר ליג.' };

    } catch (err) {
        console.error('SportsAgent Error:', err.message);
    }

    return { answer: 'סליחה נדב, לא הצלחתי להביא נתוני כדורגל כרגע.' };
}

module.exports = { runSportsAgent };
