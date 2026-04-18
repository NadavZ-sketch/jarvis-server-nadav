'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
}));
const { callGemma4 } = require('../../agents/models');
const { runMusicAgent } = require('../../agents/musicAgent');

function makeChain(data = [], error = null) {
    const chain = {
        then(res) { return Promise.resolve({ data, error }).then(res); },
        catch(rej) { return Promise.resolve({ data, error }).catch(rej); },
        select: jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        ilike:  jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        limit:  jest.fn().mockReturnThis(),
    };
    return chain;
}

function makeSupabase(data = [], error = null) {
    const chain = makeChain(data, error);
    return { from: jest.fn().mockReturnValue(chain), _chain: chain };
}

beforeEach(() => callGemma4.mockReset());

describe('runMusicAgent — playlist management', () => {
    test('list playlist returns formatted list', async () => {
        const supabase = makeSupabase([
            { title: 'Bohemian Rhapsody', artist: 'Queen' },
            { title: 'Let It Be', artist: 'Beatles' },
        ]);
        const result = await runMusicAgent('הצג פלייליסט', supabase);
        expect(result.answer).toContain('Bohemian Rhapsody');
        expect(result.answer).toContain('Queen');
        expect(result.answer).toContain('Let It Be');
    });

    test('list playlist when empty returns empty message', async () => {
        const supabase = makeSupabase([]);
        const result = await runMusicAgent('פלייליסט שלי', supabase);
        expect(result.answer).toContain('אין');
    });

    test('save to playlist calls insert and confirms', async () => {
        const supabase = makeSupabase([]);
        const result = await runMusicAgent('הוסף לפלייליסט Hotel California', supabase);
        expect(result.answer).toContain('הוספתי');
        expect(result.answer).toContain('Hotel California');
        expect(supabase._chain.insert).toHaveBeenCalledWith([
            expect.objectContaining({ title: 'Hotel California' }),
        ]);
    });

    test('save without title returns guidance', async () => {
        const supabase = makeSupabase([]);
        const result = await runMusicAgent('הוסף לפלייליסט', supabase);
        expect(result.answer).toContain('מה להוסיף');
    });

    test('delete from playlist calls delete and confirms', async () => {
        const supabase = makeSupabase([{ title: 'Hotel California', artist: 'Eagles' }]);
        const result = await runMusicAgent('מחק שיר Hotel California', supabase);
        expect(result.answer).toContain('הסרתי');
        expect(result.answer).toContain('Hotel California');
    });

    test('delete not found returns not-found message', async () => {
        const supabase = makeSupabase([]);
        const result = await runMusicAgent('מחק מהפלייליסט unknown song', supabase);
        expect(result.answer).toContain('לא מצאתי');
    });
});

describe('runMusicAgent — recommendation', () => {
    test('returns answer and action with YouTube Music url', async () => {
        callGemma4.mockResolvedValue("מוזיקת ג'אז מרגיעה מושלמת לעבודה.\nSEARCH: relaxing jazz music");
        const supabase = makeSupabase([]);
        const result = await runMusicAgent('מוזיקה רגועה לעבודה', supabase);
        expect(result.answer).toContain("ג'אז");
        expect(result.answer).not.toContain('SEARCH:');
        expect(result.action).toBeDefined();
        expect(result.action.type).toBe('music');
        expect(result.action.url).toContain('music.youtube.com');
        expect(result.action.url).toContain('relaxing');
    });

    test('recommendation without SEARCH tag still returns valid url', async () => {
        callGemma4.mockResolvedValue('מוזיקה יפה מאוד');
        const supabase = makeSupabase([]);
        const result = await runMusicAgent('מוזיקה', supabase);
        expect(result.action?.url).toContain('music.youtube.com');
    });

    test('callGemma4 throws → returns error answer', async () => {
        callGemma4.mockRejectedValue(new Error('API error'));
        const supabase = makeSupabase([]);
        const result = await runMusicAgent('נגן מוזיקה', supabase);
        expect(result.answer).toContain('סליחה');
        expect(result.action).toBeUndefined();
    });
});
