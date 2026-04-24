'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runMemoryAgent } = require('../../agents/memoryAgent');

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

describe('runMemoryAgent', () => {
    test('save memory: calls insert with content from LLM', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] אני אוהב פיצה"}');
        const supabase = makeSupabase();
        const result = await runMemoryAgent('זכור ש אני אוהב פיצה', supabase);
        expect(supabase.from).toHaveBeenCalledWith('memories');
        expect(supabase._chain.insert).toHaveBeenCalledWith([
            { content: '[hobby] אני אוהב פיצה' }
        ]);
        expect(result.answer).toContain('שמרתי');
    });

    test('save memory: LLM returns no JSON → error message', async () => {
        callGemma4.mockResolvedValue('I cannot do that.');
        const supabase = makeSupabase();
        const result = await runMemoryAgent('זכור ש כל מיני', supabase);
        expect(result.answer).toContain('הייתה בעיה בשמירת הזיכרון');
    });

    test('recall: fetches memories and passes to LLM', async () => {
        const memories = [
            { content: '[hobby] אני אוהב פיצה' },
            { content: '[location] גר בתל אביב' },
        ];
        callGemma4.mockResolvedValue('יש לי זיכרונות עליך: אוהב פיצה וגר בתל אביב.');
        const supabase = makeSupabase(memories);
        const result = await runMemoryAgent('מה אתה יודע עליי', supabase);
        expect(supabase._chain.select).toHaveBeenCalledWith('content');
        expect(callGemma4).toHaveBeenCalled();
        const prompt = callGemma4.mock.calls[0][0];
        expect(prompt).toContain('[hobby] אני אוהב פיצה');
        expect(result.answer).toContain('פיצה');
    });

    test('recall with no memories → no memories message', async () => {
        const supabase = makeSupabase([]);
        const result = await runMemoryAgent('מה אתה יודע עליי', supabase);
        expect(callGemma4).not.toHaveBeenCalled();
        expect(result.answer).toContain('אין לי עדיין זיכרונות');
    });

    test('delete memory: calls delete with ilike and confirms', async () => {
        const supabase = makeSupabase([{ content: '[hobby] אני אוהב פיצה' }]);
        const result = await runMemoryAgent('מחק זיכרון על פיצה', supabase);
        expect(supabase._chain.delete).toHaveBeenCalled();
        expect(supabase._chain.ilike).toHaveBeenCalledWith('content', '%פיצה%');
        expect(result.answer).toContain('מחקתי');
    });

    test('delete memory with no match → not found message', async () => {
        const supabase = makeSupabase([]);
        const result = await runMemoryAgent('מחק זיכרון על פיצה', supabase);
        expect(result.answer).toContain('לא מצאתי');
    });

    test('callGemma4 throws → error message', async () => {
        callGemma4.mockRejectedValue(new Error('API error'));
        const supabase = makeSupabase();
        const result = await runMemoryAgent('זכור ש חמש', supabase);
        expect(result.answer).toContain('הייתה בעיה בשמירת הזיכרון');
    });
});
