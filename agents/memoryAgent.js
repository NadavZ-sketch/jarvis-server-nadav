const { sanitizeLike } = require('./utils');
require('dotenv').config();
const { callGemma4 }   = require('./models');
const obsidianSync     = require('../services/obsidianSync');
const pinecone         = require('../services/pineconeMemory');

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
Given a user message and assistant reply, extract personal facts worth remembering.

Save facts in these categories:
- long_term: stable personal facts (health/allergy, family, location, job, hobby, preference, schedule)
- session: active goals, current tasks, decisions made this session, names of people/places just mentioned
- Do NOT save: questions, commands, greetings, weather queries, sports questions, or general non-personal content.

Return ONLY JSON (no explanation):
{"items": []} — if nothing worth saving
{"items": [{"content": "[tag] fact in Hebrew", "scope": "long_term|session"}]} — up to 3 items

Tags: health, location, family, work, hobby, preference, goal, decision, context, schedule, other
Scope: "long_term" for stable facts, "session" for current goals/tasks/decisions.

User message: `;

async function autoExtractMemory(userMessage, assistantAnswer, supabase, settings = {}) {
    try {
        if (!userMessage || userMessage.trim().length < 8) return;
        if (/מה אתה יודע|מה את יודעת|מה ידוע לך|יודע עליי|יודעת עליי|מה זכרת|ספר לי עליי|מה שמרת|מחק זיכרון|הסר זיכרון|שכח ש/i.test(userMessage)) return;

        const prompt = AUTO_EXTRACT_PROMPT + userMessage
            + `\nAssistant reply: ${(assistantAnswer || '').slice(0, 200)}`;

        const aiText = await callGemma4(
            [{ role: 'user', content: prompt }],
            settings.useLocalModel === true,
            300,
        );

        // Parse the first complete JSON object from the response.
        const firstOpen  = aiText.indexOf('{');
        const lastClose  = aiText.lastIndexOf('}');
        if (firstOpen === -1 || lastClose === -1) return;

        let parsed;
        try { parsed = JSON.parse(aiText.substring(firstOpen, lastClose + 1)); } catch { return; }

        const items = Array.isArray(parsed.items) ? parsed.items : [];
        if (items.length === 0) return;

        for (const item of items.slice(0, 3)) {
            const content = (item.content || '').trim();
            const scope   = item.scope === 'session' ? 'session' : 'long_term';
            if (!content) continue;

            if (await checkDuplicate(content, supabase)) {
                console.log('🧠 AutoExtract: duplicate skipped:', content);
                continue;
            }

            const { data: inserted } = await supabase
                .from('memories').insert([{ content, scope }]).select('id').limit(1);
            obsidianSync.dbToVault('memories', { content, scope });
            if (inserted?.[0]?.id) pinecone.upsertMemory(inserted[0].id, content).catch(() => {});
            console.log(`🧠 AutoExtract saved [${scope}]:`, content);
        }
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
        .select('id, content');

    if (error) throw error;
    if (!data || data.length === 0) return { answer: `לא מצאתי זיכרון על "${textToDelete}".` };
    // Remove from Pinecone as well
    await Promise.allSettled(data.map(m => pinecone.deleteMemory(m.id)));
    return { answer: `בסדר, מחקתי את הזיכרון: "${data[0].content}"` };
}

async function runMemoryAgent(userMessage, supabase, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';

    try {
        // Delete memory
        if (/מחק זיכרון|הסר זיכרון|שכח ש|שכח/i.test(userMessage)) {
            return deleteMemory(userMessage, supabase);
        }

        // Explicit save keywords — everything else in memoryAgent is a recall
        const isSave = /זכור ש|תזכור ש|שמור ש/i.test(userMessage);

        if (!isSave) {
            // Try Pinecone semantic search first; fall back to fetching all
            let memContents = await pinecone.searchMemories(userMessage, 15);
            if (!memContents) {
                const { data: memoriesData } = await supabase.from('memories').select('content');
                memContents = (memoriesData || []).map(m => m.content);
            }
            if (memContents.length === 0) {
                return { answer: `אין לי עדיין זיכרונות שמורים עליך ${userName}.` };
            }

            const memoriesList = memContents.map(c => `- ${c}`).join('\n');
            const fullPrompt = RECALL_INTRO + memoriesList + `\n\nשאלת הגולש: ${userMessage}`;

            const answer = await callGemma4(fullPrompt, useLocal);
            return { answer };
        }

        // Save a memory (explicit save keyword present)
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
        const { data: saved } = await supabase
            .from('memories').insert([{ content: parsed.memoryContent }]).select('id').limit(1);
        obsidianSync.dbToVault('memories', { content: parsed.memoryContent });
        if (saved?.[0]?.id) pinecone.upsertMemory(saved[0].id, parsed.memoryContent).catch(() => {});
        return { answer: `שמרתי לפניי: ${parsed.memoryContent}` };

    } catch (err) {
        console.error('MemoryAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בשמירת הזיכרון, נסה שוב.' };
}

module.exports = { runMemoryAgent, autoExtractMemory };
