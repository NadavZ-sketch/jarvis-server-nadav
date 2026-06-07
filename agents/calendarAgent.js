require('dotenv').config();
const axios = require('axios');
const { callGemma4 } = require('./models');
const { nowJerusalem } = require('./utils');

const GOOGLE_AUTH_BASE = 'https://accounts.google.com/o/oauth2';
const CALENDAR_API = 'https://www.googleapis.com/calendar/v3';
const SCOPES = 'https://www.googleapis.com/auth/calendar';

// ─── Token helpers ─────────────────────────────────────────────────────────────

async function getStoredToken(supabase) {
    try {
        const { data } = await supabase
            .from('user_profiles')
            .select('google_calendar_token')
            .limit(1)
            .single();
        return data?.google_calendar_token || null;
    } catch {
        return null;
    }
}

async function refreshAccessToken(refreshToken) {
    const res = await axios.post('https://oauth2.googleapis.com/token', {
        client_id: process.env.GOOGLE_CLIENT_ID,
        client_secret: process.env.GOOGLE_CLIENT_SECRET,
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
    });
    return res.data.access_token;
}

async function getAccessToken(supabase) {
    const tokenData = await getStoredToken(supabase);
    if (!tokenData) return null;
    try {
        const parsed = typeof tokenData === 'string' ? JSON.parse(tokenData) : tokenData;
        if (!parsed.refresh_token) return null;
        return await refreshAccessToken(parsed.refresh_token);
    } catch {
        return null;
    }
}

// ─── Calendar API helpers ─────────────────────────────────────────────────────
// nowJerusalem now lives in ./utils (shared across agents).

function formatEventHebrew(event) {
    const start = event.start?.dateTime || event.start?.date;
    const end   = event.end?.dateTime   || event.end?.date;
    const timeStr = start
        ? new Date(start).toLocaleString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit', weekday: 'long', day: 'numeric', month: 'long' })
        : '';
    const location = event.location ? ` | 📍 ${event.location}` : '';
    return `• **${event.summary || 'ללא כותרת'}** — ${timeStr}${location}`;
}

async function listEvents(accessToken, timeMin, timeMax) {
    const { data } = await axios.get(`${CALENDAR_API}/calendars/primary/events`, {
        headers: { Authorization: `Bearer ${accessToken}` },
        params: {
            timeMin: timeMin.toISOString(),
            timeMax: timeMax.toISOString(),
            singleEvents: true,
            orderBy: 'startTime',
            maxResults: 10,
        },
    });
    return data.items || [];
}

