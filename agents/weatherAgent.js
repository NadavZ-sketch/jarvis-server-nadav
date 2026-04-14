require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const WEATHER_PROMPT = `אתה עוזר מזג אוויר ידידותי. ענה תמיד בעברית בלבד.
ספק מידע עדכני: טמפרטורה, תחושה בחוץ, מצב שמיים, סיכוי לגשם, המלצת לבוש.
אם לא צוין מיקום — הנח ישראל / תל אביב.
היה תמציתי ופרקטי. תאריך היום: ${new Date().toLocaleDateString('he-IL')}.

שאלת המשתמש: `;

async function runWeatherAgent(userMessage) {
    try {
        let answer;
        try {
            answer = await callGeminiWithSearch(WEATHER_PROMPT + userMessage);
        } catch (geminiErr) {
            console.warn('⚠️ Gemini Search failed (weather), falling back to Groq:', geminiErr.message);
            answer = await callGemma4(WEATHER_PROMPT + userMessage, false);
        }
        console.log('🌤️ WeatherAgent answered');
        return { answer: answer || 'לא הצלחתי להביא תחזית מזג אוויר כרגע.' };
    } catch (err) {
        console.error('WeatherAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי להביא נתוני מזג אוויר כרגע.' };
    }
}

module.exports = { runWeatherAgent };
