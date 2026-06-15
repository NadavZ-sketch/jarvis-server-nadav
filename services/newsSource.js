/**
 * News source — Google News RSS (free, keyless, no LLM).
 *
 * Replaces the old Gemini-Search-backed news summary on the home screen's
 * "סביבה" card. Fetches the Hebrew Google News feed, extracts the top headlines
 * with a light regex (no XML dependency), and returns them as a short summary.
 */

const axios = require('axios');

const RSS_URL = 'https://news.google.com/rss?hl=he&gl=IL&ceid=IL:he';
const HTTP_TIMEOUT = 8000;
const TTL_NEWS = 60 * 60 * 1000; // 1 h — headlines stay relevant for an hour
const MAX_HEADLINES = 4;

const _cache = new Map();
function _cacheGet(key) {
    const e = _cache.get(key);
    if (!e) return undefined;
    if (Date.now() > e.expiresAt) { _cache.delete(key); return undefined; }
    return e.value;
}
function _cacheSet(key, value, ttl) {
    _cache.set(key, { value, expiresAt: Date.now() + ttl });
}

// Decode the handful of XML entities that show up in RSS titles.
function _decodeEntities(s) {
    return s
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'")
        .replace(/&apos;/g, "'");
}

// Google News titles end with " - <source>"; trim the source for a cleaner line.
function _stripSource(title) {
    return title.replace(/\s+-\s+[^-]+$/, '').trim();
}

/**
 * Parses raw RSS XML → array of headline strings (top [limit]).
 * Exported for unit testing without a network round-trip.
 */
function parseHeadlines(xml, limit = MAX_HEADLINES) {
    if (!xml || typeof xml !== 'string') return [];
    const items = xml.split('<item>').slice(1); // drop the channel header
    const titles = [];
    for (const item of items) {
        // Title may be wrapped in CDATA or plain text.
        const m = item.match(/<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/);
        if (!m) continue;
        const clean = _stripSource(_decodeEntities(m[1].trim()));
        if (clean) titles.push(clean);
        if (titles.length >= limit) break;
    }
    return titles;
}

/**
 * Returns a short Hebrew news summary, or null on failure.
 * Shape matches the old agent: { summary: string, headlines: string[] }.
 */
async function getNewsSummary() {
    const cacheKey = 'news:il:he';
    const cached = _cacheGet(cacheKey);
    if (cached !== undefined) return cached;

    try {
        const res = await axios.get(RSS_URL, {
            timeout: HTTP_TIMEOUT,
            headers: { 'User-Agent': 'Mozilla/5.0 (Jarvis/1.0)' },
            responseType: 'text',
        });
        const headlines = parseHeadlines(res.data, MAX_HEADLINES);
        if (headlines.length === 0) { _cacheSet(cacheKey, null, TTL_NEWS); return null; }

        const data = { summary: headlines.map(h => `• ${h}`).join('\n'), headlines };
        _cacheSet(cacheKey, data, TTL_NEWS);
        return data;
    } catch (err) {
        console.warn('⚠️ newsSource failed:', err.message);
        return null; // caller omits the widget; do NOT cache transient errors
    }
}

const TOPIC_RSS_BASE = 'https://news.google.com/rss/search';

/**
 * Fetches headlines for a specific topic using Google News RSS search.
 * @param {string} topic - Hebrew search string (e.g., 'ספורט ישראל')
 * @param {number} maxItems - max headlines to return (default 4)
 * @returns {{ headlines: string[] } | null}
 */
async function getTopicHeadlines(topic, maxItems = MAX_HEADLINES) {
    const cacheKey = `news:topic:${topic}`;
    const cached = _cacheGet(cacheKey);
    if (cached !== undefined) return cached;

    try {
        const url = `${TOPIC_RSS_BASE}?q=${encodeURIComponent(topic)}&hl=he&gl=IL&ceid=IL:he`;
        const res = await axios.get(url, {
            timeout: HTTP_TIMEOUT,
            headers: { 'User-Agent': 'Mozilla/5.0 (Jarvis/1.0)' },
            responseType: 'text',
        });
        const headlines = parseHeadlines(res.data, maxItems);
        if (headlines.length === 0) { _cacheSet(cacheKey, null, TTL_NEWS); return null; }
        const data = { headlines };
        _cacheSet(cacheKey, data, TTL_NEWS);
        return data;
    } catch (err) {
        console.warn(`⚠️ newsSource.getTopicHeadlines(${topic}) failed:`, err.message);
        return null;
    }
}

module.exports = { getNewsSummary, parseHeadlines, getTopicHeadlines };
