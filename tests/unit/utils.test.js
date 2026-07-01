// Unit tests for agents/utils.js — focused on the Jerusalem-offset date
// helpers. The DST regression here matters: toISO() used to hardcode +03:00,
// which made every winter (IST, +02:00) reminder fire an hour off.

const { toISO, jerusalemOffset, todayISODate, sanitizeLike, extractJSON } = require('../../agents/utils');

describe('jerusalemOffset', () => {
    test('winter date (IST) → +02:00', () => {
        expect(jerusalemOffset(new Date(Date.UTC(2026, 0, 15, 12, 0)))).toBe('+02:00');
    });

    test('summer date (IDT) → +03:00', () => {
        expect(jerusalemOffset(new Date(Date.UTC(2026, 6, 15, 12, 0)))).toBe('+03:00');
    });
});

describe('toISO', () => {
    test('uses the winter offset for winter dates', () => {
        const iso = toISO(new Date(2026, 0, 15, 9, 30));
        expect(iso).toBe(`2026-01-15T09:30:00${jerusalemOffset(new Date(Date.UTC(2026, 0, 15)))}`);
        expect(iso.endsWith('+02:00')).toBe(true);
    });

    test('uses the summer offset for summer dates', () => {
        const iso = toISO(new Date(2026, 6, 15, 9, 30));
        expect(iso.endsWith('+03:00')).toBe(true);
    });

    test('zero-pads month, day, hour and minute', () => {
        const iso = toISO(new Date(2026, 2, 5, 7, 5));
        expect(iso.startsWith('2026-03-05T07:05:00')).toBe(true);
    });
});

describe('todayISODate', () => {
    test('returns YYYY-MM-DD', () => {
        expect(todayISODate()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    });
});

describe('sanitizeLike', () => {
    test('escapes %, _ and backslash', () => {
        expect(sanitizeLike('a%b_c\\d')).toBe('a\\%b\\_c\\\\d');
    });

    test('leaves plain text untouched', () => {
        expect(sanitizeLike('פרויקט חדש')).toBe('פרויקט חדש');
    });
});

describe('extractJSON', () => {
    test('extracts the last JSON object from wrapped text', () => {
        expect(extractJSON('sure! {"a":1} done')).toEqual({ a: 1 });
    });

    test('returns null on malformed JSON', () => {
        expect(extractJSON('no json here {broken')).toBeNull();
    });
});
