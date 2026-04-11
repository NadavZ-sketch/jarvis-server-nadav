require('dotenv').config();
const { callGemma4 } = require('./models');

const SAVE_PROMPT = `You are a memory manager. The user wants to save a personal fact about Nadav.
Create a concise memory statement with a context tag in brackets at the beginning.
Return ONLY a JSON object: {"memoryContent": "[context tag] the fact to remember"}

User message: `;

const RECALL_INTRO = `You are a memory recall assistant for Nadav. Given the user's question and stored memories, answer naturally in Hebrew.
If no relevant memories exist, say so politely.

Stored memories:
`;

async function runMemoryAgent(userMessage, supabase, useLocal = true) {
    try {
        const isRecall = /תזכיר|מה אתה יודע|מה זכרת|ספר לי עליי|מה שמרת/i.test(userMessage);

        if (isRecall) {
            const { data: memoriesData } = await supabase.from('memories').select('content');
            if (!memoriesData || memoriesData.length === 0) {
                return { answer: 'אין לי עדיין זיכרונות שמורים עליך נדב.' };
            }

            const memoriesList = memoriesData.map(m => `- ${m.content}`).join('\n');
            const fullPrompt = RECALL_INTRO + memoriesList + `\n\nשאלת הגולש: ${userMessage}`;

            const answer = await callGemma4(fullPrompt, useLocal);
            return { answer };
        }

        // Default: save a memory
        const aiText = await callGemma4(SAVE_PROMPT + userMessage, useLocal);

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
