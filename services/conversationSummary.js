/**
 * Rolling conversation summary — keeps mid-term memory alive beyond the 20-message window.
 *
 * updateSummaryIfNeeded() is called fire-and-forget after every chat turn.
 * It runs only when enough new turns have accumulated since the last summary,
 * so in the common case (< 12 turns total) it does nothing.
 *
 * getSummary() is called at request time alongside loadChatHistory(); it is
 * fast because it uses a 60-second in-process TTL cache.
 */

const { callGemma4 } = require('../agents/models');

// In-process TTL cache keyed by chatId (60 seconds).
const _summaryCache = new Map();
const TTL_SUMMARY_MS = 60 * 1000;

function _cacheGet(chatId) {
    const entry = _summaryCache.get(chatId);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) { _summaryCache.delete(chatId); return undefined; }
    return entry.value;
}
function _cacheSet(chatId, value) {
    _summaryCache.set(chatId, { value, expiresAt: Date.now() + TTL_SUMMARY_MS });
}

// Minimum new turns since last summary before we re-run.
const MIN_NEW_TURNS = 4;
// Minimum total turns before we ever create a summary.
const MIN_TOTAL_TURNS = 12;

// Returns the true total message count for a chat, independent of the
// (capped) context window. Falls back to the window length if the count query
// fails, so the summary still advances rather than stalling.
async function _countTurns(chatId, repos, windowLength) {
    try {
        const count = await repos.chat.countForChat(chatId);
        if (typeof count === 'number') return count;
    } catch { /* fall through */ }
    return windowLength;
}

const SUMMARY_PROMPT = `אתה מנגנון זיכרון של עוזר אישי בשם ג'רביס.
קיבלת שיחה בין המשתמש לעוזר. הכן סיכום תמציתי **בעברית** שיעזור לעוזר להבין את הקונטקסט של ההמשך.
כלול: מטרות פעילות, החלטות שהתקבלו, נושאים שנדונו, מצב רגשי בולט (אם קיים).
אל תכלול ציטוטים ישירים — רק תוכן קונקרטי.
אורך מקסימלי: 600 תווים.
סיכום קודם (אם יש, אפשר לעדכן): `;

/**
 * Returns the current summary string for a chatId, or '' if none exists.
 * @param {string} chatId
 * @param {object} supabase - Supabase client
 * @returns {Promise<string>}
 */
async function getSummary(chatId, repos) {
    const cached = _cacheGet(chatId);
    if (cached !== undefined) return cached;

    const summary = await repos.summaries.get(chatId);
    _cacheSet(chatId, summary);
    return summary;
}

/**
 * Fire-and-forget: generates/updates a summary if enough turns have passed.
 * @param {string} chatId
 * @param {Array<{role:string, text:string}>} chatHistory - full recent history
 * @param {object} supabase
 * @param {object} [settings]
 */
async function updateSummaryIfNeeded(chatId, chatHistory, repos, settings = {}) {
    try {
        if (!chatHistory || chatHistory.length < MIN_TOTAL_TURNS) return;

        // Use the true conversation length (not the capped window) so summaries
        // keep advancing once the chat grows past the context window.
        const totalTurns = await _countTurns(chatId, repos, chatHistory.length);
        if (totalTurns < MIN_TOTAL_TURNS) return;

        // Check how many turns the existing summary already covers.
        const existing = await repos.summaries.getMeta(chatId);

        const covered = existing?.turns_covered ?? 0;
        if (totalTurns - covered < MIN_NEW_TURNS) return;

        const previousSummary = existing?.summary ?? '';

        // Build a condensed transcript of the uncovered turns (up to last 30 for context).
        const transcript = chatHistory
            .slice(Math.max(0, chatHistory.length - 30))
            .map(m => `${m.role === 'user' ? 'משתמש' : 'עוזר'}: ${m.text.slice(0, 300)}`)
            .join('\n');

        const prompt = SUMMARY_PROMPT + (previousSummary || 'אין') + `\n\nשיחה:\n${transcript}`;

        const raw = await callGemma4(
            [{ role: 'user', content: prompt }],
            settings.useLocalModel === true,
            400,
        );

        const summary = (raw || '').trim().slice(0, 600);
        if (!summary) return;

        await repos.summaries.upsert({
            chat_id:       chatId,
            summary,
            topics:        [],
            turns_covered: totalTurns,
            updated_at:    new Date().toISOString(),
        });

        _cacheSet(chatId, summary);
        console.log(`📝 ConvSummary updated for ${chatId.slice(0, 20)} (${totalTurns} turns)`);
    } catch (err) {
        console.error('ConvSummary error (suppressed):', err.message);
    }
}

module.exports = { getSummary, updateSummaryIfNeeded };
