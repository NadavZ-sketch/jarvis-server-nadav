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

// Cache invalidation hook installed by server.js so memory writes immediately
// reflect in subsequent reads (no more 5-minute staleness).
let _invalidateMemoryCache = () => {};
function setMemoryCacheInvalidator(fn) {
    if (typeof fn === 'function') _invalidateMemoryCache = fn;
}

/**
 * Check if `rawContent` is a duplicate of an existing memory.
 * Semantic check via Pinecone (cosine >= 0.92) when available;
 * falls back to substring ilike on the first 40 chars of the core.
 * Returns:
 *   - { duplicate: true,  existingId?: string } if a near-duplicate exists
 *   - { duplicate: false } otherwise
 */
async function checkDuplicate(rawContent, supabase) {
    const core = rawContent.replace(/^\[[^\]]+\]\s*/, '').trim();
    if (!core) return { duplicate: false };

    // Semantic check (preferred)
    const similar = await pinecone.findSimilarMemory(rawContent, 0.92);
    if (similar) {
        return { duplicate: true, existingId: similar.id };
    }

    // Substring fallback — only when Pinecone returned null (unavailable).
    // If Pinecone returned no match, trust it and do NOT fall back to substring,
    // since substring on first 40 chars produces false positives across distinct facts
    // with the same prefix (e.g. "[location] גר ב..." × N cities).
    if (pinecone.isReady()) return { duplicate: false };

    const { data } = await supabase
        .from('memories')
        .select('id')
        .ilike('content', `%${sanitizeLike(core.slice(0, 40))}%`)
        .limit(1);
    if (data && data.length > 0) {
        return { duplicate: true, existingId: String(data[0].id) };
    }
    return { duplicate: false };
}

// Retry wrapper: exponential backoff up to N attempts. Returns the resolved value
// or rethrows the last error. Used for LLM calls in auto-extraction so transient
// network/rate-limit failures don't silently lose extracted facts.
async function withRetry(fn, { attempts = 2, baseMs = 400 } = {}) {
    let lastErr;
    for (let i = 0; i <= attempts; i++) {
        try { return await fn(); }
        catch (err) {
            lastErr = err;
            if (i === attempts) break;
            await new Promise(r => setTimeout(r, baseMs * Math.pow(2, i)));
        }
    }
    throw lastErr;
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
        // Skip extraction on short/filler messages — nothing memorable in "תודה" or "יאלה".
        if (!userMessage || userMessage.trim().length < 30) return null;
        if (/מה אתה יודע|מה את יודעת|מה ידוע לך|יודע עליי|יודעת עליי|מה זכרת|ספר לי עליי|מה שמרת|מחק זיכרון|הסר זיכרון|שכח ש|מזג האוויר|תחזית|חדשות|כותרות|ספורט|תוצאות|מניות|שוק המניות|שוק|מניה/i.test(userMessage)) return null;

        const prompt = AUTO_EXTRACT_PROMPT + userMessage
            + `\nAssistant reply: ${(assistantAnswer || '').slice(0, 200)}`;

        const aiText = await withRetry(() => callGemma4(
            [{ role: 'user', content: prompt }],
            settings.useLocalModel === true,
            300,
        ));

        // Parse the first complete JSON object from the response.
        const firstOpen  = aiText.indexOf('{');
        const lastClose  = aiText.lastIndexOf('}');
        if (firstOpen === -1 || lastClose === -1) return null;

        let parsed;
        try { parsed = JSON.parse(aiText.substring(firstOpen, lastClose + 1)); } catch { return null; }

        const items = Array.isArray(parsed.items) ? parsed.items : [];
        if (items.length === 0) return null;

        let firstSaved = null;
        for (const item of items.slice(0, 3)) {
            const content = (item.content || '').trim();
            const scope   = item.scope === 'session' ? 'session' : 'long_term';
            if (!content) continue;

            const dup = await checkDuplicate(content, supabase);
            if (dup.duplicate) {
                console.log('🧠 AutoExtract: duplicate skipped:', content);
                continue;
            }

            const { data: inserted } = await supabase
                .from('memories').insert([{ content, scope }]).select('id').limit(1);
            obsidianSync.dbToVault('memories', { content, scope });
            if (inserted?.[0]?.id) pinecone.upsertMemory(inserted[0].id, content).catch(() => {});
            if (!firstSaved) firstSaved = content;
            console.log(`🧠 AutoExtract saved [${scope}]:`, content);
        }
        if (firstSaved) _invalidateMemoryCache();
        return firstSaved;
    } catch (err) {
        console.error('AutoExtract error (suppressed):', err.message);
        return null;
    }
}

const RECALL_INTRO = `You are a memory recall assistant. Given the user's question and stored memories, answer naturally in Hebrew.
If no relevant memories exist, say so politely.

Stored memories:
`;

const UPDATE_PROMPT = (userName) =>
    `You are a memory manager. The user wants to update a saved personal fact about ${userName}.
Extract the new fact to store. Return ONLY JSON: {"newContent": "[context tag] the updated fact"}

User message: `;

