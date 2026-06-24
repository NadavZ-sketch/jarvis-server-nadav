'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
}));
const { callGemma4 } = require('../../agents/models');
const { runMusicAgent } = require('../../agents/musicAgent');

function makeRepos(songs = [], deleteError = null) {
    return {
        playlist: {
            list:          jest.fn().mockResolvedValue(songs),
            add:           jest.fn().mockResolvedValue({ error: null }),
            deleteByTitle: jest.fn().mockResolvedValue(deleteError ? [] : songs),
        },
    };
}

beforeEach(() => callGemma4.mockReset());

describe('runMusicAgent — playlist management', () => {
    test('list playlist returns formatted list', async () => {
        const repos = makeRepos([
            { title: 'Bohemian Rhapsody', artist: 'Queen' },
            { title: 'Let It Be', artist: 'Beatles' },
        ]);
        const result = await runMusicAgent('הצג פלייליסט', repos);
        expect(result.answer).toContain('Bohemian Rhapsody');
        expect(result.answer).toContain('Queen');
        expect(result.answer).toContain('Let It Be');
    });

    test('list playlist when empty returns empty message', async () => {
        const repos = makeRepos([]);
        const result = await runMusicAgent('פלייליסט שלי', repos);
        expect(result.answer).toContain('אין');
    });

    test('save to playlist calls add and confirms', async () => {
        const repos = makeRepos([]);
        const result = await runMusicAgent('הוסף לפלייליסט Hotel California', repos);
        expect(result.answer).toContain('הוספתי');
        expect(result.answer).toContain('Hotel California');
        expect(repos.playlist.add).toHaveBeenCalledWith('Hotel California');
    });

    test('save without title returns guidance', async () => {
        const repos = makeRepos([]);
        const result = await runMusicAgent('הוסף לפלייליסט', repos);
        expect(result.answer).toContain('מה להוסיף');
    });

    test('delete from playlist calls deleteByTitle and confirms', async () => {
        const songs = [{ title: 'Hotel California', artist: 'Eagles' }];
        const repos = makeRepos(songs);
        // deleteByTitle returns the deleted rows
        repos.playlist.deleteByTitle.mockResolvedValue(songs);
        const result = await runMusicAgent('מחק שיר Hotel California', repos);
        expect(result.answer).toContain('הסרתי');
        expect(result.answer).toContain('Hotel California');
    });

    test('delete not found returns not-found message', async () => {
        const repos = makeRepos([]);
        repos.playlist.deleteByTitle.mockResolvedValue([]);
        const result = await runMusicAgent('מחק מהפלייליסט unknown song', repos);
        expect(result.answer).toContain('לא מצאתי');
    });
});

describe('runMusicAgent — recommendation', () => {
    test('returns answer and action with YouTube Music url', async () => {
        callGemma4.mockResolvedValue("מוזיקת ג'אז מרגיעה מושלמת לעבודה.\nSEARCH: relaxing jazz music");
        const repos = makeRepos([]);
        const result = await runMusicAgent('מוזיקה רגועה לעבודה', repos);
        expect(result.answer).toContain("ג'אז");
        expect(result.answer).not.toContain('SEARCH:');
        expect(result.action).toBeDefined();
        expect(result.action.type).toBe('music');
        expect(result.action.url).toContain('music.youtube.com');
        expect(result.action.url).toContain('relaxing');
    });

    test('recommendation without SEARCH tag still returns valid url', async () => {
        callGemma4.mockResolvedValue('מוזיקה יפה מאוד');
        const repos = makeRepos([]);
        const result = await runMusicAgent('מוזיקה', repos);
        expect(result.action?.url).toContain('music.youtube.com');
    });

    test('callGemma4 throws → returns error answer', async () => {
        callGemma4.mockRejectedValue(new Error('API error'));
        const repos = makeRepos([]);
        const result = await runMusicAgent('נגן מוזיקה', repos);
        expect(result.answer).toContain('סליחה');
        expect(result.action).toBeUndefined();
    });
});
