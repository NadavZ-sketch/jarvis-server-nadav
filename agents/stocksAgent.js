require('dotenv').config();
const { callGeminiWithSearch, callGemma4 } = require('./models');

const STOCKS_PROMPT = `אתה עוזר פיננסי ישראלי. ענה תמיד בעברית בלבד.
הבא מחירים עדכניים של מניות, קריפטו, מטבעות או מדדים.
כלול: מחיר נוכחי, שינוי באחוזים היום, ותחזית קצרה.
אם לא צוין נכס ספציפי — הצג את המדדים הראשיים (ת"א 35, S&P 500, נסד"ק, ביטקוין).
תאריך היום: ${new Date().toLocaleDateString('he-IL')}.

שאלת המשתמש: `;

async function runStocksAgent(userMessage) {
    try {
        let answer;
        try {
            answer = await callGeminiWithSearch(STOCKS_PROMPT + userMessage);
        } catch (e) {
            console.warn('⚠️ Gemini Search failed (stocks), fallback to Groq:', e.message);
            answer = await callGemma4(STOCKS_PROMPT + userMessage, false);
        }
        console.log('📈 StocksAgent answered');
        return { answer: answer || 'לא הצלחתי להביא נתוני שוק כרגע.' };
    } catch (err) {
        console.error('StocksAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי להביא נתוני מניות כרגע.' };
    }
}

module.exports = { runStocksAgent };
