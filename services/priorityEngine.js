// ─── Smart Day Engine — deterministic prioritization & load management ────────
// Pure JS, no DB / no LLM. Operates on already-fetched task & reminder items.
// All scores are 0–100. Times are handled in UTC with a Jerusalem (+3) offset
// for day-boundary math, matching the rest of the codebase.

const JERUSALEM_OFFSET_HOURS = 3;
const DAY_END_HOUR = 22; // last productive hour (Jerusalem), used for capacity

// Heuristic task durations (minutes) — no estimate field exists in the schema.
const DURATION_BY_PRIORITY = { high: 45, medium: 30, low: 20 };
const REMINDER_DURATION = 30; // a fixed appointment still consumes a slot
const DEFAULT_DURATION = 30;

const IMPORTANCE_BY_PRIORITY = { high: 100, medium: 60, low: 30 };
const REMINDER_IMPORTANCE = 80; // reminders are commitments

const URGENT_THRESHOLD = 60;
const IMPORTANT_THRESHOLD = 60;

// ─── Day-boundary helpers (Jerusalem) ────────────────────────────────────────

function startOfJerusalemDay(now) {
    const shifted = new Date(now.getTime() + JERUSALEM_OFFSET_HOURS * 3600000);
    const dayStartUTC = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate());
    // convert that Jerusalem-midnight back to a real UTC instant
    return new Date(dayStartUTC - JERUSALEM_OFFSET_HOURS * 3600000);
}

// Whole-day difference between a due date and "today" (negative = overdue).
function dayDiff(dueDate, now) {
    const today = startOfJerusalemDay(now);
    const due = startOfJerusalemDay(new Date(dueDate));
    return Math.round((due.getTime() - today.getTime()) / 86400000);
}

function clamp(n, lo, hi) {
    return Math.max(lo, Math.min(hi, n));
}

// ─── Scoring ──────────────────────────────────────────────────────────────────

function scoreTask(task, now = new Date()) {
    const priority = IMPORTANCE_BY_PRIORITY[task.priority] != null ? task.priority : 'medium';
    const importance = IMPORTANCE_BY_PRIORITY[priority];

    let urgency;
    let staleness = 0;

    if (!task.due_date) {
        urgency = 10;
        // Anti-starvation: undated pending tasks gain weight with age.
        if (task.created_at) {
            const ageDays = Math.max(0, (now.getTime() - new Date(task.created_at).getTime()) / 86400000);
            staleness = Math.min(ageDays * 2, 20);
        }
    } else {
        const diff = dayDiff(task.due_date, now);
        if (diff < 0)       urgency = 100; // overdue
        else if (diff === 0) urgency = 85; // today
        else if (diff === 1) urgency = 65; // tomorrow
        else if (diff <= 3)  urgency = 45;
        else if (diff <= 7)  urgency = 30;
        else                 urgency = 15;
    }

    const score = clamp(0.55 * urgency + 0.45 * importance + staleness, 0, 100);
    return { urgency, importance, score: Math.round(score) };
}

function scoreReminder(reminder, now = new Date()) {
    const importance = REMINDER_IMPORTANCE;
    let urgency = 35;

    if (reminder.scheduled_time) {
        const minutesUntil = (new Date(reminder.scheduled_time).getTime() - now.getTime()) / 60000;
        if (minutesUntil < 0)        urgency = 100; // past due, not yet fired
        else if (minutesUntil <= 30)  urgency = 95;
        else if (minutesUntil <= 60)  urgency = 85;
        else if (minutesUntil <= 180) urgency = 70;
        else if (minutesUntil <= 360) urgency = 50;
        else                          urgency = 35;
    }

    const score = clamp(0.55 * urgency + 0.45 * importance, 0, 100);
    return { urgency, importance, score: Math.round(score) };
}

function classifyQuadrant(urgency, importance) {
    const urgent = urgency >= URGENT_THRESHOLD;
    const important = importance >= IMPORTANT_THRESHOLD;
    if (urgent && important) return 'now';
    if (important && !urgent) return 'plan';
    if (urgent && !important) return 'quick';
    return 'later';
}

