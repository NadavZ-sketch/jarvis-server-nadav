'use strict';
const { computeProactiveSuggestion, shouldNudgeInline, markNudged } = require('../../services/proactiveEngine');

function mockSupabase(tasks) {
    const chain = {
        select: jest.fn().mockReturnThis(),
        eq: jest.fn().mockReturnThis(),
        order: jest.fn().mockReturnThis(),
        limit: jest.fn().mockResolvedValue({ data: tasks, error: null }),
    };
    return { from: jest.fn().mockReturnValue(chain) };
}

function isoDaysAgo(n) {
    return new Date(Date.now() - n * 86400000).toISOString();
}
function dateOffset(days) {
    const d = new Date(Date.now() + days * 86400000);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

describe('computeProactiveSuggestion', () => {
    test('returns null when there are no open tasks', async () => {
        expect(await computeProactiveSuggestion(mockSupabase([]))).toBeNull();
    });

    test('overdue task yields an overdue suggestion', async () => {
        const r = await computeProactiveSuggestion(mockSupabase([
            { content: 'להגיש דוח', priority: 'medium', due_date: dateOffset(-3), created_at: isoDaysAgo(5) },
        ]));
        expect(r.type).toBe('overdue');
        expect(r.message).toContain('דוח');
    });

    test('stale high-priority task yields stale_high', async () => {
        const r = await computeProactiveSuggestion(mockSupabase([
            { content: 'משימה דחופה', priority: 'high', due_date: null, created_at: isoDaysAgo(5) },
        ]));
        expect(r.type).toBe('stale_high');
    });

    test('backlog alone (no overdue/stale-high) returns null — backlog nudge removed', async () => {
        const tasks = Array.from({ length: 6 }, (_, i) => ({
            content: `t${i}`, priority: 'low', due_date: null, created_at: isoDaysAgo(0),
        }));
        const r = await computeProactiveSuggestion(mockSupabase(tasks));
        expect(r).toBeNull();
    });

    test('returns null on query error', async () => {
        const bad = { from: () => ({ select: () => { throw new Error('db'); } }) };
        expect(await computeProactiveSuggestion(bad)).toBeNull();
    });

    test('returns null when user message is about going to sleep', async () => {
        const supabase = mockSupabase([
            { content: 'משימה דחופה', priority: 'high', due_date: null, created_at: isoDaysAgo(5) },
        ]);
        expect(await computeProactiveSuggestion(supabase, 'להתארגן לקראת שינה')).toBeNull();
    });

    test('returns null when user message is about resting', async () => {
        const supabase = mockSupabase([
            { content: 'משימה', priority: 'medium', due_date: dateOffset(-1), created_at: isoDaysAgo(2) },
        ]);
        expect(await computeProactiveSuggestion(supabase, 'אני רוצה לנוח קצת הערב')).toBeNull();
    });

    test('still suggests overdue when message is work-related', async () => {
        const supabase = mockSupabase([
            { content: 'להגיש דוח', priority: 'medium', due_date: dateOffset(-1), created_at: isoDaysAgo(3) },
        ]);
        const r = await computeProactiveSuggestion(supabase, 'מה יש לי לעשות היום?');
        expect(r.type).toBe('overdue');
    });
});

describe('inline nudge cooldown', () => {
    test('allows once then blocks after markNudged', () => {
        const id = 'chat-' + Math.random();
        expect(shouldNudgeInline(id)).toBe(true);
        markNudged(id);
        expect(shouldNudgeInline(id)).toBe(false);
    });

    test('blocks empty chatId', () => {
        expect(shouldNudgeInline('')).toBe(false);
    });
});
