require('dotenv').config();
const axios = require('axios');
const { GEMINI_25_URL } = require('./models');

function buildSystemPrompt(chatHistory, longTermMemories) {
    const now = new Date();
    const currentDate = now.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' });
    const currentDay = now.toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });
    const currentTime = now.toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit' });

    const historyString = chatHistory
        .map(msg => `${msg.role === 'user' ? 'Nadav' : 'Jarvis'}: ${msg.text}`)
        .join('\n');

    return `You are Jarvis, a personal AI assistant for Nadav. Respond naturally in Hebrew.
If an image is provided, analyze it carefully to answer the question.

--- Permanent Memories About Nadav ---
${longTermMemories}
--------------------------------------

Current DateTime: Today is ${currentDay}, ${currentDate}, local time is ${currentTime}.
User is Nadav, Mechanical Engineer.

--- Recent Conversation History ---
${historyString}
-----------------------------------

Current message from Nadav: `;
}

async function runChatAgent(userMessage, imageBase64, chatHistory, longTermMemories) {
    try {
        const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories);

        const parts = [{ text: systemPrompt + userMessage }];
        if (imageBase64) {
            parts.push({ inlineData: { data: imageBase64, mimeType: 'image/jpeg' } });
        }

        const requestBody = { contents: [{ parts }] };

        // Google Search only works without images (API constraint)
        if (!imageBase64) {
            requestBody.tools = [{ googleSearch: {} }];
        }

        const response = await axios.post(GEMINI_25_URL, requestBody);
        const responseParts = response.data.candidates[0].content.parts;
        const textPart = responseParts.find(p => typeof p.text === 'string' && p.text.trim().length > 0);
        const answer = textPart ? textPart.text.trim() : 'לא הצלחתי לגבש תשובה.';

        return { answer };

    } catch (err) {
        console.error('ChatAgent Error:', err.response ? JSON.stringify(err.response.data, null, 2) : err.message);
    }

    return { answer: 'סליחה נדב, נתקלתי בבעיה. נסה שוב.' };
}

module.exports = { runChatAgent };
