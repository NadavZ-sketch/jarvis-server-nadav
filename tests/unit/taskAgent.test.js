'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runTaskAgent } = require('../../agents/taskAgent');

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
        order:   jest.fn().mockReturnThis(),
        limit:   jest.fn().mockReturnThis(),
    };
    return chain;
}

function makeSupabase(data, error) {
    const chain = makeChain(data, error);
    return { from: jest.fn(() => chain), _chain: chain };
}

beforeEach(() => {
    jest.clearAllMocks();
});

describe('runTaskAgent', () => {
    test('add intent inserts task and confirms', async () => {
        callGemma4.mockResolvedValue('{"intent":"add","taskDetails":"buy milk"}');
        const supabase = makeSupabase();
        const result = await runTaskAgent('הוסף משימה לקנות חלב', supabase);
        expect(supabase.from).toHaveBeenCalledWith('tasks');
        expect(supabase._chain.insert).toHaveBeenCalledWith([{ content: 'buy milk' }]);
        expect(result.answer).toContain('הוספתי');
    });

    test('list intent queries tasks and returns list', async () => {
        callGemma4.mockResolvedValue('{"intent":"list","taskDetails":""}');
        const supabase = makeSupabase([{ content: 'buy milk' }, { content: 'call mom' }]);
        const result = await runTaskAgent('מה המשימות שלי', supabase);
        expect(supabase._chain.select).toHaveBeenCalled();
        expect(result.answer).toContain('buy milk');
    });

    test('list intent with empty tasks → no tasks message', async () => {
        callGemma4.mockResolvedValue('{"intent":"list","taskDetails":""}');
        const supabase = makeSupabase([]);
        const result = await runTaskAgent('מה המשימות שלי', supabase);
        expect(result.answer).toContain('אין לך משימות');
    });

    test('JSON wrapped in markdown still parsed via lastIndexOf', async () => {
        callGemma4.mockResolvedValue('Here is the result: {"intent":"list","taskDetails":""} — done');
        const supabase = makeSupabase([{ content: 'task1' }]);
        const result = await runTaskAgent('רשימת משימות', supabase);
        expect(result.answer).toContain('task1');
    });

    test('delete intent removes matching task', async () => {
        callGemma4.mockResolvedValue('{"intent":"delete","taskDetails":"buy milk"}');
        const supabase = makeSupabase([{ content: 'buy milk' }]);
        const result = await runTaskAgent('מחק משימה לקנות חלב', supabase);
        expect(supabase._chain.delete).toHaveBeenCalled();
        expect(supabase._chain.ilike).toHaveBeenCalledWith('content', '%buy milk%');
        expect(result.answer).toContain('מחקתי');
    });

    test('delete intent with no match → not found message', async () => {
        callGemma4.mockResolvedValue('{"intent":"delete","taskDetails":"buy milk"}');
        const supabase = makeSupabase([]);
        const result = await runTaskAgent('מחק משימה', supabase);
        expect(result.answer).toContain('לא מצאתי');
    });

    test('complete intent removes and celebrates', async () => {
        callGemma4.mockResolvedValue('{"intent":"complete","taskDetails":"buy milk"}');
        const supabase = makeSupabase([{ content: 'buy milk' }]);
        const result = await runTaskAgent('סיימתי לקנות חלב', supabase);
        expect(result.answer).toContain('כל הכבוד');
    });

    test('LLM returns no JSON → error message', async () => {
        callGemma4.mockResolvedValue('Sorry, I cannot help with that.');
        const supabase = makeSupabase();
        const result = await runTaskAgent('בלה בלה', supabase);
        expect(result.answer).toContain('הייתה בעיה בעיבוד המשימה');
    });

    test('callGemma4 throws → error message', async () => {
        callGemma4.mockRejectedValue(new Error('Network error'));
        const supabase = makeSupabase();
        const result = await runTaskAgent('הוסף משימה', supabase);
        expect(result.answer).toContain('הייתה בעיה בעיבוד המשימה');
    });
});