async function createEvent(accessToken, eventData) {
    const { data } = await axios.post(
        `${CALENDAR_API}/calendars/primary/events`,
        eventData,
        { headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' } }
    );
    return data;
}

// ─── Parse event from Hebrew message ─────────────────────────────────────────

async function parseEventFromMessage(userMessage) {
    const now = nowJerusalem();
    const todayStr = now.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' });

    const prompt = `Parse this Hebrew message into a Google Calendar event JSON.
Today is ${todayStr} (Jerusalem time).

Message: "${userMessage}"

Rules:
- summary: event title
- startDateTime: ISO 8601 with +03:00 offset
- endDateTime: ISO 8601 (default 1 hour after start if not specified)
- description: optional additional details
- location: optional location

Return ONLY valid JSON (no explanation):
{"summary": "...", "startDateTime": "...", "endDateTime": "...", "description": "", "location": ""}`;

    const raw = await callGemma4(prompt, false, 300);
    const text = typeof raw === 'string' ? raw : (raw?.answer || '');
    const m = text.match(/\{[\s\S]*\}/);
    if (!m) throw new Error('Could not parse event data');
    return JSON.parse(m[0]);
}

// ─── Auth URL generator ────────────────────────────────────────────────────────

function buildAuthUrl(redirectUri, state) {
    const params = new URLSearchParams({
        client_id: process.env.GOOGLE_CLIENT_ID,
        redirect_uri: redirectUri,
        response_type: 'code',
        scope: SCOPES,
        access_type: 'offline',
        prompt: 'consent',
        ...(state && { state }),
    });
    return `${GOOGLE_AUTH_BASE}/auth?${params.toString()}`;
}

// ─── Main agent ───────────────────────────────────────────────────────────────

async function runCalendarAgent(userMessage, supabase, settings = {}) {
    const hasCredentials = process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET;

    if (!hasCredentials) {
        return {
            answer: 'כדי לחבר את יומן Google, צריך להגדיר את GOOGLE_CLIENT_ID ו-GOOGLE_CLIENT_SECRET ב-.env. לאחר מכן גש ל-/auth/google/start לאישור.',
        };
    }

    const accessToken = await getAccessToken(supabase);

    if (!accessToken) {
        const redirectUri = `${process.env.SERVER_URL || 'http://localhost:3000'}/auth/google/callback`;
        const authUrl = buildAuthUrl(redirectUri);
        return {
            answer: `📅 יומן Google לא מחובר עדיין.\n\n**כדי לחבר:**\n1. גש לקישור הזה: ${authUrl}\n2. אשר גישה ליומן שלך\n3. לאחר מכן חזור ונסה שוב`,
            action: { type: 'open_url', url: authUrl },
        };
    }

    // List events
    if (/מה יש לי|מה הפגישות|פגישות.*היום|פגישות.*מחר|אירועים.*היום|יומן.*היום|מה ביומן/i.test(userMessage)) {
        const now = nowJerusalem();
        let timeMin = new Date(now);
        let timeMax = new Date(now);

        if (/מחר/i.test(userMessage)) {
            timeMin.setDate(timeMin.getDate() + 1);
            timeMax.setDate(timeMax.getDate() + 1);
        }
        timeMin.setHours(0, 0, 0, 0);
        timeMax.setHours(23, 59, 59, 999);

        const events = await listEvents(accessToken, timeMin, timeMax);
        const dayLabel = /מחר/i.test(userMessage) ? 'מחר' : 'היום';

        if (events.length === 0) {
            return { answer: `אין אירועים ביומן ל${dayLabel} 🗓️` };
        }

        const list = events.map(formatEventHebrew).join('\n');
        return { answer: `📅 *אירועים ל${dayLabel}:*\n${list}` };
    }

    // Create event
    if (/קבע|תוסיף.*יומן|תקבע|הוסף.*יומן|פגישה עם|אירוע/i.test(userMessage)) {
        const eventData = await parseEventFromMessage(userMessage);

        const gcalEvent = {
            summary: eventData.summary,
            start: { dateTime: eventData.startDateTime, timeZone: 'Asia/Jerusalem' },
            end:   { dateTime: eventData.endDateTime,   timeZone: 'Asia/Jerusalem' },
        };
        if (eventData.description) gcalEvent.description = eventData.description;
        if (eventData.location)    gcalEvent.location    = eventData.location;

        const created = await createEvent(accessToken, gcalEvent);
        const startStr = new Date(eventData.startDateTime).toLocaleString('he-IL', {
            timeZone: 'Asia/Jerusalem', weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit',
        });

        return {
            answer: `✅ הוספתי ליומן: **${gcalEvent.summary}** ב${startStr}`,
            action: { type: 'calendar_event', eventId: created.id, htmlLink: created.htmlLink },
        };
    }

    // Search / upcoming events (next 7 days)
    const now = nowJerusalem();
    const next7 = new Date(now);
    next7.setDate(next7.getDate() + 7);

    const events = await listEvents(accessToken, now, next7);
    if (events.length === 0) {
        return { answer: 'אין אירועים ביומן ב-7 הימים הקרובים.' };
    }

    const list = events.map(formatEventHebrew).join('\n');
    return { answer: `📅 *האירועים הקרובים שלך:*\n${list}` };
}

module.exports = { runCalendarAgent, buildAuthUrl, getAccessToken };
