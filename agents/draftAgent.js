require('dotenv').config();
const { callGemma4 } = require('./models');

async function runDraftAgent(userMessage, chatHistory, longTermMemories, settings = {}) {
    try {
        const userName    = settings.userName    || 'נדב';
        const name        = settings.assistantName || 'Jarvis';
        const personality = settings.personality   || 'friendly';

        // Build a style reference from recent chat history (user messages only)
        const userSamples = chatHistory
            .filter(m => m.role === 'user')
            .slice(-6)
            .map(m => `- "${m.text}"`)
            .join('\n');

        const styleBlock = userSamples
            ? `להלן דוגמאות לסגנון הכתיבה של ${userName} (חיקה אותן בדיוק):\n${userSamples}`
            : '';

        const memoriesBlock = longTermMemories && longTermMemories !== 'אין עדיין זיכרונות שמורים.'
            ? `מידע על ${userName}:\n${longTermMemories}`
            : '';

        const prompt = `אתה ${name}, עוזר אישי ל${userName}. המשימה שלך לנסח טקסט בדיוק בסגנון הכתיבה של ${userName}.

${styleBlock}

${memoriesBlock}

כללים:
- כתוב בדיוק כמו ${userName} — אותו אורך משפטים, אותן מילות גישור, אותה רמת פורמליות.
- אל תוסיף מילות פתיחה כמו "הנה הניסוח:" או הסברים.
- כתוב רק את הטקסט המבוקש עצמו.
- אם יש כמה אפשרויות סגנון, בחר את המתאים ביותר לבקשה.

בקשה: ${userMessage}`;

        const draft = await callGemma4(prompt);

        // Check if the request seems to be for sending (WhatsApp/email)
        const sendIntent = /לשלוח|לשליחה|ווצאפ|וואטסאפ|מייל|לשלוח ל/i.test(userMessage);
        const followUp   = sendIntent
            ? '\n\nרוצה שאשלח אותה? תגיד לי למי.'
            : '';

        return { answer: `${draft}${followUp}` };

    } catch (err) {
        console.error('DraftAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי לנסח. נסה שוב.' };
    }
}

module.exports = { runDraftAgent };
