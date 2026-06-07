'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
}));

const { callGemma4 } = require('../../agents/models');
const { runHabitAgent, computeStreak } = require('../../agents/habitAgent');
const { nowJerusalem } = require('../../agents/utils');

// Per-table mock: from(table) returns a thenable chain seeded with that table's data.
function makeSupabase(tableData = {}) {
    const chains = {};
    const make = (data) => ({
        then(res) { return Promise.resolve({ data, error: null }).then(res); },
        catch(rej) { return Promise.resolve({ data, error: null }).catch(rej); },
        select: jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        upsert: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        ilike:  jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        limit:  jest.fn().mockReturnThis(),
    });
    const seed = (t) => (chains[t] = make(tableData[t] || []));
    Object.keys(tableData).forEach(seed);
    const from = jest.fn((t) => chains[t] || seed(t));
    return { from, chains };
}

function isoDaysAgo(n) {
    const d = nowJerusalem();
    d.setDate(d.getDate() - n);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

beforeEach(() => jest.clearAllMocks());

describe('computeStreak', () => {
    test('counts consecutive days ending today', () => {
        expect(computeStreak([isoDaysAgo(0), isoDaysAgo(1), isoDaysAgo(2)])).toBe(3);
    });
    test('stays alive when today not yet logged but yesterday is', () => {
        expect(computeStreak([isoDaysAgo(1), isoDaysAgo(2)])).toBe(2);
    });
    test('breaks on a gap', () => {
        expect(computeStreak([isoDaysAgo(0), isoDaysAgo(2), isoDaysAgo(3)])).toBe(1);
    });
    test('zero when no recent logs', () => {
        expect(computeStreak([isoDaysAgo(5)])).toBe(0);
        expect(computeStreak([])).toBe(0);
    });
});

describe('runHabitAgent', () => {
    test('add inserts a habit', async () => {
        callGemma4.mockResolvedValue('{"intent":"add","habitName":"ריצה","schedule":"daily"}');
        const supabase = makeSupabase({ habits: [] });
        const result = await runHabitAgent('תוסיף הרגל ריצה כל בוקר', supabase);
        expect(supabase.from).toHaveBeenCalledWith('habits');
        expect(supabase.chains.habits.insert).toHaveBeenCalledWith(
            expect.arrayContaining([expect.objectContaining({ name: 'ריצה', schedule: 'daily' })])
        );
        expect(result.answer).toContain('ריצה');
    });

    test('log records today and reports streak', async () => {
        callGemma4.mockResolvedValue('{"intent":"log","habitName":"ריצה"}');
        const supabase = makeSupabase({
            habits: [{ id: 'h1', name: 'ריצה', schedule: 'daily' }],
            habit_logs: [{ date: isoDaysAgo(0) }, { date: isoDaysAgo(1) }],
        });
        const result = await runHabitAgent('התאמנתי היום', supabase);
        expect(supabase.chains.habit_logs.upsert).toHaveBeenCalled();
        expect(result.answer).toContain('הרצף שלך');
    });

    test('log with unknown habit suggests adding it', async () => {
        callGemma4.mockResolvedValue('{"intent":"log","habitName":"שחייה"}');
        const supabase = makeSupabase({ habits: [] });
        const result = await runHabitAgent('שחיתי היום', supabase);
        expect(result.answer).toContain('לא מצאתי הרגל');
    });

    test('status reports streak and total', async () => {
        callGemma4.mockResolvedValue('{"intent":"status","habitName":"ריצה"}');
        const supabase = makeSupabase({
            habits: [{ id: 'h1', name: 'ריצה', schedule: 'daily' }],
            habit_logs: [{ date: isoDaysAgo(0) }, { date: isoDaysAgo(1) }, { date: isoDaysAgo(2) }],
        });
        const result = await runHabitAgent('מה הרצף שלי בריצה', supabase);
        expect(result.answer).toContain('רצף נוכחי 3');
    });

    test('list with no habits prompts to start one', async () => {
        callGemma4.mockResolvedValue('{"intent":"list","habitName":""}');
        const supabase = makeSupabase({ habits: [] });
        const result = await runHabitAgent('מה ההרגלים שלי', supabase);
        expect(result.answer).toContain('אין לך הרגלים');
    });

    test('delete deactivates the habit', async () => {
        callGemma4.mockResolvedValue('{"intent":"delete","habitName":"ריצה"}');
        const supabase = makeSupabase({ habits: [{ id: 'h1', name: 'ריצה', schedule: 'daily' }] });
        const result = await runHabitAgent('תפסיק לעקוב אחרי ריצה', supabase);
        expect(supabase.chains.habits.update).toHaveBeenCalledWith({ active: false });
        expect(result.answer).toContain('הפסקתי לעקוב');
    });

    test('no JSON → graceful message', async () => {
        callGemma4.mockResolvedValue('no json here');
        const supabase = makeSupabase({});
        const result = await runHabitAgent('בלה', supabase);
        expect(result.answer).toContain('לא הצלחתי');
    });
});
