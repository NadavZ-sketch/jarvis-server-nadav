require('dotenv').config();
const axios = require('axios');
const { GEMINI_URL } = require('./models');

const PERSONALITY_DESC = {
    friendly:  'ידידותי, חם ונגיש. התאם את שפתך וסגנונך לדרך הדיבור של המשתמש.',
    formal:    'מקצועי ורשמי. שפה עניינית, מדויקת וענינית.',
    concise:   'קצר ולעניין בלבד. תשובות ישירות וממוקדות ללא מילות מילוי.',
    humorous:  'ידידותי עם חוש הומור קל, תוך שמירה על עזרה אמיתית ומועילה.',
};

function buildSystemPrompt(chatHistory, longTermMemories, settings = {}) {
    const now = new Date();
    const currentDate = now.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' });
    const currentDay  = now.toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });
    const currentTime = now.toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit' });

    const name        = settings.assistantName || 'Jarvis';
    const userName    = settings.userName      || 'נדב';
    const gender      = settings.gender        || 'male';
    const personality = settings.personality   || 'friendly';

    const genderInstr = gender === 'female'
        ? 'את עוזרת אישית. השתמשי תמיד בלשון נקבה.'
        : 'אתה עוזר אישי. השתמש תמיד בלשון זכר.';

    const personalityDesc = PERSONALITY_DESC[personality] || PERSONALITY_DESC.friendly;

    const historyString = chatHistory
        .map(msg => `${msg.role === 'user' ? userName : name}: ${msg.text}`)
        .join('\n');

    return `You are ${name}, a personal AI assistant for ${userName}. Respond in Hebrew only.
${genderInstr}
Personality: ${personalityDesc}
CRITICAL: Mirror ${userName}'s own writing style, vocabulary and tone in every response.

--- Permanent Memories About ${userName} ---
${longTermMemories}
--------------------------------------

Current DateTime: ${currentDay}, ${currentDate}, ${currentTime}.

--- Recent Conversation History ---
${historyString}
-----------------------------------

Current message from ${userName}: `;
}

async function runChatAgent(userMessage, imageBase64, chatHistory, longTermMemories, settings = {}) {
    try {
        const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings);

        const parts = [{ text: systemPrompt + userMessage }];
        if (imageBase64) {
            parts.push({ inlineData: { data: imageBase64, mimeType: 'image/jpeg' } });
        }

        const requestBody = { contents: [{ parts }] };

        if (!imageBase64) {
            requestBody.tools = [{ googleSearch: {} }];
        }

        const response = await axios.post(GEMINI_URL, requestBody);
        const responseParts = response.data.candidates[0].content.parts;
        const textPart = responseParts.find(p => typeof p.text === 'string' && p.text.trim().length > 0);
        const answer   = textPart ? textPart.text.trim() : 'לא הצלחתי לגבש תשובה.';

        return { answer };

    } catch (err) {
        console.error('ChatAgent Error:', err.response ? JSON.stringify(err.response.data, null, 2) : err.message);
    }

    return { answer: 'סליחה, נתקלתי בבעיה. נסה שוב.' };
}

module.exports = { runChatAgent };
