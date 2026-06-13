'use strict';

// obsidianSync.dbToVault is a fire-and-forget side effect; stub it so the add
// path doesn't touch the filesystem.
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));

const obsidianSync = require('../../services/obsidianSync');
const { runNotesAgent } = require('../../agents/notesAgent');
const { makeRepos, makeNoteRepo } = require('../helpers/fakeRepos');

beforeEach(() => jest.clearAllMocks());

describe('runNotesAgent — add', () => {
    test('strips the leading verb and saves the remainder as content', async () => {
        const repos = makeRepos({ notes: [{ id: 'n1' }] });
        const res = await runNotesAgent('תרשום לי לקנות חלב', repos, false);
        expect(res.answer).toContain('שמרתי את ההערה');
        expect(res.action).toEqual({ type: 'navigate', target: 'notes', label: 'פתח הערות' });
        expect(repos.notes.add).toHaveBeenCalledWith({ title: '', content: 'לקנות חלב' });
    });

    test('mirrors the inserted row to the Obsidian vault', async () => {
        const repos = makeRepos({ notes: [{ id: 'n9', content: 'x' }] });
        await runNotesAgent('שמור הערה רעיון חדש', repos, false);
        expect(obsidianSync.dbToVault).toHaveBeenCalledWith('notes', expect.anything());
    });

    test('a bare sentence with no verb is stored verbatim', async () => {
        const repos = makeRepos({ notes: [{ id: 'n2' }] });
        await runNotesAgent('הרעיון הגדול שלי להיום', repos, false);
        expect(repos.notes.add).toHaveBeenCalledWith({ title: '', content: 'הרעיון הגדול שלי להיום' });
    });
});

describe('runNotesAgent — list', () => {
    test('empty store → "no notes" message, no action', async () => {
        const res = await runNotesAgent('הצג הערות', makeRepos({ notes: [] }), false);
        expect(res.answer).toBe('אין לך הערות שמורות.');
        expect(res.action).toBeUndefined();
    });

    test('numbers the notes, preferring the title then falling back to content', async () => {
        const repos = makeRepos({ notes: [
            { title: 'כותרת', content: 'גוף ההערה' },
            { title: '', content: 'הערה בלי כותרת שצריכה חיתוך תצוגה מקדימה' },
        ] });
        const res = await runNotesAgent('הערות שלי', repos, false);
        expect(res.answer).toContain('1. כותרת');
        expect(res.answer).toContain('2. הערה בלי כותרת');
    });
});

describe('runNotesAgent — search', () => {
    test('reports matches with a count', async () => {
        const repos = makeRepos({ notes: [{ title: 'רעיון', content: 'לפתח פיצ\'ר חדש' }] });
        const res = await runNotesAgent('חפש הערה פיצ\'ר', repos, false);
        expect(res.answer).toContain('מצאתי 1 הערות');
        expect(res.answer).toContain('לפתח פיצ');
        expect(repos.notes.search).toHaveBeenCalledWith(expect.stringContaining('פיצ'));
    });

    test('no matches → not-found message echoing the query', async () => {
        const res = await runNotesAgent('חפש הערה משהו', makeRepos({ notes: [] }), false);
        expect(res.answer).toContain('לא מצאתי הערות עם');
        expect(res.answer).toContain('משהו');
    });
});

describe('runNotesAgent — delete', () => {
    test('asks which note when no query term survives the verb strip', async () => {
        const res = await runNotesAgent('מחק הערה', makeRepos({ notes: [] }), false);
        expect(res.answer).toBe('איזו הערה למחוק?');
    });

    test('confirms deletion when a row was removed', async () => {
        const res = await runNotesAgent('מחק הערה חלב', makeRepos({ notes: [{ id: 'gone' }] }), false);
        expect(res.answer).toBe('ההערה נמחקה ✓');
    });

    test('reports nothing-to-delete when no row matched', async () => {
        const res = await runNotesAgent('הסר פתק לא קיים', makeRepos({ notes: [] }), false);
        expect(res.answer).toBe('לא מצאתי הערה למחוק.');
    });
});

describe('runNotesAgent — resilience', () => {
    test('a thrown repo error is caught and returns the Hebrew fallback', async () => {
        const notes = makeNoteRepo();
        notes.listRecent = jest.fn(async () => { throw new Error('db exploded'); });
        const res = await runNotesAgent('הצג הערות', { notes }, false);
        expect(res.answer).toBe('שגיאה בעיבוד בקשת ההערות.');
    });
});
