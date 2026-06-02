'use strict';

/**
 * In-process record of the last routing decision per chat, so explicit feedback
 * (👍/👎) can be linked back to the intent that produced the reply. This makes
 * systematic mis-routes visible: a 👎 on a reply whose intent was, say, "weather"
 * when the user wanted "news" is far more useful than a 👎 with no routing context.
 *
 * Deliberately tiny and ephemeral — a short-TTL Map, no persistence. If the entry
 * has expired or never existed, callers simply get null and carry on.
 */

const _last = new Map(); // chatId -> { intent, mode, at }
const TTL_MS = 10 * 60 * 1000;
const MAX_ENTRIES = 1000;

function setLastRoute(chatId, info = {}) {
    if (!chatId) return;
    if (_last.size >= MAX_ENTRIES) {
        // Drop the oldest inserted entry (Map preserves insertion order).
        _last.delete(_last.keys().next().value);
    }
    _last.set(String(chatId), { intent: info.intent, mode: info.mode, at: Date.now() });
}

function getLastRoute(chatId) {
    if (!chatId) return null;
    const entry = _last.get(String(chatId));
    if (!entry) return null;
    if (Date.now() - entry.at > TTL_MS) { _last.delete(String(chatId)); return null; }
    return { intent: entry.intent, mode: entry.mode };
}

module.exports = { setLastRoute, getLastRoute };
