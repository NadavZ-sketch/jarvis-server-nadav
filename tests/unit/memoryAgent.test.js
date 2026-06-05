'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn(), removeFromVault: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
    upsertMemory:      jest.fn().mockResolvedValue(true),
    searchMemories:    jest.fn().mockResolvedValue(null),
    findSimilarMemory: jest.fn().mockResolvedValue(null),
    deleteMemory:      jest.fn().mockResolvedValue(),
    isReady:           jest.fn().mockReturnValue(false),
}));

const { callGemma4 }      = require('../../agents/models');
const pinecone             = require('../../services/pineconeMemory');
const { runMemoryAgent, autoExtractMemory, checkDuplicate } = require('../../agents/memoryAgent');

// ─── Supabase mock helpers ────────────────────────────────────────────────────

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
    pinecone.isReady.mockReturnValue(false);
    pinecone.searchMemories.mockResolvedValue(null);
    pinecone.findSimilarMemory.mockResolvedValue(null);
});

// ─── runMemoryAgent: save ─────────────────────────────────────────────────────

describe('runMemoryAgent — save', () => {
    // All save tests need Pinecone to be "ready" so checkDuplicate trusts
    // findSimilarMemory(null) and does NOT fall back to the ilike path that
    // would falsely match the test data already in the mock chain.
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('saves memory with long_term scope when explicit save keyword used', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] אני אוהב פיצה"}');
        const supabase = makeSupabase([{ id: 1, content: '[hobby] אני אוהב פיצה' }]);
        const result = await runMemoryAgent('זכור ש אני אוהב פיצה', supabase);
        expect(supabase.from).toHaveBeenCalledWith('memories');
        expect(supabase._chain.insert).toHaveBeenCalledWith([
            { content: '[hobby] אני אוהב פיצה', scope: 'long_term' }
        ]);
        expect(result.answer).toContain('שמרתי');
    });

    test('upserts to Pinecone after saving', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] ריצה"}');
        const supabase = makeSupabase([{ id: 42 }]);
        await runMemoryAgent('זכור ש אני אוהב ריצה', supabase);
        expect(pinecone.upsertMemory).toHaveBeenCalledWith(42, '[hobby] ריצה');
    });

    test('LLM returns no JSON → error message', async () => {
        callGemma4.mockResolvedValue('I cannot do that.');
        const supabase = makeSupabase();
        const result = await runMemoryAgent('זכור ש כל מיני', supabase);
        expect(result.answer).toContain('הייתה בעיה בשמירת הזיכרון');
    });

    test('JSON with braces inside content value is parsed correctly', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[health] אלרגי ל{בוטנים} ול{שקדים}"}');
        const supabase = makeSupabase([{ id: 1 }]);
        await runMemoryAgent('זכור ש אני אלרגי לבוטנים', supabase);
        expect(supabase._chain.insert).toHaveBeenCalledWith([
            { content: '[health] אלרגי ל{בוטנים} ול{שקדים}', scope: 'long_term' }
        ]);
    });

    test('LLM preamble before JSON is skipped correctly', async () => {
        callGemma4.mockResolvedValue('הנה הזיכרון שלך: {"memoryContent":"[hobby] אוהב ריצה"}');
        const supabase = makeSupabase([{ id: 1 }]);
        await runMemoryAgent('זכור ש אני אוהב ריצה', supabase);
        expect(supabase._chain.insert).toHaveBeenCalledWith([
            { content: '[hobby] אוהב ריצה', scope: 'long_term' }
        ]);
    });

    test('duplicate detected (Pinecone) → suggests update instead of save', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] אני אוהב פיצה"}');
        pinecone.findSimilarMemory.mockResolvedValue({ id: '5', content: '[hobby] אני אוהב פיצה', score: 0.97 });
        const supabase = makeSupabase([]);
        const result = await runMemoryAgent('זכור ש אני אוהב פיצה', supabase);
        expect(supabase._chain.insert).not.toHaveBeenCalled();
        expect(result.answer).toContain('עדכן זיכרון');
    });

    test('callGemma4 throws → error message', async () => {
        callGemma4.mockRejectedValue(new Error('API error'));
        const supabase = makeSupabase();
        const result = await runMemoryAgent('זכור ש חמש', supabase);
        expect(result.answer).toContain('הייתה בעיה בשמירת הזיכרון');
    });
});

