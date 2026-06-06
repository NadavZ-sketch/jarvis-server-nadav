// Shared agent utilities.

// Escapes % _ \ wildcards from user input before ilike pattern matching
function sanitizeLike(str) {
    return String(str).replace(/[\\%_]/g, '\\$&');
}

// ─── Date/time helpers (Jerusalem TZ) ────────────────────────────────────────
// Consolidated from taskAgent / reminderAgent / projectAgent / calendarAgent,
// which each carried identical copies of these.

function nowJerusalem() {
    return new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
}

// Today's date as YYYY-MM-DD in Jerusalem TZ.
function todayISODate() {
    const d = nowJerusalem();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// Format a Date to an ISO timestamp with the +03:00 Jerusalem offset.
function toISO(date) {
    const pad = n => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:00+03:00`;
}

// ─── LLM output helpers ───────────────────────────────────────────────────────

// Robustly extract the last JSON object from an LLM response that may wrap the
// JSON in explanatory text. Returns the parsed object, or null on failure.
// Replaces the repeated lastIndexOf('{')…JSON.parse(substring) boilerplate.
function extractJSON(aiText) {
    if (!aiText) return null;
    const lastOpen = aiText.lastIndexOf('{');
    const lastClose = aiText.lastIndexOf('}');
    if (lastOpen === -1 || lastClose === -1 || lastClose < lastOpen) return null;
    try {
        return JSON.parse(aiText.substring(lastOpen, lastClose + 1));
    } catch {
        return null;
    }
}

module.exports = { sanitizeLike, nowJerusalem, todayISODate, toISO, extractJSON };
