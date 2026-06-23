require('dotenv').config();
const { callGemma4 }   = require('./models');
const obsidianSync     = require('../services/obsidianSync');
const pinecone         = require('../services/pineconeMemory');
const memoryContext    = require('../services/memoryContext');

function buildSavePrompt(userName) {
    return `You are a memory manager. The user wants to save a personal fact about ${userName}.
Create a concise memory statement with a context tag in brackets at the beginning.
Return ONLY a JSON object: {"memoryContent": "[context tag] the fact to remember"}

User message: `;
}

// ─── Deduplication ────────────────────────────────────────────────────────────

// Delegate to memoryContext so all callers share the same cache.
function _invalidateMemoryCache() { memoryContext.invalidateCache(); }
// Kept for backward compatibility with existing test mocks.
function setMemoryCacheInvalidator(_fn) { /* no-op: invalidation owned by memoryContext */ }

/**
 * Check if `rawContent` is a duplicate of an existing memory.
 * Semantic check via Pinecone (cosine >= 0.92) when available;
 * falls back to substring ilike on the first 40 chars of the core.
 * Returns:
 *   - { duplicate: true,  existingId?: string } if a near-duplicate exists
 *   - { duplicate: false } otherwise
 */
async function checkDuplicate(rawContent, memories) {
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

    const data = await memories.findByContent(core.slice(0, 40), { columns: 'id', limit: 1 });
    if (data && data.length > 0) {
        return { duplicate: true, existingId: String(data[0].id) };
    }
    return { duplicate: false };
}

