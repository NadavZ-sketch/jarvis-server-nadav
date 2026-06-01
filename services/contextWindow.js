/**
 * Context window selection — keeps the chat history sent to the model within a
 * token budget instead of a fixed message count, so short messages give more
 * continuity and long ones don't blow the budget.
 *
 * Token estimation is deliberately rough and provider-agnostic: Hebrew text
 * averages ~3 characters per token, so we divide character length by 3 and add
 * a small per-message overhead for role framing. This intentionally
 * over-estimates slightly, keeping us safely under the real budget.
 */

const CHARS_PER_TOKEN = 3;
const PER_MESSAGE_OVERHEAD = 4;

/** Rough token estimate for a single piece of text. */
function estimateTokens(text) {
    if (!text) return 0;
    return Math.ceil(String(text).length / CHARS_PER_TOKEN) + PER_MESSAGE_OVERHEAD;
}

/**
 * Returns the most recent slice of `messages` that fits within both a token
 * budget and a hard message cap. Order is preserved (oldest → newest); trimming
 * always drops the oldest messages first so the latest turns are never lost.
 *
 * @param {Array<{role:string, text:string}>} messages - chronological history
 * @param {object} [opts]
 * @param {number} [opts.maxTokens=2000]   - approximate token budget
 * @param {number} [opts.maxMessages=40]   - hard upper bound on message count
 * @returns {Array} the retained tail of `messages`
 */
function selectByTokenBudget(messages, opts = {}) {
    if (!Array.isArray(messages) || messages.length === 0) return messages || [];
    const maxTokens = opts.maxTokens ?? 2000;
    const maxMessages = opts.maxMessages ?? 40;

    const kept = [];
    let total = 0;
    // Walk newest → oldest, accumulating until a limit is hit.
    for (let i = messages.length - 1; i >= 0; i--) {
        const cost = estimateTokens(messages[i].text);
        if (kept.length >= maxMessages) break;
        // Always keep at least the most recent message, even if it alone is huge.
        if (kept.length > 0 && total + cost > maxTokens) break;
        kept.push(messages[i]);
        total += cost;
    }
    return kept.reverse();
}

module.exports = { estimateTokens, selectByTokenBudget };
