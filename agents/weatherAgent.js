require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const WEATHER_PROMPT_BASE = `אתה עוזר מזג אוויר ידידותי. ענה תמיד בעברית בלבד.
ספק מידע עדכני: טמפרטורה, תחושה בחוץ, מצב שמיים, סיכוי לגשם, המלצת לבוש.
אם לא צוין מיקום — הנח ישראל / תל אביב.
היה תמציתי ופרקטי. תאריך היום: ${new Date().toLocaleDateString('he-IL')}.`;

async function runWeatherAgent(userMessage, settings = {}) {
    try {
        const memBlock = settings.userMemories
            ? `\nמידע רלוונטי על המשתמש (השתמש בו לגבי מיקום אם לא צוין): ${settings.userMemories}`
            : '';

        const prompt = WEATHER_PROMPT_BASE + memBlock + '\n\nשאלת המשתמש: ' + userMessage;

        let answer;
        try {
            answer = await callGeminiWithSearch(prompt);
        } catch (geminiErr) {
            console.warn('⚠️ Gemini Search failed (weather), falling back to Groq:', geminiErr.message);
            answer = await callGemma4(prompt, false);
        }
        console.log('🌤️ WeatherAgent answered');
        return { answer: answer || 'לא הצלחתי להביא תחזית מזג אוויר כרגע.' };
    } catch (err) {
        console.error('WeatherAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי להביא נתוני מזג אוויר כרגע.' };
    }
}

module.exports = { runWeatherAgent };
