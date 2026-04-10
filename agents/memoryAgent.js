require('dotenv').config();
const axios = require('axios');

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=${process.env.GOOGLE_API_KEY}`;

const SAVE_PROMPT = `You are a memory manager. The user wants to save a personal fact about Nadav.
Create a concise memory statement with a context tag in brackets at the beginning.
Return ONLY a JSON object: {"memoryContent": "[context tag] the fact to remember"}

User message: `;

const RECALL_INTRO = `You are a memory recall assistant for Nadav. Given the user's question and stored memories, answer naturally in Hebrew.
If no relevant memories exist, say so politely.

Stored memories:
`;

async function runMemoryAgent(userMessage, supabase) {
    try {
        const isRecall = /תזכיר|מה אתה יודע|מה זכרת|ספר לי עליי|מה שמרת/i.test(userMessage);

        if (isRecall) {
            const { data: memoriesData } = await supabase.from('memories').select('content');
            if (!memoriesData || memoriesData.length === 0) {
                return { answer: 'אין לי עדיין זיכרונות שמורים עליך נדב.' };
            }

            const memoriesList = memoriesData.map(m => `- ${m.content}`).join('\n');
            const fullPrompt = RECALL_INTRO + memoriesList + `\n\nשאלת הגולש: ${userMessage}`;

            const response = await axios.post(GEMINI_URL, {
                contents: [{ parts: [{ text: fullPrompt }] }]
            });

            const answer = response.data.candidates[0].content.parts[0].text.trim();
            return { answer };
        }

        // Default: save a memory
        const response = await axios.post(GEMINI_URL, {
            contents: [{ parts: [{ text: SAVE_PROMPT + userMessage }] }]
        });

        let aiText = response.data.candidates[0].content.parts[0].text;
        const lastOpen = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');

        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in memory agent response');

        const parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        console.log('🧠 MemoryAgent saving:', parsed.memoryContent);

        await supabase.from('memories').insert([{ content: parsed.memoryContent }]);
        return { answer: `שמרתי לפניי: ${parsed.memoryContent}` };

    } catch (err) {
        console.error('MemoryAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בשמירת הזיכרון, נסה שוב.' };
}

module.exports = { runMemoryAgent };
