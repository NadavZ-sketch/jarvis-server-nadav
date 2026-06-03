/**
 * Weather source — Open-Meteo (free, keyless, no LLM).
 *
 * Replaces the old Gemini-Search-backed weather summary on the home screen's
 * "סביבה" card. Geocodes a city name → lat/lon, fetches the current conditions
 * + today's high/low + rain chance, and composes a short Hebrew summary locally.
 *
 * Two layers of in-process TTL cache (geocode rarely changes; forecast ~1h) keep
 * the home screen free of per-open network spam.
 */

const axios = require('axios');

const GEOCODE_URL  = 'https://geocoding-api.open-meteo.com/v1/search';
const FORECAST_URL = 'https://api.open-meteo.com/v1/forecast';
const DEFAULT_CITY = 'תל אביב';
const HTTP_TIMEOUT = 8000;

const TTL_GEOCODE  = 30 * 24 * 60 * 60 * 1000; // 30 d — a city's coordinates don't move
const TTL_FORECAST = 60 * 60 * 1000;           // 1 h — conditions change slowly

// ─── Tiny in-process TTL cache (self-contained, mirrors conversationSummary) ──
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

// ─── WMO weather code → Hebrew description + emoji ────────────────────────────
// https://open-meteo.com/en/docs (WW interpretation codes)
const WMO = {
    0:  ['בהיר', '☀️'],
    1:  ['בהיר ברובו', '🌤'],
    2:  ['מעונן חלקית', '⛅'],
    3:  ['מעונן', '☁️'],
    45: ['ערפילי', '🌫'],
    48: ['ערפל מתנקש', '🌫'],
    51: ['טפטוף קל', '🌦'],
    53: ['טפטוף', '🌦'],
    55: ['טפטוף חזק', '🌧'],
    56: ['טפטוף קופא', '🌧'],
    57: ['טפטוף קופא חזק', '🌧'],
    61: ['גשם קל', '🌦'],
    63: ['גשם', '🌧'],
    65: ['גשם חזק', '🌧'],
    66: ['גשם קופא', '🌧'],
    67: ['גשם קופא חזק', '🌧'],
    71: ['שלג קל', '🌨'],
    73: ['שלג', '🌨'],
    75: ['שלג כבד', '❄️'],
    77: ['גרגרי שלג', '🌨'],
    80: ['ממטרים קלים', '🌦'],
    81: ['ממטרים', '🌧'],
    82: ['ממטרים עזים', '⛈'],
    85: ['ממטרי שלג', '🌨'],
    86: ['ממטרי שלג כבדים', '❄️'],
    95: ['סופת רעמים', '⛈'],
    96: ['סופת רעמים עם ברד', '⛈'],
    99: ['סופת רעמים עם ברד כבד', '⛈'],
};

function _describe(code) {
    return WMO[code] || ['', '🌡'];
}

// A short, practical dressing hint based on temperature + rain chance.
function _advice(temp, rainChance) {
    if (rainChance >= 50) return 'קח מטרייה';
    if (temp <= 12) return 'כדאי מעיל';
    if (temp <= 18) return 'כדאי שכבה';
    if (temp >= 30) return 'שתה הרבה מים';
    return '';
}

/** Resolve a city name → { latitude, longitude, name } via Open-Meteo geocoding. */
async function geocode(city) {
    const key = `geo:${city}`;
    const cached = _cacheGet(key);
    if (cached !== undefined) return cached;

    const res = await axios.get(GEOCODE_URL, {
        params: { name: city, count: 1, language: 'he', country: 'IL' },
        timeout: HTTP_TIMEOUT,
    });
    const hit = res.data?.results?.[0];
    const loc = hit
        ? { latitude: hit.latitude, longitude: hit.longitude, name: hit.name || city }
        : null;
    _cacheSet(key, loc, TTL_GEOCODE);
    return loc;
}

/**
 * Returns a short Hebrew weather summary for [city], or null on failure.
 * Shape matches the old agent: { summary: string }.
 */
async function getWeatherSummary(city) {
    const target = (city && String(city).trim()) || DEFAULT_CITY;
    const cacheKey = `forecast:${target}`;
    const cached = _cacheGet(cacheKey);
    if (cached !== undefined) return cached;

    try {
        const loc = await geocode(target);
        if (!loc) { _cacheSet(cacheKey, null, TTL_FORECAST); return null; }

        const res = await axios.get(FORECAST_URL, {
            params: {
                latitude: loc.latitude,
                longitude: loc.longitude,
                current: 'temperature_2m,apparent_temperature,weather_code',
                daily: 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
                timezone: 'Asia/Jerusalem',
            },
            timeout: HTTP_TIMEOUT,
        });

        const cur  = res.data?.current || {};
        const day  = res.data?.daily   || {};
        const temp = Math.round(cur.temperature_2m);
        const code = cur.weather_code;
        const [desc, emoji] = _describe(code);
        const max  = Array.isArray(day.temperature_2m_max) ? Math.round(day.temperature_2m_max[0]) : null;
        const min  = Array.isArray(day.temperature_2m_min) ? Math.round(day.temperature_2m_min[0]) : null;
        const rain = Array.isArray(day.precipitation_probability_max) ? day.precipitation_probability_max[0] : null;

        const parts = [`${emoji} ${target}: ${temp}°`];
        if (desc) parts[0] += `, ${desc}`;
        if (max != null && min != null) parts.push(`מקס׳ ${max}°/מינ׳ ${min}°`);
        if (rain != null && rain > 0)   parts.push(`${rain}% גשם`);
        const advice = _advice(temp, rain || 0);
        let summary = parts.join(' · ');
        if (advice) summary += ` — ${advice}`;

        const data = { summary };
        _cacheSet(cacheKey, data, TTL_FORECAST);
        return data;
    } catch (err) {
        console.warn('⚠️ weatherSource failed:', err.message);
        return null; // caller omits the widget; do NOT cache transient errors
    }
}

module.exports = { getWeatherSummary, geocode, _describe };
