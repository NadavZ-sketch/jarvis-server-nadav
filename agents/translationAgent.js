require('dotenv').config();
const { callGemma4 } = require('./models');

const TRANSLATION_PROMPT = `אתה מתרגם מקצועי. תרגם את הטקסט שמציין המשתמש.
כללים:
- אם לא צוינה שפת יעד — אם הטקסט בעברית תרגם לאנגלית, אחרת תרגם לעברית.
- אם המשתמש ציין שפת יעד — תרגם לאותה שפה.
- החזר רק את התרגום, ללא הסברים נוספים.
- אם יש מספר אפשרויות תרגום — הצג את הנפוץ ביותר ובסוגריים חלופות.

הבקשה: `;

async function runTranslationAgent(userMessage, supabase, useLocal = true) {
    try {
        const answer = await callGemma4(TRANSLATION_PROMPT + userMessage, useLocal);
        console.log('🌐 TranslationAgent answered');
        return { answer: answer || 'לא הצלחתי לתרגם.' };
    } catch (err) {
        console.error('TranslationAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי לתרגם כרגע.' };
    }
}

module.exports = { runTranslationAgent };
