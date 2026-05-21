'use strict';
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { shouldResolve, resolveReferences } = require('../../services/contextResolver');

beforeEach(() => jest.clearAllMocks());

describe('contextResolver.shouldResolve', () => {
    test('true for short message with anaphora', () => {
        expect(shouldResolve('תזכיר לי על זה מחר')).toBe(true);
        expect(shouldResolve('ספר לי עוד עליו')).toBe(true);
        expect(shouldResolve('תוסיף את זה למשימות')).toBe(true);
    });

    test('false without anaphora', () => {
        expect(shouldResolve('הוסף משימה לקנות חלב')).toBe(false);
        expect(shouldResolve('שלום')).toBe(false);
        expect(shouldResolve('מה מזג האוויר היום')).toBe(false);
    });

    test('false for long messages even with anaphora', () => {
        const long = 'אני רוצה לדבר על זה ועל עוד הרבה דברים אחרים שקרו לי היום בעבודה ובבית עם המשפחה שלי';
        expect(shouldResolve(long)).toBe(false);
    });

    test('false for empty/null', () => {
        expect(shouldResolve('')).toBe(false);
        expect(shouldResolve(null)).toBe(false);
    });
});

describe('contextResolver.resolveReferences', () => {
    const history = [
        { role: 'user', text: 'מה אתה חושב על הפגישה עם דני?' },
        { role: 'jarvis', text: 'הפגישה עם דני נשמעת חשובה.' },
    ];

    test('rewrites a reference using recent context', async () => {
        callGemma4.mockResolvedValue('תזכיר לי על הפגישה עם דני מחר');
        const r = await resolveReferences('תזכיר לי על זה מחר', history, '');
        expect(r.didResolve).toBe(true);
        expect(r.resolved).toContain('דני');
    });

    test('falls back (no LLM) when history is too short', async () => {
        const r = await resolveReferences('תזכיר לי על זה', [], '');
        expect(r.didResolve).toBe(false);
        expect(r.resolved).toBe('תזכיר לי על זה');
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('falls back on LLM failure', async () => {
        callGemma4.mockRejectedValue(new Error('boom'));
        const r = await resolveReferences('תזכיר לי על זה מחר', history, '');
        expect(r.didResolve).toBe(false);
        expect(r.resolved).toBe('תזכיר לי על זה מחר');
    });

    test('safety valve: rejects a rewrite with no token overlap', async () => {
        callGemma4.mockResolvedValue('משהו אחר לגמרי כאן');
        const r = await resolveReferences('תזכיר לי על זה מחר', history, '');
        expect(r.didResolve).toBe(false);
    });

    test('safety valve: rejects an oversized rewrite', async () => {
        callGemma4.mockResolvedValue('תזכיר '.repeat(60));
        const r = await resolveReferences('תזכיר לי על זה', history, '');
        expect(r.didResolve).toBe(false);
    });
});
