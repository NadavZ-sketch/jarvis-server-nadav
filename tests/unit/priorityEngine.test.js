'use strict';

const {
    scoreTask,
    scoreReminder,
    classifyQuadrant,
    computeLoad,
    detectConflicts,
    buildDayPlan,
} = require('../../services/priorityEngine');

// Fixed reference "now": 2026-05-22T09:00:00Z → 12:00 Jerusalem.
const NOW = new Date('2026-05-22T09:00:00Z');

function isoDate(daysFromNow) {
    const d = new Date(NOW.getTime() + daysFromNow * 86400000);
    return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

describe('scoreTask — urgency by due date', () => {
    test('overdue task → urgency 100', () => {
        const { urgency } = scoreTask({ priority: 'medium', due_date: isoDate(-2) }, NOW);
        expect(urgency).toBe(100);
    });

    test('due today → urgency 85', () => {
        const { urgency } = scoreTask({ priority: 'medium', due_date: isoDate(0) }, NOW);
        expect(urgency).toBe(85);
    });

    test('due in a week → low urgency', () => {
        const { urgency } = scoreTask({ priority: 'medium', due_date: isoDate(7) }, NOW);
        expect(urgency).toBe(30);
    });

    test('high priority raises importance and final score', () => {
        const high = scoreTask({ priority: 'high', due_date: isoDate(0) }, NOW);
        const low  = scoreTask({ priority: 'low',  due_date: isoDate(0) }, NOW);
        expect(high.importance).toBe(100);
        expect(low.importance).toBe(30);
        expect(high.score).toBeGreaterThan(low.score);
    });

    test('invalid priority defaults to medium', () => {
        const { importance } = scoreTask({ priority: 'bogus', due_date: isoDate(0) }, NOW);
        expect(importance).toBe(60);
    });
});

describe('scoreTask — staleness for undated tasks', () => {
    test('old undated task scores higher than fresh undated task (anti-starvation)', () => {
        const old   = scoreTask({ priority: 'low', created_at: new Date(NOW.getTime() - 8 * 86400000).toISOString() }, NOW);
        const fresh = scoreTask({ priority: 'low', created_at: NOW.toISOString() }, NOW);
        expect(old.score).toBeGreaterThan(fresh.score);
    });

    test('staleness is capped (does not exceed +20)', () => {
        const ancient = scoreTask({ priority: 'low', created_at: new Date(NOW.getTime() - 365 * 86400000).toISOString() }, NOW);
        // base: 0.55*10 + 0.45*30 = 19, +20 cap = 39
        expect(ancient.score).toBeLessThanOrEqual(39);
    });
});

describe('scoreReminder — urgency by time until fire', () => {
    test('past-due unfired reminder → urgency 100', () => {
        const r = scoreReminder({ scheduled_time: new Date(NOW.getTime() - 60000).toISOString() }, NOW);
        expect(r.urgency).toBe(100);
    });

    test('reminder within 30 min → urgency 95', () => {
        const r = scoreReminder({ scheduled_time: new Date(NOW.getTime() + 20 * 60000).toISOString() }, NOW);
        expect(r.urgency).toBe(95);
    });

    test('reminder hours away → lower urgency', () => {
        const r = scoreReminder({ scheduled_time: new Date(NOW.getTime() + 5 * 3600000).toISOString() }, NOW);
        expect(r.urgency).toBe(50);
    });
});

describe('classifyQuadrant — Eisenhower', () => {
    test.each([
        [90, 90, 'now'],
        [30, 90, 'plan'],
        [90, 30, 'quick'],
        [20, 20, 'later'],
        [60, 60, 'now'], // on threshold → deterministic (>=)
    ])('urgency=%i importance=%i → %s', (u, i, expected) => {
        expect(classifyQuadrant(u, i)).toBe(expected);
    });
});

describe('computeLoad — feasibility', () => {
    test('empty list → status empty', () => {
        expect(computeLoad([], NOW).status).toBe('empty');
    });

    test('many urgent+important tasks → overload', () => {
        // 12:00 Jerusalem → 10h (600 min) capacity until 22:00.
        // 20 high-priority "now" tasks × 45 min = 900 min > 600.
        const items = Array.from({ length: 20 }, (_, i) => ({
            id: `t${i}`, type: 'task', priority: 'high', quadrant: 'now',
        }));
        const load = computeLoad(items, NOW);
        expect(load.status).toBe('overload');
        expect(load.ratio).toBeGreaterThan(1);
    });

    test('light day → status ok', () => {
        const items = [{ id: 't1', type: 'task', priority: 'low', quadrant: 'now' }];
        expect(computeLoad(items, NOW).status).toBe('ok');
    });
});

describe('detectConflicts — overlapping reminder anchors', () => {
    test('two reminders within 30 min → conflict', () => {
        const reminders = [
            { id: 1, text: 'פגישה א', scheduled_time: new Date(NOW.getTime() + 2 * 3600000).toISOString() },
            { id: 2, text: 'פגישה ב', scheduled_time: new Date(NOW.getTime() + 2 * 3600000 + 10 * 60000).toISOString() },
        ];
        const conflicts = detectConflicts(reminders, NOW);
        expect(conflicts).toHaveLength(1);
        expect(conflicts[0]).toMatchObject({ a: 1, b: 2 });
    });

    test('well-spaced reminders → no conflict', () => {
        const reminders = [
            { id: 1, text: 'א', scheduled_time: new Date(NOW.getTime() + 1 * 3600000).toISOString() },
            { id: 2, text: 'ב', scheduled_time: new Date(NOW.getTime() + 3 * 3600000).toISOString() },
        ];
        expect(detectConflicts(reminders, NOW)).toHaveLength(0);
    });
});

describe('buildDayPlan — orchestration', () => {
    test('returns sorted items, quadrants, load, conflicts', () => {
        const items = [
            { id: 'task-1', type: 'task', title: 'דחוף', priority: 'high', due_date: isoDate(-1) },
            { id: 'task-2', type: 'task', title: 'מתישהו', priority: 'low' },
            { id: 'reminder-1', type: 'reminder', title: 'שיחה', scheduled_time: new Date(NOW.getTime() + 20 * 60000).toISOString() },
        ];
        const plan = buildDayPlan(items, NOW);

        expect(plan.items).toHaveLength(3);
        // sorted descending by score
        expect(plan.items[0].score).toBeGreaterThanOrEqual(plan.items[1].score);
        // overdue high task lands in "now"
        expect(plan.quadrants.now.map(i => i.id)).toContain('task-1');
        // undated low task lands in backlog
        expect(plan.quadrants.later.map(i => i.id)).toContain('task-2');
        expect(plan.load).toHaveProperty('status');
        expect(Array.isArray(plan.conflicts)).toBe(true);
    });

    test('empty input → empty plan', () => {
        const plan = buildDayPlan([], NOW);
        expect(plan.items).toHaveLength(0);
        expect(plan.load.status).toBe('empty');
    });
});
