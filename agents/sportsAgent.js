require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const SYSTEM_PROMPT = `אתה מומחה ספורט. ענה תמיד בעברית בלבד.
ספק מידע על: תוצאות משחקים, טבלות ליגה, כובשים, קבוצות, שחקנים והעברות.
אם אין לך נתונים עדכניים — ציין זאת בבירור.`;

function buildCtxBlock(settings) {
    if (!settings?.recentHistory?.length) return '';
    return '\nהקשר שיחה אחרון:\n' + settings.recentHistory
        .slice(-3)
        .map(m => `${m.role === 'user' ? 'משתמש' : "ג'רביס"}: ${(m.text || m.content || '').slice(0, 100)}`)
        .join('\n');
}

async function runSportsAgent(userMessage, settings = {}) {
    const ctxBlock = buildCtxBlock(settings);
    // Primary: Gemini with live search grounding
    try {
        const answer = await callGeminiWithSearch(SYSTEM_PROMPT + ctxBlock + '\n\nשאלת המשתמש: ' + userMessage);
        if (answer) {
            return { answer };
        }
    } catch (err) {
        console.warn('SportsAgent Gemini failed, trying fallback:', err.message);
    }

    // Fallback: LLM without live search (may lack very recent results)
    try {
        const answer = await callGemma4([
            { role: 'system', content: SYSTEM_PROMPT + ctxBlock },
            { role: 'user', content: userMessage },
        ], false, 400);
        return { answer: answer || 'לא הצלחתי למצוא מידע ספורטיבי כרגע.' };
    } catch (err) {
        console.error('SportsAgent fallback failed:', err.message);
        return { answer: 'סליחה, לא הצלחתי להביא נתוני ספורט כרגע. נסה שוב בעוד רגע.' };
    }
}

module.exports = { runSportsAgent };
