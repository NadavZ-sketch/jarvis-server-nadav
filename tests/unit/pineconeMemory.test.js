'use strict';

// pineconeMemory has module-level singleton state (_ready, _index, _initPromise).
// We reset all of it by calling jest.resetModules() + re-requiring everything
// fresh inside each test via setup().  The key rule: set up mock behaviour on
// the SAME fresh mock instances the module will use.

beforeEach(() => {
    jest.resetModules();
    jest.mock('axios');
    jest.mock('@pinecone-database/pinecone');
    delete process.env.PINECONE_API_KEY;
    delete process.env.GOOGLE_API_KEY;
});

// Returns fresh {mod, axios, Pinecone} all pointing at the same mock instances
function freshRequires() {
    const ax = require('axios');
    const { Pinecone } = require('@pinecone-database/pinecone');
    const mod = require('../../services/pineconeMemory');
    return { mod, ax, Pinecone };
}

// Standard Pinecone index mock
function makeIndexMock() {
    return {
        upsert:        jest.fn().mockResolvedValue({}),
        query:         jest.fn().mockResolvedValue({ matches: [] }),
        deleteOne:     jest.fn().mockResolvedValue({}),
        deleteMany:    jest.fn().mockResolvedValue({}),
        listPaginated: jest.fn().mockResolvedValue({ vectors: [], pagination: null }),
    };
}

function setupPinecone(Pinecone, { indexExists = true } = {}) {
    const idx = makeIndexMock();
    Pinecone.mockImplementation(() => ({
        listIndexes:   jest.fn().mockResolvedValue({ indexes: indexExists ? [{ name: 'jarvis-memories' }] : [] }),
        createIndex:   jest.fn().mockResolvedValue({}),
        describeIndex: jest.fn().mockResolvedValue({ status: { ready: true } }),
        index:         jest.fn().mockReturnValue(idx),
    }));
    return idx;
}

function setupEmbed(ax) {
    ax.post.mockResolvedValue({ data: { embedding: { values: new Array(768).fill(0.1) } } });
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

    test('becomes true after successful init with existing index', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, Pinecone } = freshRequires();
        setupPinecone(Pinecone, { indexExists: true });
        await mod.ensureInit();
        expect(mod.isReady()).toBe(true);
    });

    test('becomes true after auto-creating new index', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        jest.useFakeTimers();
        const { mod, Pinecone } = freshRequires();
        setupPinecone(Pinecone, { indexExists: false });
        const initPromise = mod.ensureInit();
        // Advance past the 5 s setTimeout in the ready-poll loop
        await jest.runAllTimersAsync();
        await initPromise;
        jest.useRealTimers();
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

    test('embeds content and upserts vector, returns true', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        process.env.GOOGLE_API_KEY   = 'gk-test';
        const { mod, ax, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        setupEmbed(ax);
        const result = await mod.upsertMemory('42', '[hobby] אוהב ריצה');
        expect(result).toBe(true);
        expect(idx.upsert).toHaveBeenCalledWith([
            expect.objectContaining({ id: '42', metadata: { content: '[hobby] אוהב ריצה' } }),
        ]);
    });

    test('converts numeric id to string', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, ax, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        setupEmbed(ax);
        await mod.upsertMemory(99, 'content');
        expect(idx.upsert).toHaveBeenCalledWith([expect.objectContaining({ id: '99' })]);
    });

    test('embed API failure → returns false', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, ax, Pinecone } = freshRequires();
        setupPinecone(Pinecone);
        ax.post.mockRejectedValue(new Error('embed API down'));
        expect(await mod.upsertMemory('1', 'content')).toBe(false);
    });

    test('Pinecone upsert failure → returns false', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, ax, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        setupEmbed(ax);
        idx.upsert.mockRejectedValue(new Error('upsert failed'));
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
        const { mod, ax, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        setupEmbed(ax);
        idx.query.mockResolvedValue({
            matches: [
                { score: 0.92, metadata: { content: '[health] אלרגי לבוטנים' } },
                { score: 0.73, metadata: { content: '[hobby] אוהב ריצה' } },
                { score: 0.40, metadata: { content: '[work] עובד בהייטק' } }, // below threshold
            ],
        });
        const results = await mod.searchMemories('בריאות');
        expect(results).toEqual(['[health] אלרגי לבוטנים', '[hobby] אוהב ריצה']);
    });

    test('all results below threshold → empty array', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, ax, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        setupEmbed(ax);
        idx.query.mockResolvedValue({ matches: [{ score: 0.3, metadata: { content: 'irrelevant' } }] });
        expect(await mod.searchMemories('query')).toEqual([]);
    });

    test('Pinecone query error → returns null', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, ax, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        setupEmbed(ax);
        idx.query.mockRejectedValue(new Error('query failed'));
        expect(await mod.searchMemories('query')).toBeNull();
    });

    test('passes topK parameter to Pinecone query', async () => {
        process.env.PINECONE_API_KEY = 'pk-test';
        const { mod, ax, Pinecone } = freshRequires();
        const idx = setupPinecone(Pinecone);
        setupEmbed(ax);
        idx.query.mockResolvedValue({ matches: [] });
        await mod.searchMemories('query', 5);
        expect(idx.query).toHaveBeenCalledWith(expect.objectContaining({ topK: 5 }));
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
