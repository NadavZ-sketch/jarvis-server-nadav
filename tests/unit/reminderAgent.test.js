'use strict';
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));
const {
    parseTime,
    parseRecurrence,
    extractReminderText,
    toISO,
    runReminderAgent,
} = require('../../agents/reminderAgent');

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeChain(data = [], error = null) {
    const chain = {
        then(res) { return Promise.resolve({ data, error }).then(res); },
        catch(rej) { return Promise.resolve({ data, error }).catch(rej); },
        select:  jest.fn().mockReturnThis(),
        single:  jest.fn().mockReturnThis(),
        insert:  jest.fn().mockReturnThis(),
        update:  jest.fn().mockReturnThis(),
        delete:  jest.fn().mockReturnThis(),
        eq:      jest.fn().mockReturnThis(),
        ilike:   jest.fn().mockReturnThis(),
        lte:     jest.fn().mockReturnThis(),
        in:      jest.fn().mockReturnThis(),
        order:   jest.fn().mockReturnThis(),
        limit:   jest.fn().mockReturnThis(),
    };
    return chain;
}

function makeSupabase(data, error) {
    const chain = makeChain(data, error);
    return { from: jest.fn(() => chain), _chain: chain };
}

// ─── parseTime ────────────────────────────────────────────────────────────────

