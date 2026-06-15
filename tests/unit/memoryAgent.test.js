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
const { runMemoryAgent, autoExtractMemory, checkDuplicate, findConflict } = require('../../agents/memoryAgent');
const { makeRepos, makeMemoryRepo } = require('../helpers/fakeRepos');

beforeEach(() => {
    jest.clearAllMocks();
    pinecone.isReady.mockReturnValue(false);
    pinecone.searchMemories.mockResolvedValue(null);
    pinecone.findSimilarMemory.mockResolvedValue(null);
});

// ─── runMemoryAgent: save ─────────────────────────────────────────────────────

describe('runMemoryAgent — save', () => {
    // All save tests need Pinecone "ready" so checkDuplicate trusts
    // findSimilarMemory(null) and does NOT fall back to the ilike path.
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('saves memory with long_term scope when explicit save keyword used', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] אני אוהב פיצה"}');
        const repos = makeRepos({ memories: [{ id: 1, content: '[hobby] אני אוהב פיצה' }] });
        const result = await runMemoryAgent('זכור ש אני אוהב פיצה', repos);
        expect(repos.memories.insert).toHaveBeenCalledWith({ content: '[hobby] אני אוהב פיצה', scope: 'long_term' });
        expect(result.answer).toContain('שמרתי');
    });

    test('upserts to Pinecone after saving', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] ריצה"}');
        const repos = makeRepos({ memories: [{ id: 42 }] });
        await runMemoryAgent('זכור ש אני אוהב ריצה', repos);
        expect(pinecone.upsertMemory).toHaveBeenCalledWith(42, '[hobby] ריצה');
    });

    test('LLM returns no JSON → error message', async () => {
        callGemma4.mockResolvedValue('I cannot do that.');
        const result = await runMemoryAgent('זכור ש כל מיני', makeRepos());
        expect(result.answer).toContain('הייתה בעיה בשמירת הזיכרון');
    });

    test('JSON with braces inside content value is parsed correctly', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[health] אלרגי ל{בוטנים} ול{שקדים}"}');
        const repos = makeRepos({ memories: [{ id: 1 }] });
        await runMemoryAgent('זכור ש אני אלרגי לבוטנים', repos);
        expect(repos.memories.insert).toHaveBeenCalledWith({ content: '[health] אלרגי ל{בוטנים} ול{שקדים}', scope: 'long_term' });
    });

    test('LLM preamble before JSON is skipped correctly', async () => {
        callGemma4.mockResolvedValue('הנה הזיכרון שלך: {"memoryContent":"[hobby] אוהב ריצה"}');
        const repos = makeRepos({ memories: [{ id: 1 }] });
        await runMemoryAgent('זכור ש אני אוהב ריצה', repos);
        expect(repos.memories.insert).toHaveBeenCalledWith({ content: '[hobby] אוהב ריצה', scope: 'long_term' });
    });

    test('duplicate detected (Pinecone) → suggests update instead of save', async () => {
        callGemma4.mockResolvedValue('{"memoryContent":"[hobby] אני אוהב פיצה"}');
        pinecone.findSimilarMemory.mockResolvedValue({ id: '5', content: '[hobby] אני אוהב פיצה', score: 0.97 });
        const repos = makeRepos({ memories: [] });
        const result = await runMemoryAgent('זכור ש אני אוהב פיצה', repos);
        expect(repos.memories.insert).not.toHaveBeenCalled();
        expect(result.answer).toContain('עדכן זיכרון');
    });

    test('callGemma4 throws → error message', async () => {
        callGemma4.mockRejectedValue(new Error('API error'));
        const result = await runMemoryAgent('זכור ש חמש', makeRepos());
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
        const repos = makeRepos({ memories });
        const result = await runMemoryAgent('מה אתה יודע עליי', repos);
        expect(repos.memories.allContents).toHaveBeenCalled();
        const prompt = callGemma4.mock.calls[0][0];
        expect(prompt).toContain('[hobby] אני אוהב פיצה');
        expect(result.answer).toContain('פיצה');
    });

    test('uses Pinecone semantic results when Pinecone is ready', async () => {
        pinecone.isReady.mockReturnValue(true);
        pinecone.searchMemories.mockResolvedValue(['[hobby] פיצה', '[location] תל אביב']);
        callGemma4.mockResolvedValue('אתה אוהב פיצה וגר בתל אביב.');
        const repos = makeRepos({ memories: [] });
        const result = await runMemoryAgent('מה אני אוהב', repos);
        expect(pinecone.searchMemories).toHaveBeenCalled();
        expect(repos.memories.allContents).not.toHaveBeenCalled();
        expect(result.answer).toContain('פיצה');
    });

    test('no memories → no memories message without calling LLM', async () => {
        const result = await runMemoryAgent('מה אתה יודע עליי', makeRepos({ memories: [] }));
        expect(callGemma4).not.toHaveBeenCalled();
        expect(result.answer).toContain('אין לי עדיין זיכרונות');
    });
});

