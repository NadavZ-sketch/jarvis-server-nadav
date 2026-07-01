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

// UTC offset ("+02:00"/"+03:00") of Asia/Jerusalem at the given moment.
// Israel observes DST, so the offset must be derived per-date — a hardcoded
// +03:00 makes every winter reminder fire an hour off.
function jerusalemOffset(date) {
    const part = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Jerusalem', timeZoneName: 'longOffset' })
        .formatToParts(date)
        .find(p => p.type === 'timeZoneName');
    const m = /GMT([+-]\d{2}:\d{2})/.exec(part?.value || '');
    return m ? m[1] : '+02:00';
}

// Format a Date to an ISO timestamp with the Jerusalem offset for that date.
function toISO(date) {
    const pad = n => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:00${jerusalemOffset(date)}`;
}

// ─── LLM output helpers ───────────────────────────────────────────────────────

// Robustly extract a JSON object from an LLM response that may wrap the JSON
// in explanatory text. Returns the parsed object, or null on failure.
// Two passes: last '{'…last '}' (catches a trailing flat object even when the
// preamble contains stray braces), then first '{'…last '}' (catches nested
// objects, where the last '{' is an inner brace). Replaces the repeated
// indexOf/lastIndexOf…JSON.parse boilerplate that agents used to carry.
function extractJSON(aiText) {
    if (!aiText) return null;
    const lastClose = aiText.lastIndexOf('}');
    if (lastClose === -1) return null;
    for (const open of [aiText.lastIndexOf('{'), aiText.indexOf('{')]) {
        if (open === -1 || lastClose < open) continue;
        try {
            return JSON.parse(aiText.substring(open, lastClose + 1));
        } catch { /* try the next candidate range */ }
    }
    return null;
}

module.exports = { sanitizeLike, nowJerusalem, todayISODate, toISO, jerusalemOffset, extractJSON };
