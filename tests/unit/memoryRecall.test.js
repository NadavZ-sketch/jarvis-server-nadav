'use strict';

// Mock the Pinecone memory layer so we control isReady()/embed() per test.
jest.mock('../../services/pineconeMemory', () => ({
    isReady: jest.fn(),
    embed: jest.fn(),
}));

const pinecone = require('../../services/pineconeMemory');
const { filterRelevantMemoriesAsync, getMemoryRecallStats } = require('../../agents/chatAgent');

const manyMemories = Array.from({ length: 12 }, (_, i) => `- זיכרון מספר ${i}`).join('\n');

beforeEach(() => {
    pinecone.isReady.mockReset();
    pinecone.embed.mockReset();
});

describe('filterRelevantMemoriesAsync', () => {
    it('returns text unchanged when at or below topK lines', async () => {
        const few = '- א\n- ב';
        expect(await filterRelevantMemoriesAsync(few, 'שאלה')).toBe(few);
        expect(pinecone.embed).not.toHaveBeenCalled();
    });

    it('uses the semantic path and counts a hit when Pinecone is ready', async () => {
        pinecone.isReady.mockReturnValue(true);
        // Deterministic fake embedding: vector based on string length.
        pinecone.embed.mockImplementation(async (t) => [t.length, 1, 0]);

        const before = getMemoryRecallStats().semantic;
        const out = await filterRelevantMemoriesAsync(manyMemories, 'שאלה כלשהי', 5);
        expect(out.split('\n')).toHaveLength(5);
        expect(getMemoryRecallStats().semantic).toBe(before + 1);
    });

    it('caches memory-line embeddings across calls (query re-embedded, lines not)', async () => {
        pinecone.isReady.mockReturnValue(true);
        pinecone.embed.mockImplementation(async (t) => [t.length, 1, 0]);

        await filterRelevantMemoriesAsync(manyMemories, 'שאלה ראשונה', 5);
        const afterFirst = pinecone.embed.mock.calls.length;
        await filterRelevantMemoriesAsync(manyMemories, 'שאלה שנייה', 5);
        const afterSecond = pinecone.embed.mock.calls.length;
        // Second call should only re-embed the query (1 call), not all 12 lines.
        expect(afterSecond - afterFirst).toBe(1);
    });

    it('falls back to token ranking and counts a fallback when Pinecone is down', async () => {
        pinecone.isReady.mockReturnValue(false);
        const before = getMemoryRecallStats().fallback;
        const out = await filterRelevantMemoriesAsync(manyMemories, 'זיכרון מספר 3', 5);
        expect(out.length).toBeGreaterThan(0);
        expect(getMemoryRecallStats().fallback).toBe(before + 1);
        expect(pinecone.embed).not.toHaveBeenCalled();
    });

    it('falls back when embedding throws', async () => {
        pinecone.isReady.mockReturnValue(true);
        pinecone.embed.mockRejectedValue(new Error('embed boom'));
        const before = getMemoryRecallStats().fallback;
        const out = await filterRelevantMemoriesAsync(manyMemories, 'שאלה', 5);
        expect(out.length).toBeGreaterThan(0);
        expect(getMemoryRecallStats().fallback).toBe(before + 1);
    });
});