// ─── runMemoryAgent: recall ───────────────────────────────────────────────────

describe('runMemoryAgent — recall', () => {
    test('fetches memories and passes to LLM', async () => {
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

    test('uses Pinecone semantic results when Pinecone is ready', async () => {
        pinecone.isReady.mockReturnValue(true);
        pinecone.searchMemories.mockResolvedValue(['[hobby] פיצה', '[location] תל אביב']);
        callGemma4.mockResolvedValue('אתה אוהב פיצה וגר בתל אביב.');
        const supabase = makeSupabase([]);
        const result = await runMemoryAgent('מה אני אוהב', supabase);
        expect(pinecone.searchMemories).toHaveBeenCalled();
        expect(supabase.from).not.toHaveBeenCalled();
        expect(result.answer).toContain('פיצה');
    });

    test('no memories → no memories message without calling LLM', async () => {
        const supabase = makeSupabase([]);
        const result = await runMemoryAgent('מה אתה יודע עליי', supabase);
        expect(callGemma4).not.toHaveBeenCalled();
        expect(result.answer).toContain('אין לי עדיין זיכרונות');
    });
});

// ─── runMemoryAgent: delete ───────────────────────────────────────────────────

describe('runMemoryAgent — delete', () => {
    test('deletes memory by ilike and confirms', async () => {
        const supabase = makeSupabase([{ id: 3, content: '[hobby] אני אוהב פיצה' }]);
        const result = await runMemoryAgent('מחק זיכרון על פיצה', supabase);
        expect(supabase._chain.delete).toHaveBeenCalled();
        expect(supabase._chain.ilike).toHaveBeenCalledWith('content', '%פיצה%');
        expect(result.answer).toContain('מחקתי');
    });

    test('deletes corresponding Pinecone vector', async () => {
        const supabase = makeSupabase([{ id: 7, content: '[hobby] פיצה' }]);
        await runMemoryAgent('מחק זיכרון על פיצה', supabase);
        expect(pinecone.deleteMemory).toHaveBeenCalledWith(7);
    });

    test('no match → not found message', async () => {
        const supabase = makeSupabase([]);
        const result = await runMemoryAgent('מחק זיכרון על פיצה', supabase);
        expect(result.answer).toContain('לא מצאתי');
    });
});

// ─── runMemoryAgent: update ───────────────────────────────────────────────────

describe('runMemoryAgent — update', () => {
    test('updates memory in Supabase and re-upserts in Pinecone', async () => {
        callGemma4.mockResolvedValue('{"newContent":"[location] גר בירושלים"}');
        const findChain = makeChain([{ id: 9, content: '[location] גר בתל אביב' }]);
        const updateChain = makeChain([{ id: 9, content: '[location] גר בירושלים' }]);
        let callCount = 0;
        const supabase = {
            from: jest.fn(() => {
                callCount++;
                return callCount === 1 ? findChain : updateChain;
            }),
        };
        const result = await runMemoryAgent('עדכן זיכרון על מיקום גר בירושלים', supabase);
        expect(supabase.from).toHaveBeenCalledWith('memories');
        expect(updateChain.update).toHaveBeenCalledWith({ content: '[location] גר בירושלים' });
        expect(pinecone.upsertMemory).toHaveBeenCalledWith(9, '[location] גר בירושלים');
        expect(result.answer).toContain('עדכנתי');
    });

    test('memory not found during update → not found message', async () => {
        const supabase = makeSupabase([]);
        const result = await runMemoryAgent('עדכן זיכרון על מיקום', supabase);
        expect(result.answer).toContain('לא מצאתי');
    });
});

// ─── checkDuplicate ───────────────────────────────────────────────────────────

describe('checkDuplicate', () => {
    test('returns duplicate=true when Pinecone finds similar', async () => {
        pinecone.findSimilarMemory.mockResolvedValue({ id: '5', content: '[hobby] פיצה', score: 0.95 });
        const supabase = makeSupabase([]);
        const result = await checkDuplicate('[hobby] אני אוהב פיצה', supabase);
        expect(result.duplicate).toBe(true);
        expect(result.existingId).toBe('5');
    });

    test('returns duplicate=false when Pinecone finds no similar', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        pinecone.isReady.mockReturnValue(true);
        const supabase = makeSupabase([]);
        const result = await checkDuplicate('[hobby] אני אוהב ריצה', supabase);
        expect(result.duplicate).toBe(false);
    });

    test('falls back to ilike when Pinecone is not ready', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        pinecone.isReady.mockReturnValue(false);
        const supabase = makeSupabase([{ id: '2' }]);
        const result = await checkDuplicate('[hobby] אני אוהב פיצה', supabase);
        expect(supabase.from).toHaveBeenCalledWith('memories');
        expect(result.duplicate).toBe(true);
    });

    test('no duplicate in ilike fallback returns false', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        pinecone.isReady.mockReturnValue(false);
        const supabase = makeSupabase([]);
        const result = await checkDuplicate('[hobby] אני אוהב ריצה', supabase);
        expect(result.duplicate).toBe(false);
    });

    test('empty content returns duplicate=false immediately', async () => {
        const supabase = makeSupabase([]);
        const result = await checkDuplicate('', supabase);
        expect(result.duplicate).toBe(false);
        expect(pinecone.findSimilarMemory).not.toHaveBeenCalled();
    });
});