function durationOf(item) {
    if (item.type === 'reminder') return REMINDER_DURATION;
    return DURATION_BY_PRIORITY[item.priority] || DEFAULT_DURATION;
}

// ─── Load / feasibility ─────────────────────────────────────────────────────

function minutesUntilDayEnd(now) {
    const dayStart = startOfJerusalemDay(now);
    const dayEnd = new Date(dayStart.getTime() + DAY_END_HOUR * 3600000);
    return Math.max(0, (dayEnd.getTime() - now.getTime()) / 60000);
}

// Must-do = items in the "now" quadrant. capacity = remaining productive minutes.
function computeLoad(scoredItems, now = new Date()) {
    if (!scoredItems.length) {
        return { ratio: 0, status: 'empty', mustDoMinutes: 0, capacityMinutes: 0 };
    }

    const capacityMinutes = Math.round(minutesUntilDayEnd(now));
    const mustDo = scoredItems.filter(it => it.quadrant === 'now');
    const mustDoMinutes = mustDo.reduce((sum, it) => sum + durationOf(it), 0);

    let status;
    let ratio;
    if (capacityMinutes <= 0) {
        ratio = mustDoMinutes > 0 ? Infinity : 0;
        status = mustDoMinutes > 0 ? 'overload' : 'ok';
    } else {
        ratio = mustDoMinutes / capacityMinutes;
        if (ratio > 1.0)      status = 'overload';
        else if (ratio > 0.8) status = 'tight';
        else                  status = 'ok';
    }

    return {
        ratio: ratio === Infinity ? 99 : Math.round(ratio * 100) / 100,
        status,
        mustDoMinutes,
        capacityMinutes,
    };
}

// ─── Conflict detection (fixed reminder anchors overlapping) ──────────────────

function detectConflicts(reminders, now = new Date()) {
    const anchors = (reminders || [])
        .filter(r => r.scheduled_time && new Date(r.scheduled_time).getTime() >= now.getTime())
        .map(r => ({ id: r.id, title: r.text || r.title, at: new Date(r.scheduled_time).getTime() }))
        .sort((a, b) => a.at - b.at);

    const conflicts = [];
    for (let i = 1; i < anchors.length; i++) {
        const gapMin = (anchors[i].at - anchors[i - 1].at) / 60000;
        if (gapMin < REMINDER_DURATION) {
            conflicts.push({
                a: anchors[i - 1].id,
                b: anchors[i].id,
                reason: `חפיפת זמן: "${anchors[i - 1].title}" ו-"${anchors[i].title}" במרווח של ${Math.round(gapMin)} דק׳`,
            });
        }
    }
    return conflicts;
}

// ─── Orchestration ────────────────────────────────────────────────────────────
// items: normalized { id, type:'task'|'reminder', title, priority?, due_date?,
//         scheduled_time?, created_at? }

function buildDayPlan(items, now = new Date()) {
    const scored = (items || []).map(item => {
        const { urgency, importance, score } =
            item.type === 'reminder' ? scoreReminder(item, now) : scoreTask(item, now);
        return { ...item, urgency, importance, score, quadrant: classifyQuadrant(urgency, importance) };
    });

    scored.sort((a, b) => b.score - a.score);

    const quadrants = { now: [], plan: [], quick: [], later: [] };
    for (const it of scored) quadrants[it.quadrant].push(it);

    const load = computeLoad(scored, now);
    const reminders = (items || []).filter(it => it.type === 'reminder');
    const conflicts = detectConflicts(reminders, now);

    return { items: scored, quadrants, load, conflicts };
}

module.exports = {
    scoreTask,
    scoreReminder,
    classifyQuadrant,
    computeLoad,
    detectConflicts,
    buildDayPlan,
    durationOf,
    // exported for tests / reuse
    DURATION_BY_PRIORITY,
    DAY_END_HOUR,
};
