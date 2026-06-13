'use strict';
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));
const {
    parseTime,
    parseRecurrence,
    extractReminderText,
    toISO,
    runReminderAgent,
} = require('../../agents/reminderAgent');
const { makeRepos, makeReminderRepo } = require('../helpers/fakeRepos');

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

    test('הצג תזכורות → lists upcoming reminders', async () => {
        const repos = makeRepos({ reminders: [
            { id: 1, text: 'לשתות מים', scheduled_time: '2026-04-17T10:30:00+03:00' },
        ] });
        const result = await runReminderAgent('הצג תזכורות', repos);
        expect(repos.reminders.listUpcoming).toHaveBeenCalled();
        expect(result.answer).toContain('לשתות מים');
    });

    test('הצג תזכורות with empty list → no pending reminders message', async () => {
        const result = await runReminderAgent('הצג תזכורות', makeRepos({ reminders: [] }));
        expect(result.answer).toContain('אין לך תזכורות ממתינות');
    });

    test('מחק תזכורת → deletes by text and confirms', async () => {
        const repos = makeRepos({ reminders: [{ id: 1, text: 'אימון' }] });
        const result = await runReminderAgent('מחק תזכורת על אימון', repos);
        expect(repos.reminders.deleteByText).toHaveBeenCalledWith('אימון');
        expect(result.answer).toContain('מחקתי');
    });

    test('מחק תזכורת with empty delete result → not found message', async () => {
        const result = await runReminderAgent('מחק תזכורת על אימון', makeRepos({ reminders: [] }));
        expect(result.answer).toContain('לא מצאתי');
    });

    test('add reminder → calls add with correct scheduled_time', async () => {
        const repos = makeRepos({ reminders: [] });
        const result = await runReminderAgent('תזכיר לי בעוד 30 דקות לשתות מים', repos);
        expect(repos.reminders.add).toHaveBeenCalled();
        const addArg = repos.reminders.add.mock.calls[0][0];
        expect(addArg.text).toBe('לשתות מים');
        expect(addArg.scheduled_time).toMatch(/10:30:00/);
        expect(addArg.recurrence).toBeUndefined();
        expect(result.answer).toContain('אזכיר לך');
    });

    test('recurring daily reminder → adds with recurrence=daily', async () => {
        const repos = makeRepos({ reminders: [] });
        const result = await runReminderAgent('תזכיר לי כל יום ב-8:00 לשתות מים', repos);
        const addArg = repos.reminders.add.mock.calls[0][0];
        expect(addArg.recurrence).toBe('daily');
        expect(addArg.text).toContain('לשתות מים');
        expect(result.answer).toContain('יומי');
    });

    test('recurring weekly reminder → adds with recurrence=weekly', async () => {
        const repos = makeRepos({ reminders: [] });
        await runReminderAgent('כל שבוע ב-10:00 פגישה', repos);
        const addArg = repos.reminders.add.mock.calls[0][0];
        expect(addArg.recurrence).toBe('weekly');
    });

    test('recurring monthly reminder → answer contains חודשי', async () => {
        const result = await runReminderAgent('כל חודש ב-9:00 לשלם ארנונה', makeRepos({ reminders: [] }));
        expect(result.answer).toContain('חודשי');
    });

    test('add reminder with unparseable time → returns clarification question', async () => {
        const result = await runReminderAgent('ספר לי על הפרויקט', makeRepos());
        expect(result.answer).toContain('מתי תרצה שאזכיר לך');
    });

    test('insert error → returns error message', async () => {
        const repos = { reminders: makeReminderRepo({ addResult: { error: { message: 'db error' } } }) };
        const result = await runReminderAgent('תזכיר לי בעוד שעה לשתות', repos);
        expect(result.answer).toContain('לא הצלחתי להבין');
    });
});
