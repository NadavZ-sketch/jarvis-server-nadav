/**
 * Contextual reference resolution.
 *
 * Short follow-up messages often contain anaphora ("תזכיר לי על זה מחר") that
 * specialist agents can't act on, because they only receive the raw message and
 * don't see the conversation. Before routing, we rewrite such a message into a
 * self-contained one using recent turns + the rolling summary, so the existing
 * agents handle it unchanged.
 *
 * shouldResolve() is a pure synchronous gate (one regex) so ordinary messages
 * pay nothing. Only when it returns true do we load history and call the LLM.
 */

require('dotenv').config();
const { callGemma4 } = require('../agents/models');

// Whole-word anaphora markers signalling a reference to earlier context.
const ANAPHORA = /(^|[\s,.!?])(זה|זו|זאת|הזה|הזו|הזאת|אותו|אותה|אותם|אותן|עליו|עליה|עליהם|עליהן|ההוא|ההיא|לזה|בזה|מזה)($|[\s,.!?])/;

const STOP = new Set(['של', 'את', 'עם', 'אני', 'זה', 'על', 'אל', 'לי', 'מה', 'גם', 'כן', 'לא', 'ו', 'ב', 'מ', 'ל']);

const RESOLVE_PROMPT = `אתה ממיר הודעות בעוזר אישי. קיבלת קטע מהשיחה האחרונה והודעה אחרונה של המשתמש שמכילה הפניה עמומה (כמו "זה", "אותו", "עליו").
שכתב את ההודעה האחרונה להודעה עצמאית ומלאה בעברית, שמחליפה את ההפניה בנושא הקונקרטי מההקשר, ושומרת על אותה כוונה ופעולה.
אם אי אפשר לפענח בוודאות את ההפניה — החזר את ההודעה בדיוק כפי שהיא.
החזר אך ורק את ההודעה הסופית, ללא הסברים וללא מרכאות.`;

function shouldResolve(userMessage) {
    if (!userMessage) return false;
    const msg = userMessage.trim();
    if (msg.length === 0 || msg.length >= 60) return false;
    return ANAPHORA.test(msg);
}

function _tokens(s) {
    return new Set(
        String(s).toLowerCase()
            .split(/[\s,.\-!?:;״׳"']+/)
            .filter(t => t.length > 1 && !STOP.has(t))
    );
}

async function resolveReferences(userMessage, chatHistory, chatSummary = '') {
    const original = (userMessage || '').trim();
    const fallback = { resolved: userMessage, didResolve: false };
    if (!Array.isArray(chatHistory) || chatHistory.length < 2) return fallback;

    let timer;
    try {
        const recent = chatHistory.slice(-4)
            .map(m => `${m.role === 'user' ? 'משתמש' : 'עוזר'}: ${String(m.text || '').slice(0, 200)}`)
            .join('\n');
        const summaryPart = chatSummary ? `\nסיכום השיחה: ${String(chatSummary).slice(0, 300)}` : '';
        const prompt = `${RESOLVE_PROMPT}${summaryPart}\n\nשיחה אחרונה:\n${recent}\n\nההודעה לשכתוב: ${original}`;

        const llmPromise = callGemma4([{ role: 'user', content: prompt }], false, 120);
        const timeoutPromise = new Promise(resolve => { timer = setTimeout(() => resolve(null), 2500); });
        const raw = await Promise.race([llmPromise, timeoutPromise]);

        const rewritten = (typeof raw === 'string' ? raw : (raw?.answer || raw?.content || ''))
            .trim()
            .replace(/^["'״]+/, '')
            .replace(/["'״]+$/, '')
            .trim();

        // Safety valves — never let resolution corrupt the user's intent.
        if (!rewritten || rewritten === original) return fallback;
        if (rewritten.length > original.length * 4) return fallback;
        const origTokens = _tokens(original);
        const newTokens = _tokens(rewritten);
        let overlap = 0;
        for (const t of origTokens) if (newTokens.has(t)) overlap++;
        if (origTokens.size > 0 && overlap === 0) return fallback;

        return { resolved: rewritten, didResolve: true };
    } catch (_) {
        return fallback;
    } finally {
        clearTimeout(timer);
    }
}

module.exports = { shouldResolve, resolveReferences };
