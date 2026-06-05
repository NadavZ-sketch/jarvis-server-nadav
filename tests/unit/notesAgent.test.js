'use strict';

// obsidianSync.dbToVault is a fire-and-forget side effect; stub it so the add
// path doesn't touch the filesystem.
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));

const obsidianSync = require('../../services/obsidianSync');
const { runNotesAgent } = require('../../agents/notesAgent');
const { makeChain } = require('../helpers/supabaseMock');

// A supabase whose every .from(...) returns the same seeded chain, so the test
// can both seed the resolved rows and inspect which query methods were called.
function seed(rows = [], error = null) {
    const chain = makeChain(rows, error);
    return { supabase: { from: jest.fn(() => chain) }, chain };
}

beforeEach(() => jest.clearAllMocks());

describe('runNotesAgent — add', () => {
    test('strips the leading verb and saves the remainder as content', async () => {
        const { supabase, chain } = seed([{ id: 'n1' }]);
        const res = await runNotesAgent('תרשום לי לקנות חלב', supabase, false);

        expect(res.answer).toContain('שמרתי את ההערה');
        expect(res.action).toEqual({ type: 'navigate', target: 'notes', label: 'פתח הערות' });
        // content passed to insert is the message minus the verb
        expect(chain.insert).toHaveBeenCalledWith([{ title: '', content: 'לקנות חלב' }]);
    });

    test('mirrors the inserted row to the Obsidian vault', async () => {
        const { supabase } = seed([{ id: 'n9', content: 'x' }]);
        await runNotesAgent('שמור הערה רעיון חדש', supabase, false);
        expect(obsidianSync.dbToVault).toHaveBeenCalledWith('notes', expect.anything());
    });

    test('a bare sentence with no verb is stored verbatim', async () => {
        const { supabase, chain } = seed([{ id: 'n2' }]);
        await runNotesAgent('הרעיון הגדול שלי להיום', supabase, false);
        expect(chain.insert).toHaveBeenCalledWith([{ title: '', content: 'הרעיון הגדול שלי להיום' }]);
    });
});

describe('runNotesAgent — list', () => {
    test('empty store → "no notes" message, no action', async () => {
        const { supabase } = seed([]);
        const res = await runNotesAgent('הצג הערות', supabase, false);
        expect(res.answer).toBe('אין לך הערות שמורות.');
        expect(res.action).toBeUndefined();
    });

    test('numbers the notes, preferring the title then falling back to content', async () => {
        const { supabase } = seed([
            { title: 'כותרת', content: 'גוף ההערה' },
            { title: '', content: 'הערה בלי כותרת שצריכה חיתוך תצוגה מקדימה' },
        ]);
        const res = await runNotesAgent('הערות שלי', supabase, false);
        expect(res.answer).toContain('1. כותרת');               // title wins
        expect(res.answer).toContain('2. הערה בלי כותרת');       // content fallback
    });
});

describe('runNotesAgent — search', () => {
    test('reports matches with a count', async () => {
        const { supabase, chain } = seed([{ title: 'רעיון', content: 'לפתח פיצ\'ר חדש' }]);
        const res = await runNotesAgent('חפש הערה פיצ\'ר', supabase, false);
        expect(res.answer).toContain('מצאתי 1 הערות');
        expect(res.answer).toContain('לפתח פיצ');
        // the search query was the message minus the "חפש הערה" prefix
        expect(chain.or).toHaveBeenCalledWith(expect.stringContaining('פיצ'));
    });

    test('no matches → not-found message echoing the query', async () => {
        const { supabase } = seed([]);
        const res = await runNotesAgent('חפש הערה משהו', supabase, false);
        expect(res.answer).toContain('לא מצאתי הערות עם');
        expect(res.answer).toContain('משהו');
    });
});

describe('runNotesAgent — delete', () => {
    test('asks which note when no query term survives the verb strip', async () => {
        const { supabase } = seed([]);
        const res = await runNotesAgent('מחק הערה', supabase, false);
        expect(res.answer).toBe('איזו הערה למחוק?');
    });

    test('confirms deletion when a row was removed', async () => {
        const { supabase } = seed([{ id: 'gone' }]);
        const res = await runNotesAgent('מחק הערה חלב', supabase, false);
        expect(res.answer).toBe('ההערה נמחקה ✓');
    });

    test('reports nothing-to-delete when no row matched', async () => {
        const { supabase } = seed([]);
        const res = await runNotesAgent('הסר פתק לא קיים', supabase, false);
        expect(res.answer).toBe('לא מצאתי הערה למחוק.');
    });
});

describe('runNotesAgent — resilience', () => {
    test('a thrown supabase error is caught and returns the Hebrew fallback', async () => {
        const supabase = { from: jest.fn(() => { throw new Error('db exploded'); }) };
        const res = await runNotesAgent('הצג הערות', supabase, false);
        expect(res.answer).toBe('שגיאה בעיבוד בקשת ההערות.');
    });
});
