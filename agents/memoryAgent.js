const { sanitizeLike } = require('./utils');
require('dotenv').config();
const { callGemma4 } = require('./models');
const obsidianSync   = require('../services/obsidianSync');

function buildSavePrompt(userName) {
    return `You are a memory manager. The user wants to save a personal fact about ${userName}.
Create a concise memory statement with a context tag in brackets at the beginning.
Return ONLY a JSON object: {"memoryContent": "[context tag] the fact to remember"}

User message: `;
}

// ─── Deduplication ────────────────────────────────────────────────────────────

async function checkDuplicate(rawContent, supabase) {
    const core = rawContent.replace(/^\[[^\]]+\]\s*/, '').trim();
    if (!core) return false;
    const { data } = await supabase
        .from('memories')
        .select('content')
        .ilike('content', `%${sanitizeLike(core.slice(0, 40))}%`)
        .limit(1);
    return !!(data && data.length > 0);
}

// ─── Passive auto-extraction (fire-and-forget) ────────────────────────────────

const AUTO_EXTRACT_PROMPT = `You are a memory extractor for a Hebrew personal assistant.
Given a user message and assistant reply, decide if the user revealed a personal fact worth remembering.
Personal facts worth saving: allergies, medical conditions, residence, family members,
job/occupation, hobbies, preferences, dislikes, goals, regular schedules.
NOT worth saving: questions, commands, greetings, weather queries, sports questions,
or anything that is NOT about the user personally.
Return ONLY JSON (no explanation):
{"memoryContent": ""} — if nothing worth saving
{"memoryContent": "[tag] fact in Hebrew"} — if there is a personal fact
Tags: health, location, family, work, hobby, preference, goal, schedule, other
User message: `;

async function autoExtractMemory(userMessage, assistantAnswer, supabase, settings = {}) {
    try {
        if (!userMessage || userMessage.trim().length < 8) return;

        const prompt = AUTO_EXTRACT_PROMPT + userMessage
            + `\nAssistant reply: ${(assistantAnswer || '').slice(0, 200)}`;

        const aiText = await callGemma4(
            [{ role: 'user', content: prompt }],
            settings.useLocalModel === true
        );

        const lastOpen  = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');
        if (lastOpen === -1 || lastClose === -1) return;

        let parsed;
        try { parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1)); } catch { return; }

        const content = (parsed.memoryContent || '').trim();
        if (!content) return;

        if (await checkDuplicate(content, supabase)) {
            console.log('🧠 AutoExtract: duplicate skipped:', content);
            return;
        }

        await supabase.from('memories').insert([{ content }]);
        obsidianSync.dbToVault('memories', { content });
        console.log('🧠 AutoExtract saved:', content);
    } catch (err) {
        console.error('AutoExtract error (suppressed):', err.message);
    }
}

const RECALL_INTRO = `You are a memory recall assistant. Given the user's question and stored memories, answer naturally in Hebrew.
If no relevant memories exist, say so politely.

Stored memories:
`;

async function deleteMemory(userMessage, supabase) {
    const textToDelete = userMessage
        .replace(/מחק זיכרון|הסר זיכרון|שכח ש|שכח/g, '')
        .replace(/(?<!\S)(על|את|ה)(?!\S)/g, '')
        .trim();

    if (!textToDelete) {
        return { answer: 'מה למחוק? נסה: "מחק זיכרון על [נושא]"' };
    }

    const { data, error } = await supabase
        .from('memories')
        .delete()
        .ilike('content', `%${textToDelete}%`)
        .select();

    if (error) throw error;
    if (!data || data.length === 0) return { answer: `לא מצאתי זיכרון על "${textToDelete}".` };
    return { answer: `בסדר, מחקתי את הזיכרון: "${data[0].content}"` };
}

async function runMemoryAgent(userMessage, supabase, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';

    try {
        // Delete memory
        if (/מחק זיכרון|הסר זיכרון|שכח ש|שכח/i.test(userMessage)) {
            return deleteMemory(userMessage, supabase);
        }

        const isRecall = /תזכיר|מה אתה יודע|מה זכרת|ספר לי עליי|מה שמרת/i.test(userMessage);

        if (isRecall) {
            const { data: memoriesData } = await supabase.from('memories').select('content');
            if (!memoriesData || memoriesData.length === 0) {
                return { answer: `אין לי עדיין זיכרונות שמורים עליך ${userName}.` };
            }

            const memoriesList = memoriesData.map(m => `- ${m.content}`).join('\n');
            const fullPrompt = RECALL_INTRO + memoriesList + `\n\nשאלת הגולש: ${userMessage}`;

            const answer = await callGemma4(fullPrompt, useLocal);
            return { answer };
        }

        // Default: save a memory
        const aiText = await callGemma4(buildSavePrompt(userName) + userMessage, useLocal);

        const lastOpen = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');

        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in memory agent response');

        let parsed;
        try {
            parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        } catch {
            return { answer: 'לא הצלחתי לעבד את הבקשה, נסה לנסח אחרת.' };
        }
        const isDuplicate = await checkDuplicate(parsed.memoryContent, supabase);
        if (isDuplicate) {
            console.log('🧠 MemoryAgent: duplicate skipped:', parsed.memoryContent);
            return { answer: `כבר יש לי זיכרון דומה: "${parsed.memoryContent}"` };
        }

        console.log('🧠 MemoryAgent saving:', parsed.memoryContent);
        await supabase.from('memories').insert([{ content: parsed.memoryContent }]);
        obsidianSync.dbToVault('memories', { content: parsed.memoryContent });
        return { answer: `שמרתי לפניי: ${parsed.memoryContent}` };

    } catch (err) {
        console.error('MemoryAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בשמירת הזיכרון, נסה שוב.' };
}

module.exports = { runMemoryAgent, autoExtractMemory };
