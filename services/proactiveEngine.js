/**
 * Proactive suggestion engine.
 *
 * Inspects current task state (cheaply) and returns at most ONE suggestion that
 * Jarvis can surface — inline at the end of a chat reply, or as a midday push
 * via the existing notification queue. Returns null when nothing is worth
 * raising, so callers can append unconditionally.
 *
 * Query constraint: this runs inside POST /ask-jarvis, whose integration tests
 * mock the Supabase chain with only .select/.eq/.order/.limit/.in/.lte/.then.
 * We therefore over-fetch open tasks and compute overdue/stale/backlog in JS
 * rather than relying on .lt/.gte filters.
 */

const STALE_HIGH_DAYS = 3;
const NUDGE_COOLDOWN_MS = 6 * 60 * 60 * 1000; // 6h per chat

// Per-chat cooldown for inline nudges (in-memory; resets on restart).
const _lastNudgeAt = new Map();

// Keywords indicating the user is winding down, resting, or in leisure mode —
// surfacing task nudges in these contexts feels jarring and unhelpful.
const NON_WORK_PATTERNS = [
    /שינ[הות]|לישון|להירדם|ללכת לישון/,
    /לנוח|מנוחה|נח|נחה/,
    /ערב טוב|לילה טוב|בלילה|לפני שינה/,
    /להתארגן.*שינ|להתכונן.*שינ/,
    /רגיע[הות]|להירגע|זמן פנוי/,
    /סרט|מוזיקה|נגן|לצפות|לשמוע/,
    /good night|goodnight|going to sleep/i,
];

function isNonWorkContext(userMessage) {
    if (!userMessage) return false;
    return NON_WORK_PATTERNS.some(re => re.test(userMessage));
}

function nowJerusalem() {
    return new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
}

function todayISO() {
    const d = nowJerusalem();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function shouldNudgeInline(chatId) {
    if (!chatId) return false;
    const last = _lastNudgeAt.get(chatId);
    return !last || (Date.now() - last) > NUDGE_COOLDOWN_MS;
}

function markNudged(chatId) {
    if (chatId) _lastNudgeAt.set(chatId, Date.now());
}

async function computeProactiveSuggestion(repos, userMessage) {
    // Don't interrupt rest/leisure conversations with task reminders.
    if (isNonWorkContext(userMessage)) return null;

    try {
        const data = await repos.tasks.openForNudge(50);

        const open = Array.isArray(data) ? data : [];
        if (open.length === 0) return null;

        const today = todayISO();

        // 1. Overdue — highest signal.
        const overdue = open.filter(t => t.due_date && t.due_date < today);
        if (overdue.length > 0) {
            return {
                type: 'overdue',
                message: overdue.length === 1
                    ? `שמתי לב שהמשימה "${overdue[0].content}" עברה את תאריך היעד. רוצה לטפל בה עכשיו?`
                    : `יש לך ${overdue.length} משימות שעברו את תאריך היעד. רוצה שנעבור עליהן יחד?`,
            };
        }

        // 2. Stale high-priority task.
        const staleCutoff = nowJerusalem().getTime() - STALE_HIGH_DAYS * 24 * 60 * 60 * 1000;
        const staleHigh = open.filter(t =>
            t.priority === 'high' && t.created_at && new Date(t.created_at).getTime() < staleCutoff
        );
        if (staleHigh.length > 0) {
            return {
                type: 'stale_high',
                message: `המשימה הדחופה "${staleHigh[0].content}" ממתינה כבר כמה ימים. אולי נתקדם איתה?`,
            };
        }

        return null;
    } catch (_) {
        return null;
    }
}

module.exports = { computeProactiveSuggestion, shouldNudgeInline, markNudged };