async function findConflict(content) {
    if (!pinecone.isReady()) return { type: 'new' };
    const similar = await pinecone.findSimilarMemory(content, 0.70);
    if (!similar) return { type: 'new' };
    if (similar.score > 0.92) return { type: 'duplicate' };
    return { type: 'update', existingId: similar.id, existingContent: similar.content, score: similar.score };
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

// ─── Pending TTL cache (delegated to memoryContext) ───────────────────────────
// These wrappers keep existing test spies on memoryAgent working.

function getPendingMemory(chatId) { return memoryContext.getPending(chatId); }
function clearPendingMemory(chatId) { return memoryContext.clearPending(chatId); }

// ─── Passive auto-extraction (fire-and-forget) ────────────────────────────────

const AUTO_EXTRACT_PROMPT = `אתה מנתח שיחה ומחלץ עובדות אישיות חשובות לשמירה.

הודעת המשתמש: "{message}"
תגובת העוזר: "{answer}"

חלץ עד 3 פריטי מידע בעלי ערך לזיכרון ארוך טווח.
סווג כל פריט לאחת מהקטגוריות:
- [fact]: עובדה יציבה — משפחה, מקום מגורים, בריאות, עבודה, גיל
- [pref]: העדפה או דפוס התנהגות — מה אוהב, איך עובד, שגרת יום
- [context]: הקשר פעיל — פרויקט עכשווי, החלטה השבוע, מטרה קרובה

החזר JSON בלבד:
{ "memories": [ { "type": "fact|pref|context", "content": "[tag] תוכן בעברית" } ] }

כללים:
- רק מידע אישי ספציפי (לא שאלות כלליות)
- משפט אחד קצר לכל פריט
- אם אין מידע ראוי — החזר { "memories": [] }`;

async function autoExtractMemory(userMessage, assistantAnswer, repos, settings = {}, chatId = null) {
    const memories = repos.memories;
    try {
        if (!userMessage || userMessage.trim().length < 20) return null;
        if (/מזג האוויר|תחזית|חדשות|כותרות|ספורט|תוצאות|מניות|שוק המניות|מה אתה יודע|מה ידוע לך|מחק זיכרון|הסר זיכרון/i.test(userMessage)) return null;

        const prompt = AUTO_EXTRACT_PROMPT
            .replace('{message}', userMessage)
            .replace('{answer}', (assistantAnswer || '').slice(0, 200));

        const aiText = await withRetry(() => callGemma4(
            [{ role: 'user', content: prompt }],
            settings.useLocalModel === true,
            400,
        ));

        const firstOpen = aiText.indexOf('{');
        const lastClose = aiText.lastIndexOf('}');
        if (firstOpen === -1 || lastClose === -1) return null;

        let parsed;
        try { parsed = JSON.parse(aiText.substring(firstOpen, lastClose + 1)); } catch { return null; }

        const items = Array.isArray(parsed.memories) ? parsed.memories : [];
        if (items.length === 0) return null;

        for (const item of items.slice(0, 3)) {
            const content = (item.content || '').trim();
            const type    = item.type || 'fact';
            if (!content) continue;

            if (type === 'context') {
                const dup = await checkDuplicate(content, memories);
                if (dup.duplicate) continue;
                const inserted = await memories.insert({ content, scope: 'session' });
                obsidianSync.dbToVault('memories', { content, scope: 'session' });
                if (inserted?.[0]?.id) pinecone.upsertMemory(inserted[0].id, content).catch(() => {});
                console.log('🧠 AutoExtract [context] saved:', content);
                _invalidateMemoryCache();
                continue;
            }

            const conflict = await findConflict(content);
            if (conflict.type === 'duplicate') {
                console.log('🧠 AutoExtract: duplicate skipped:', content);
                continue;
            }

            if (chatId) {
                memoryContext.setPending(chatId, {
                    content, type, ...( conflict.type === 'update' && {
                        replacesId:      conflict.existingId,
                        replacesContent: conflict.existingContent,
                    }),
                });
                console.log(`🧠 AutoExtract: pending [${type}] for chatId ${chatId}:`, content);
                return { type: conflict.type, content, ...( conflict.type === 'update' && {
                    replacesId: conflict.existingId, replacesContent: conflict.existingContent,
                })};
            }
        }
        return null;
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

async function deleteMemory(userMessage, memories) {
    const textToDelete = userMessage
        .replace(/מחק\s+(?:את\s+)?(?:ה)?זיכרון|הסר\s+(?:את\s+)?(?:ה)?זיכרון|שכח\s+ש|שכח|תמחק|תסיר/gi, '')
        .replace(/(?<!\S)(?:לגבי|בנוגע\s+ל|על|את|של|ה|ו|ב|מ|ל|ש|כ)(?!\S)/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();

    if (!textToDelete) {
        return { answer: 'מה למחוק? נסה: "מחק זיכרון על [נושא]"' };
    }

    const data = await memories.deleteByContent(textToDelete);
    if (!data || data.length === 0) return { answer: `לא מצאתי זיכרון על "${textToDelete}".` };
    await Promise.allSettled(data.map(m => pinecone.deleteMemory(m.id)));
    data.forEach(m => obsidianSync.removeFromVault('memories', m));
    _invalidateMemoryCache();
    return { answer: `בסדר, מחקתי את הזיכרון: "${data[0].content}"` };
}

async function updateMemory(userMessage, memories, useLocal, settings = {}) {
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
    const existing = await memories.findByContent(searchText.slice(0, 50), { columns: 'id, content', limit: 1 });

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

    const { error: updateErr } = await memories.update(row.id, newContent);

    if (updateErr) throw updateErr;

    // Re-embed the updated content in Pinecone
    pinecone.upsertMemory(row.id, newContent).catch(() => {});
    obsidianSync.dbToVault('memories', { content: newContent });
    _invalidateMemoryCache();

    return { answer: `עדכנתי את הזיכרון:\nלפני: "${row.content}"\nאחרי: "${newContent}"` };
}

async function runMemoryAgent(userMessage, repos, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';
    const memories = repos.memories;

    try {
        // Update memory
        if (/עדכן|שנה|תעדכן/i.test(userMessage) && /זיכרון|זכור|זכרון/i.test(userMessage)) {
            return updateMemory(userMessage, memories, useLocal, settings);
        }

        // Delete memory
        if (/מחק|הסר|שכח|תמחק|תסיר/i.test(userMessage) && /זיכרון|זכור|זכרון|שכח/i.test(userMessage) ||
            /מחק\s+(?:את\s+)?(?:ה)?זיכרון|הסר\s+(?:את\s+)?(?:ה)?זיכרון|שכח\s+ש|שכח/i.test(userMessage)) {
            return deleteMemory(userMessage, memories);
        }

        // Explicit save keywords — everything else in memoryAgent is a recall
        const isSave = /זכור ש|תזכור ש|שמור ש/i.test(userMessage);

        if (!isSave) {
            // Try Pinecone semantic search first; fall back to fetching all
            let memContents = await pinecone.searchMemories(userMessage, 15);
            if (!memContents) {
                memContents = await memories.allContents();
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
        const dup = await checkDuplicate(parsed.memoryContent, memories);
        if (dup.duplicate) {
            console.log('🧠 MemoryAgent: duplicate skipped:', parsed.memoryContent);
            return { answer: `כבר יש לי זיכרון דומה. אם תרצה לעדכן אותו אמור: "עדכן זיכרון על ${parsed.memoryContent}"` };
        }

        console.log('🧠 MemoryAgent saving:', parsed.memoryContent);
        const saved = await memories.insert({ content: parsed.memoryContent, scope: 'long_term' });
        obsidianSync.dbToVault('memories', { content: parsed.memoryContent, scope: 'long_term' });
        if (saved?.[0]?.id) pinecone.upsertMemory(saved[0].id, parsed.memoryContent).catch(() => {});
        _invalidateMemoryCache();
        return { answer: `שמרתי לפניי: ${parsed.memoryContent}` };

    } catch (err) {
        console.error('MemoryAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בשמירת הזיכרון, נסה שוב.' };
}

async function saveSessionSummary(chatId, repos, history) {
    if (!history || history.length < 5) return;
    try {
        const turns = history.slice(-10)
            .map(m => `${m.sender === 'user' ? 'משתמש' : 'ג׳רביס'}: ${m.text}`)
            .join('\n');
        const prompt = `סכם בשני משפטים קצרים את נושאי השיחה הבאה (בעברית):\n${turns}\nהחזר רק את הסיכום, ללא הסברים.`;
        const summary = await callGemma4([{ role: 'user', content: prompt }], false, 200);
        if (!summary || summary.trim().length < 5) return;
        const content = `[context] ${summary.trim()}`;
        const inserted = await repos.memories.insert({ content, scope: 'session' });
        if (inserted?.[0]?.id) pinecone.upsertMemory(inserted[0].id, content).catch(() => {});
        _invalidateMemoryCache();
        console.log('🧠 Session summary saved for', chatId);
    } catch (err) {
        console.error('saveSessionSummary error (suppressed):', err.message);
    }
}

module.exports = {
    runMemoryAgent, autoExtractMemory, checkDuplicate, findConflict,
    getPendingMemory, clearPendingMemory, saveSessionSummary,
    setMemoryCacheInvalidator, deleteMemory, updateMemory,
};
