'use strict';

beforeEach(() => {
    jest.resetModules();
    jest.mock('@pinecone-database/pinecone');
    delete process.env.PINECONE_API_KEY;
});

function freshRequires() {
    const { Pinecone } = require('@pinecone-database/pinecone');
    const mod = require('../../services/pineconeMemory');
    return { mod, Pinecone };
}

function makeIndexMock() {
    return {
        upsertRecords:  jest.fn().mockResolvedValue({}),
        searchRecords:  jest.fn().mockResolvedValue({ result: { hits: [] } }),
        deleteOne:      jest.fn().mockResolvedValue({}),
        deleteMany:     jest.fn().mockResolvedValue({}),
        listPaginated:  jest.fn().mockResolvedValue({ vectors: [], pagination: null }),
    };
}

function setupPinecone(Pinecone) {
    const idx = makeIndexMock();
    Pinecone.mockImplementation(() => ({
        index: jest.fn().mockReturnValue(idx),
    }));
    return idx;
}

// ── isReady / init ────────────────────────────────────────────────────────────

describe('isReady', () => {
    test('returns false before any init', () => {
        const { mod } = freshRequires();
        expect(mod.isReady()).toBe(false);
    });

    test('stays false when PINECONE_API_KEY not set', async () => {
        const { mod } = freshRequires();
        await mod.ensureInit();
        expect(mod.isReady()).toBe(false);
    });

    test('becomes true after successful init', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        setupPinecone(Pinecone);
        await mod.ensureInit();
        expect(mod.isReady()).toBe(true);
    });

    test('stays false when Pinecone constructor throws', async () => {
        process.env.PINECONE_API_KEY = 'pk-bad';
        const { mod, Pinecone } = freshRequires();
        Pinecone.mockImplementation(() => { throw new Error('connection refused'); });
        await mod.ensureInit();
        expect(mod.isReady()).toBe(false);
    });

    test('ensureInit is idempotent — Pinecone constructor called only once', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        setupPinecone(Pinecone);
        await mod.ensureInit();
        await mod.ensureInit();
        await mod.ensureInit();
        expect(Pinecone).toHaveBeenCalledTimes(1);
    });
});

// ── upsertMemory ──────────────────────────────────────────────────────────────

describe('upsertMemory', () => {
    test('returns false when not ready (no API key)', async () => {
        const { mod } = freshRequires();
        expect(await mod.upsertMemory('1', 'content')).toBe(false);
    });

    test('upserts record with text, returns true', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        const result = await mod.upsertMemory('42', '[hobby] אוהב ריצה');
        expect(result).toBe(true);
        expect(idx.upsertRecords).toHaveBeenCalledWith([
            expect.objectContaining({ id: '42', text: '[hobby] אוהב ריצה' }),
        ]);
    });

    test('converts numeric id to string', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        await mod.upsertMemory(99, 'content');
        expect(idx.upsertRecords).toHaveBeenCalledWith([expect.objectContaining({ id: '99' })]);
    });

    test('upsertRecords failure → returns false', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        idx.upsertRecords.mockRejectedValue(new Error('upsert failed'));
        expect(await mod.upsertMemory('1', 'content')).toBe(false);
    });
});

// ── searchMemories ────────────────────────────────────────────────────────────

describe('searchMemories', () => {
    test('returns null when not ready', async () => {
        const { mod } = freshRequires();
        expect(await mod.searchMemories('query')).toBeNull();
    });

    test('returns memories above score threshold (0.55)', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        idx.searchRecords.mockResolvedValue({
            result: {
                hits: [
                    { _id: '1', _score: 0.92, fields: { text: '[health] אלרגי לבוטנים' } },
                    { _id: '2', _score: 0.73, fields: { text: '[hobby] אוהב ריצה' } },
                    { _id: '3', _score: 0.40, fields: { text: '[work] עובד בהייטק' } },
                ],
            },
        });
        const results = await mod.searchMemories('בריאות');
        expect(results).toEqual(['[health] אלרגי לבוטנים', '[hobby] אוהב ריצה']);
    });

    test('all results below threshold → empty array', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        idx.searchRecords.mockResolvedValue({
            result: { hits: [{ _id: '1', _score: 0.3, fields: { text: 'irrelevant' } }] },
        });
        expect(await mod.searchMemories('query')).toEqual([]);
    });

    test('searchRecords error → returns null', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        idx.searchRecords.mockRejectedValue(new Error('search failed'));
        expect(await mod.searchMemories('query')).toBeNull();
    });

    test('passes topK parameter to searchRecords', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        await mod.searchMemories('query', 5);
        expect(idx.searchRecords).toHaveBeenCalledWith(
            expect.objectContaining({ query: expect.objectContaining({ topK: 5 }) })
        );
    });
});

// ── deleteMemory ──────────────────────────────────────────────────────────────

describe('deleteMemory', () => {
    test('does nothing silently when not ready', async () => {
        const { mod } = freshRequires();
        await expect(mod.deleteMemory('1')).resolves.not.toThrow();
    });

    test('calls deleteOne with string id', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        await mod.ensureInit();
        await mod.deleteMemory(99);
        expect(idx.deleteOne).toHaveBeenCalledWith('99');
    });

    test('deleteOne error is swallowed silently', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        idx.deleteOne.mockRejectedValue(new Error('not found'));
        await mod.ensureInit();
        await expect(mod.deleteMemory('1')).resolves.not.toThrow();
    });
});