// ─── runMemoryAgent: delete ───────────────────────────────────────────────────

describe('runMemoryAgent — delete', () => {
    test('deletes memory by content and confirms', async () => {
        const repos = makeRepos({ memories: [{ id: 3, content: '[hobby] אני אוהב פיצה' }] });
        const result = await runMemoryAgent('מחק זיכרון על פיצה', repos);
        expect(repos.memories.deleteByContent).toHaveBeenCalledWith('פיצה');
        expect(result.answer).toContain('מחקתי');
    });

    test('deletes corresponding Pinecone vector', async () => {
        const repos = makeRepos({ memories: [{ id: 7, content: '[hobby] פיצה' }] });
        await runMemoryAgent('מחק זיכרון על פיצה', repos);
        expect(pinecone.deleteMemory).toHaveBeenCalledWith(7);
    });

    test('no match → not found message', async () => {
        const result = await runMemoryAgent('מחק זיכרון על פיצה', makeRepos({ memories: [] }));
        expect(result.answer).toContain('לא מצאתי');
    });
});

// ─── runMemoryAgent: update ───────────────────────────────────────────────────

describe('runMemoryAgent — update', () => {
    test('updates memory in Supabase and re-upserts in Pinecone', async () => {
        callGemma4.mockResolvedValue('{"newContent":"[location] גר בירושלים"}');
        const repos = makeRepos({ memories: [{ id: 9, content: '[location] גר בתל אביב' }] });
        const result = await runMemoryAgent('עדכן זיכרון על מיקום גר בירושלים', repos);
        expect(repos.memories.update).toHaveBeenCalledWith(9, '[location] גר בירושלים');
        expect(pinecone.upsertMemory).toHaveBeenCalledWith(9, '[location] גר בירושלים');
        expect(result.answer).toContain('עדכנתי');
    });

    test('memory not found during update → not found message', async () => {
        const result = await runMemoryAgent('עדכן זיכרון על מיקום', makeRepos({ memories: [] }));
        expect(result.answer).toContain('לא מצאתי');
    });
});

// ─── checkDuplicate ───────────────────────────────────────────────────────────

describe('checkDuplicate', () => {
    test('returns duplicate=true when Pinecone finds similar', async () => {
        pinecone.findSimilarMemory.mockResolvedValue({ id: '5', content: '[hobby] פיצה', score: 0.95 });
        const result = await checkDuplicate('[hobby] אני אוהב פיצה', makeMemoryRepo());
        expect(result.duplicate).toBe(true);
        expect(result.existingId).toBe('5');
    });

    test('returns duplicate=false when Pinecone finds no similar', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        pinecone.isReady.mockReturnValue(true);
        const result = await checkDuplicate('[hobby] אני אוהב ריצה', makeMemoryRepo());
        expect(result.duplicate).toBe(false);
    });

    test('falls back to findByContent when Pinecone is not ready', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        pinecone.isReady.mockReturnValue(false);
        const memories = makeMemoryRepo({ rows: [{ id: '2' }] });
        const result = await checkDuplicate('[hobby] אני אוהב פיצה', memories);
        expect(memories.findByContent).toHaveBeenCalled();
        expect(result.duplicate).toBe(true);
    });

    test('no duplicate in fallback returns false', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        pinecone.isReady.mockReturnValue(false);
        const result = await checkDuplicate('[hobby] אני אוהב ריצה', makeMemoryRepo({ rows: [] }));
        expect(result.duplicate).toBe(false);
    });

    test('empty content returns duplicate=false immediately', async () => {
        const result = await checkDuplicate('', makeMemoryRepo());
        expect(result.duplicate).toBe(false);
        expect(pinecone.findSimilarMemory).not.toHaveBeenCalled();
    });
});

// ─── autoExtractMemory ────────────────────────────────────────────────────────