// ─── autoExtractMemory ────────────────────────────────────────────────────────

describe('autoExtractMemory', () => {
    // Need isReady=true so checkDuplicate trusts Pinecone's "no match" and
    // doesn't fall back to ilike on the test chain.
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('extracts and saves a long_term fact', async () => {
        callGemma4.mockResolvedValue('{"items":[{"content":"[location] גר בתל אביב","scope":"long_term"}]}');
        const supabase = makeSupabase([{ id: 10, content: '[location] גר בתל אביב' }]);
        await autoExtractMemory('אני גר בתל אביב', 'מעולה, שמרתי!', supabase, {});
        expect(supabase.from).toHaveBeenCalledWith('memories');
        expect(supabase._chain.insert).toHaveBeenCalledWith([
            { content: '[location] גר בתל אביב', scope: 'long_term' }
        ]);
    });

    test('skips extraction for weather queries', async () => {
        await autoExtractMemory('מה מזג האוויר בתל אביב', 'חם ושמשי', makeSupabase([]), {});
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('skips very short messages', async () => {
        await autoExtractMemory('כן', 'אוקיי', makeSupabase([]), {});
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('does not save when LLM returns empty items', async () => {
        callGemma4.mockResolvedValue('{"items":[]}');
        const supabase = makeSupabase([]);
        await autoExtractMemory('מה שלומך היום?', 'בסדר גמור!', supabase, {});
        expect(supabase._chain.insert).not.toHaveBeenCalled();
    });

    test('skips duplicate detected by Pinecone', async () => {
        callGemma4.mockResolvedValue('{"items":[{"content":"[hobby] פיצה","scope":"long_term"}]}');
        pinecone.findSimilarMemory.mockResolvedValue({ id: '1', content: '[hobby] פיצה', score: 0.97 });
        const supabase = makeSupabase([]);
        await autoExtractMemory('אני אוהב פיצה', 'שמרתי', supabase, {});
        expect(supabase._chain.insert).not.toHaveBeenCalled();
    });

    test('saves up to 3 items max', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ items: [
            { content: '[a] א', scope: 'long_term' },
            { content: '[b] ב', scope: 'long_term' },
            { content: '[c] ג', scope: 'long_term' },
            { content: '[d] ד', scope: 'long_term' }, // 4th — should be ignored
        ]}));
        const supabase = makeSupabase([{ id: 1 }, { id: 2 }, { id: 3 }]);
        await autoExtractMemory('יש לי הרבה מידע לשמור היום', 'כן', supabase, {});
        expect(supabase._chain.insert).toHaveBeenCalledTimes(3);
    });

    test('does not throw when LLM returns invalid JSON', async () => {
        callGemma4.mockResolvedValue('not valid json at all');
        const supabase = makeSupabase([]);
        await expect(autoExtractMemory('נתון כלשהו', 'תשובה', supabase, {})).resolves.toBeUndefined();
    });
});
