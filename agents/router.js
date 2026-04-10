require('dotenv').config();
const axios = require('axios');

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${process.env.GOOGLE_API_KEY}`;

const CLASSIFY_PROMPT = `You are an intent classifier. Given a Hebrew or English user message, classify it into exactly one of these four categories:

- task: adding, listing, checking, deleting, or completing tasks or todo items
- memory: saving personal information, facts about the user, or things to remember about Nadav
- sports: any question about football, soccer, Premier League, EPL, matches, scores, standings, fixtures, teams, or players
- chat: everything else including weather, general questions, conversation, advice, image analysis

Reply with ONLY the single lowercase word. No punctuation, no explanation.

User message: `;

async function classifyIntent(userMessage) {
    try {
        const response = await axios.post(GEMINI_URL, {
            contents: [{ parts: [{ text: CLASSIFY_PROMPT + userMessage }] }]
        });

        const aiText = response.data.candidates[0].content.parts[0].text;
        const raw = aiText.trim().toLowerCase().replace(/[^a-z]/g, '');
        const valid = ['task', 'memory', 'chat', 'sports'];

        const intent = valid.includes(raw) ? raw : 'chat';
        console.log(`🧭 Router: "${intent}" ← "${userMessage.slice(0, 50)}"`);
        return intent;

    } catch (err) {
        console.error('Router Error:', err.message);
        return 'chat';
    }
}

module.exports = { classifyIntent };