describe('autoExtractMemory', () => {
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('extracts a fact and stores it as pending (not saved directly)', async () => {
        callGemma4.mockResolvedValue('{"memories":[{"type":"fact","content":"[location] גר בתל אביב"}]}');
        const repos = makeRepos({ memories: [{ id: 10, content: '[location] גר בתל אביב' }] });
        const result = await autoExtractMemory('אני גר בתל אביב כבר שלוש שנים ונהנה מהעיר מאוד', 'מעולה, שמרתי!', repos, {}, 'chat-x');
        // fact type → pending, not saved directly
        expect(repos.memories.insert).not.toHaveBeenCalled();
        expect(result).toMatchObject({ content: '[location] גר בתל אביב' });
    });

    test('skips extraction for weather queries', async () => {
        await autoExtractMemory('מה מזג האוויר בתל אביב', 'חם ושמשי', makeRepos(), {});
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('skips very short messages', async () => {
        await autoExtractMemory('כן', 'אוקיי', makeRepos(), {});
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('does not save when LLM returns empty memories', async () => {
        callGemma4.mockResolvedValue('{"memories":[]}');
        const repos = makeRepos({ memories: [] });
        await autoExtractMemory('מה שלומך היום?', 'בסדר גמור!', repos, {});
        expect(repos.memories.insert).not.toHaveBeenCalled();
    });

    test('skips duplicate detected by Pinecone (score > 0.92)', async () => {
        callGemma4.mockResolvedValue('{"memories":[{"type":"fact","content":"[hobby] פיצה"}]}');
        pinecone.findSimilarMemory.mockResolvedValue({ id: '1', content: '[hobby] פיצה', score: 0.97 });
        const repos = makeRepos({ memories: [] });
        const result = await autoExtractMemory('אני אוהב פיצה ומעדיף אותה על פני כל מאכל אחר', 'שמרתי', repos, {});
        expect(repos.memories.insert).not.toHaveBeenCalled();
        // duplicate → returns null (no pending either)
        expect(result).toBeNull();
    });

    test('saves up to 3 context items max (auto-save for context type)', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ memories: [
            { type: 'context', content: '[context] א' },
            { type: 'context', content: '[context] ב' },
            { type: 'context', content: '[context] ג' },
            { type: 'context', content: '[context] ד' }, // 4th — should be ignored
        ]}));
        const repos = makeRepos({ memories: [{ id: 1 }] });
        await autoExtractMemory('יש לי הרבה מידע חשוב לשמור היום לגבי הפרויקט החדש', 'כן', repos, {});
        expect(repos.memories.insert).toHaveBeenCalledTimes(3);
    });

    test('does not throw when LLM returns invalid JSON', async () => {
        callGemma4.mockResolvedValue('not valid json at all');
        await expect(autoExtractMemory('נתון כלשהו', 'תשובה', makeRepos(), {})).resolves.toBeNull();
    });
});

// ─── findConflict ──────────────────────────────────────────────────────────────

describe('findConflict', () => {
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('returns "new" when no similar memory found', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        const result = await findConflict('[fact] גר בירושלים');
        expect(result.type).toBe('new');
    });

    test('returns "duplicate" when similarity > 0.92', async () => {
        pinecone.findSimilarMemory.mockResolvedValue({ id: '5', content: '[fact] גר בירושלים', score: 0.95 });
        const result = await findConflict('[fact] גר בירושלים');
        expect(result.type).toBe('duplicate');
    });

    test('returns "update" when similarity is 0.70-0.92', async () => {
        pinecone.findSimilarMemory.mockResolvedValue({ id: '3', content: '[fact] גר בתל אביב', score: 0.80 });
        const result = await findConflict('[fact] גר בירושלים');
        expect(result.type).toBe('update');
        expect(result.existingId).toBe('3');
        expect(result.existingContent).toBe('[fact] גר בתל אביב');
    });
});

// ─── autoExtractMemory: new prompt types ─────────────────────────────────────

describe('autoExtractMemory — 3-type extraction', () => {
    beforeEach(() => pinecone.isReady.mockReturnValue(true));

    test('does NOT skip reminder intent (relaxed skip)', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        callGemma4.mockResolvedValue('{"memories":[{"type":"fact","content":"[fact] גר בתל אביב"}]}');
        const repos = makeRepos();
        // "תזמין לי פיצה" has reminder keyword but is ≥20 chars — should not skip
        await autoExtractMemory('תזמין לי פיצה לרחוב הרצל 5 בתל אביב', 'הזמנתי!', repos);
        expect(callGemma4).toHaveBeenCalled();
    });

    test('skips messages shorter than 20 chars', async () => {
        const repos = makeRepos();
        await autoExtractMemory('תודה', 'בשמחה', repos);
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('pending stored when new fact detected', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        callGemma4.mockResolvedValue('{"memories":[{"type":"fact","content":"[fact] גר בירושלים"}]}');
        const repos = makeRepos();
        const result = await autoExtractMemory(
            'אני גר בירושלים בשכונת גילה', 'נהדר!', repos, {}, 'chat-1'
        );
        // Should NOT save immediately — returns pending object
        expect(repos.memories.insert).not.toHaveBeenCalled();
        expect(result).toMatchObject({ type: 'new', content: '[fact] גר בירושלים' });
    });

    test('[context] type is saved directly (no confirmation needed)', async () => {
        pinecone.findSimilarMemory.mockResolvedValue(null);
        callGemma4.mockResolvedValue('{"memories":[{"type":"context","content":"[context] עובד על מצגת"}]}');
        const repos = makeRepos({ memories: [{ id: 9 }] });
        await autoExtractMemory('מחר יש לי הצגה של המצגת לצוות', 'בהצלחה!', repos, {}, 'chat-2');
        expect(repos.memories.insert).toHaveBeenCalledWith({ content: '[context] עובד על מצגת', scope: 'session' });
    });
});