describe('parseTime', () => {
    beforeEach(() => {
        jest.useFakeTimers();
        // Fix to Friday 2026-04-17 10:00:00 Jerusalem (UTC = 07:00:00)
        jest.setSystemTime(new Date('2026-04-17T07:00:00.000Z'));
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    test('בעוד 30 דקות → 10:30 today', () => {
        const result = parseTime('תזכיר לי בעוד 30 דקות לשתות מים');
        expect(result).not.toBeNull();
        expect(result.getHours()).toBe(10);
        expect(result.getMinutes()).toBe(30);
        expect(result.getDate()).toBe(17);
    });

    test('בעוד שעה → 11:00 today', () => {
        const result = parseTime('בעוד שעה');
        expect(result).not.toBeNull();
        expect(result.getHours()).toBe(11);
        expect(result.getMinutes()).toBe(0);
    });

    test('בעוד 3 שעות → 13:00 today', () => {
        const result = parseTime('בעוד 3 שעות');
        expect(result).not.toBeNull();
        expect(result.getHours()).toBe(13);
    });

    test('ב-14:30 (future) → 14:30 today', () => {
        const result = parseTime('ב-14:30');
        expect(result).not.toBeNull();
        expect(result.getHours()).toBe(14);
        expect(result.getMinutes()).toBe(30);
        expect(result.getDate()).toBe(17);
    });

    test('ב-09:00 (past today) → 09:00 tomorrow', () => {
        const result = parseTime('ב-09:00');
        expect(result).not.toBeNull();
        expect(result.getHours()).toBe(9);
        expect(result.getMinutes()).toBe(0);
        expect(result.getDate()).toBe(18);
    });

    test('מחר ב-8:00 → 08:00 on the 18th', () => {
        const result = parseTime('מחר ב-8:00');
        expect(result).not.toBeNull();
        expect(result.getHours()).toBe(8);
        expect(result.getMinutes()).toBe(0);
        expect(result.getDate()).toBe(18);
    });

    test('ביום ראשון ב-12:00 → Sunday April 19', () => {
        // Friday(5) → Sunday(0): diff = 0-5 = -5, +7 = 2 days ahead
        const result = parseTime('ביום ראשון ב-12:00');
        expect(result).not.toBeNull();
        expect(result.getDate()).toBe(19);
        expect(result.getHours()).toBe(12);
    });

    test('ביום שישי ב-10:00 (same weekday) → next Friday', () => {
        // Friday(5) → Friday(5): diff = 0, ≤0 → +7 = 7 days ahead
        const result = parseTime('ביום שישי ב-10:00');
        expect(result).not.toBeNull();
        expect(result.getDate()).toBe(24);
    });

    test('message with no time expression → returns null', () => {
        const result = parseTime('ספר לי על הפרויקט');
        expect(result).toBeNull();
    });

    test('returns null for plain text without time', () => {
        expect(parseTime('שלום מה שלומך')).toBeNull();
    });
});

// ─── extractReminderText ─────────────────────────────────────────────────────

describe('extractReminderText', () => {
    test('strips תזכיר לי + relative time', () => {
        const result = extractReminderText('תזכיר לי בעוד 30 דקות לשתות מים');
        expect(result).toBe('לשתות מים');
    });

    test('strips מחר + time', () => {
        const result = extractReminderText('תזכיר לי מחר ב-9:00 פגישה עם דני');
        expect(result).toBe('פגישה עם דני');
    });

    test('strips day-of-week + time', () => {
        const result = extractReminderText('תזכיר לי ביום שישי בשעה 10:00 אימון');
        expect(result).toBe('אימון');
    });

    test('falls back to original trimmed message if nothing remains', () => {
        // Empty after stripping → returns original
        const msg = 'בעוד שעה';
        const result = extractReminderText(msg);
        expect(result).toBe(msg.trim());
    });
});

// ─── parseRecurrence ─────────────────────────────────────────────────────────

describe('parseRecurrence', () => {
    test('"כל יום" → daily', () => expect(parseRecurrence('תזכיר לי כל יום ב-8:00 לשתות מים')).toBe('daily'));
    test('"יומי" → daily',   () => expect(parseRecurrence('תזכורת יומי לאימון')).toBe('daily'));
    test('"כל שבוע" → weekly', () => expect(parseRecurrence('כל שבוע ב-10:00 פגישה')).toBe('weekly'));
    test('"שבועי" → weekly',  () => expect(parseRecurrence('תזכורת שבועי')).toBe('weekly'));
    test('"כל ראשון" → weekly', () => expect(parseRecurrence('כל ראשון ב-9:00')).toBe('weekly'));
    test('"כל חמישי" → weekly', () => expect(parseRecurrence('כל חמישי ב-19:00 כושר')).toBe('weekly'));
    test('"כל חודש" → monthly', () => expect(parseRecurrence('כל חודש לשלם ארנונה')).toBe('monthly'));
    test('"חודשי" → monthly',   () => expect(parseRecurrence('תשלום חודשי')).toBe('monthly'));
    test('one-time → null', () => expect(parseRecurrence('תזכיר לי בעוד שעה לאכול')).toBeNull());
});

// ─── toISO ────────────────────────────────────────────────────────────────────

describe('toISO', () => {
    test('formats date as +03:00 ISO string', () => {
        const d = new Date(2026, 3, 17, 14, 30, 0); // April = month 3
        const result = toISO(d);
        expect(result).toMatch(/^2026-04-17T14:30:00\+03:00$/);
    });

    test('pads single-digit hour and minute', () => {
        const d = new Date(2026, 3, 17, 9, 5, 0);
        const result = toISO(d);
        expect(result).toMatch(/T09:05:00/);
    });
});

// ─── runReminderAgent ─────────────────────────────────────────────────────────

describe('runReminderAgent', () => {
    beforeEach(() => {
        jest.useFakeTimers();
        jest.setSystemTime(new Date('2026-04-17T07:00:00.000Z'));
    });
    afterEach(() => jest.useRealTimers());

    test('הצג תזכורות → calls select and returns list', async () => {
        const reminders = [
            { id: 1, text: 'לשתות מים', scheduled_time: '2026-04-17T10:30:00+03:00' },
        ];
        const supabase = makeSupabase(reminders);
        const result = await runReminderAgent('הצג תזכורות', supabase);
        expect(supabase.from).toHaveBeenCalledWith('reminders');
        expect(result.answer).toContain('לשתות מים');
    });

    test('הצג תזכורות with empty list → no pending reminders message', async () => {
        const supabase = makeSupabase([]);
        const result = await runReminderAgent('הצג תזכורות', supabase);
        expect(result.answer).toContain('אין לך תזכורות ממתינות');
    });

    test('מחק תזכורת → calls delete with ilike and confirms', async () => {
        const supabase = makeSupabase([{ id: 1, text: 'אימון' }]);
        const result = await runReminderAgent('מחק תזכורת על אימון', supabase);
        expect(supabase._chain.delete).toHaveBeenCalled();
        expect(supabase._chain.ilike).toHaveBeenCalledWith('text', '%אימון%');
        expect(result.answer).toContain('מחקתי');
    });

    test('מחק תזכורת with empty delete result → not found message', async () => {
        const supabase = makeSupabase([]);
        const result = await runReminderAgent('מחק תזכורת על אימון', supabase);
        expect(result.answer).toContain('לא מצאתי');
    });

    test('add reminder → calls insert with correct scheduled_time', async () => {
        const supabase = makeSupabase([], null);
        const result = await runReminderAgent('תזכיר לי בעוד 30 דקות לשתות מים', supabase);
        expect(supabase._chain.insert).toHaveBeenCalled();
        const insertArg = supabase._chain.insert.mock.calls[0][0][0];
        expect(insertArg.text).toBe('לשתות מים');
        expect(insertArg.scheduled_time).toMatch(/10:30:00/);
        expect(insertArg.recurrence).toBeUndefined();
        expect(result.answer).toContain('אזכיר לך');
    });

    test('recurring daily reminder → inserts with recurrence=daily', async () => {
        const supabase = makeSupabase([], null);
        const result = await runReminderAgent('תזכיר לי כל יום ב-8:00 לשתות מים', supabase);
        expect(supabase._chain.insert).toHaveBeenCalled();
        const insertArg = supabase._chain.insert.mock.calls[0][0][0];
        expect(insertArg.recurrence).toBe('daily');
        expect(insertArg.text).toContain('לשתות מים');
        expect(result.answer).toContain('יומי');
    });

    test('recurring weekly reminder → inserts with recurrence=weekly', async () => {
        const supabase = makeSupabase([], null);
        await runReminderAgent('כל שבוע ב-10:00 פגישה', supabase);
        const insertArg = supabase._chain.insert.mock.calls[0][0][0];
        expect(insertArg.recurrence).toBe('weekly');
    });

    test('recurring monthly reminder → answer contains חודשי', async () => {
        const supabase = makeSupabase([], null);
        const result = await runReminderAgent('כל חודש ב-9:00 לשלם ארנונה', supabase);
        expect(result.answer).toContain('חודשי');
    });

    test('add reminder with unparseable time → returns error message', async () => {
        const supabase = makeSupabase();
        const result = await runReminderAgent('ספר לי על הפרויקט', supabase);
        expect(result.answer).toContain('לא הצלחתי להבין');
    });

    test('supabase insert error → returns error message', async () => {
        const supabase = makeSupabase([], { message: 'db error' });
        const result = await runReminderAgent('תזכיר לי בעוד שעה לשתות', supabase);
        expect(result.answer).toContain('לא הצלחתי להבין');
    });
});
