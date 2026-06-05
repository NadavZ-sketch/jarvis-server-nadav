require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const SYSTEM_PROMPT = `אתה מומחה ספורט. ענה תמיד בעברית בלבד.
ספק מידע על: תוצאות משחקים, טבלות ליגה, כובשים, קבוצות, שחקנים והעברות.
אם אין לך נתונים עדכניים — ציין זאת בבירור.`;

async function runSportsAgent(userMessage) {
    // Primary: Gemini with live search grounding
    try {
        const answer = await callGeminiWithSearch(SYSTEM_PROMPT + '\n\nשאלת המשתמש: ' + userMessage);
        if (answer) {
            return { answer };
        }
    } catch (err) {
        console.warn('SportsAgent Gemini failed, trying fallback:', err.message);
    }

    // Fallback: LLM without live search (may lack very recent results)
    try {
        const answer = await callGemma4([
            { role: 'system', content: SYSTEM_PROMPT },
            { role: 'user', content: userMessage },
        ], false, 400);
        return { answer: answer || 'לא הצלחתי למצוא מידע ספורטיבי כרגע.' };
    } catch (err) {
        console.error('SportsAgent fallback failed:', err.message);
        return { answer: 'סליחה, לא הצלחתי להביא נתוני ספורט כרגע. נסה שוב בעוד רגע.' };
    }
}

module.exports = { runSportsAgent };