async function deleteMemory(userMessage, supabase) {
    const textToDelete = userMessage
        .replace(/מחק\s+(?:את\s+)?(?:ה)?זיכרון|הסר\s+(?:את\s+)?(?:ה)?זיכרון|שכח\s+ש|שכח|תמחק|תסיר/gi, '')
        .replace(/(?<!\S)(?:לגבי|בנוגע\s+ל|על|את|של|ה|ו|ב|מ|ל|ש|כ)(?!\S)/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();

    if (!textToDelete) {
        return { answer: 'מה למחוק? נסה: "מחק זיכרון על [נושא]"' };
    }

    const { data, error } = await supabase
        .from('memories')
        .delete()
        .ilike('content', `%${sanitizeLike(textToDelete)}%`)
        .select('id, content');

    if (error) throw error;
    if (!data || data.length === 0) return { answer: `לא מצאתי זיכרון על "${textToDelete}".` };
    await Promise.allSettled(data.map(m => pinecone.deleteMemory(m.id)));
    data.forEach(m => obsidianSync.removeFromVault('memories', m));
    _invalidateMemoryCache();
    return { answer: `בסדר, מחקתי את הזיכרון: "${data[0].content}"` };
}

async function updateMemory(userMessage, supabase, useLocal, settings = {}) {
    const userName = settings.userName || 'נדב';

    // Extract the keyword used and the search term from the message
    const searchText = userMessage
        .replace(/עדכן\s+(?:את\s+)?(?:ה)?זיכרון|שנה\s+(?:את\s+)?(?:ה)?זיכרון|תעדכן|עדכן|שנה/gi, '')
        .replace(/(?<!\S)(?:לגבי|בנוגע\s+ל|על|את|של|ה|ו|ב|מ|ל|ש|כ)(?!\S)/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();

    if (!searchText) {
        return { answer: 'מה לעדכן? נסה: "עדכן זיכרון על [נושא] ל[ערך חדש]"' };
    }

    // Find the existing memory row to update
    const { data: existing, error: findErr } = await supabase
        .from('memories')
        .select('id, content')
        .ilike('content', `%${sanitizeLike(searchText.slice(0, 50))}%`)
        .limit(1);

    if (findErr) throw findErr;
    if (!existing || existing.length === 0) {
        return { answer: `לא מצאתי זיכרון תואם ל"${searchText}". נסה לנסח אחרת.` };
    }

    const row = existing[0];

    // Ask LLM to generate the updated content
    const aiText = await callGemma4(UPDATE_PROMPT(userName) + userMessage, useLocal);
    const firstOpen = aiText.indexOf('{');
    const lastClose = aiText.lastIndexOf('}');
    if (firstOpen === -1 || lastClose === -1) {
        return { answer: 'לא הצלחתי לפרש את העדכון, נסה לנסח אחרת.' };
    }

    let parsed;
    try {
        parsed = JSON.parse(aiText.substring(firstOpen, lastClose + 1));
    } catch {
        return { answer: 'לא הצלחתי לפרש את העדכון, נסה לנסח אחרת.' };
    }

    const newContent = (parsed.newContent || '').trim();
    if (!newContent) return { answer: 'לא הצלחתי לחלץ את הזיכרון המעודכן.' };

    const { error: updateErr } = await supabase
        .from('memories')
        .update({ content: newContent })
        .eq('id', row.id);

    if (updateErr) throw updateErr;

    // Re-embed the updated content in Pinecone
    pinecone.upsertMemory(row.id, newContent).catch(() => {});
    obsidianSync.dbToVault('memories', { content: newContent });
    _invalidateMemoryCache();

    return { answer: `עדכנתי את הזיכרון:\nלפני: "${row.content}"\nאחרי: "${newContent}"` };
}

async function runMemoryAgent(userMessage, supabase, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';

    try {
        // Update memory
        if (/עדכן|שנה|תעדכן/i.test(userMessage) && /זיכרון|זכור|זכרון/i.test(userMessage)) {
            return updateMemory(userMessage, supabase, useLocal, settings);
        }

        // Delete memory
        if (/מחק|הסר|שכח|תמחק|תסיר/i.test(userMessage) && /זיכרון|זכור|זכרון|שכח/i.test(userMessage) ||
            /מחק\s+(?:את\s+)?(?:ה)?זיכרון|הסר\s+(?:את\s+)?(?:ה)?זיכרון|שכח\s+ש|שכח/i.test(userMessage)) {
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

        const lastOpen = aiText.indexOf('{');
        const lastClose = aiText.lastIndexOf('}');

        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in memory agent response');

        let parsed;
        try {
            parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        } catch {
            return { answer: 'לא הצלחתי לעבד את הבקשה, נסה לנסח אחרת.' };
        }
        const dup = await checkDuplicate(parsed.memoryContent, supabase);
        if (dup.duplicate) {
            console.log('🧠 MemoryAgent: duplicate skipped:', parsed.memoryContent);
            return { answer: `כבר יש לי זיכרון דומה. אם תרצה לעדכן אותו אמור: "עדכן זיכרון על ${parsed.memoryContent}"` };
        }

        console.log('🧠 MemoryAgent saving:', parsed.memoryContent);
        const { data: saved } = await supabase
            .from('memories').insert([{ content: parsed.memoryContent, scope: 'long_term' }]).select('id').limit(1);
        obsidianSync.dbToVault('memories', { content: parsed.memoryContent, scope: 'long_term' });
        if (saved?.[0]?.id) pinecone.upsertMemory(saved[0].id, parsed.memoryContent).catch(() => {});
        _invalidateMemoryCache();
        return { answer: `שמרתי לפניי: ${parsed.memoryContent}` };

    } catch (err) {
        console.error('MemoryAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בשמירת הזיכרון, נסה שוב.' };
}

module.exports = { runMemoryAgent, autoExtractMemory, checkDuplicate, setMemoryCacheInvalidator, deleteMemory, updateMemory };
