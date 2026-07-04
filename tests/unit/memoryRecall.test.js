'use strict';

// Mock the Pinecone memory layer so we control isReady()/searchMemoriesDetailed()
// per test. NB: pineconeMemory.js is an integrated-inference index (embeds
// server-side via upsertRecords/searchRecords), so there is no local embed()
// call to mock here — semantic ranking goes through searchMemoriesDetailed.
jest.mock('../../services/pineconeMemory', () => ({
    isReady: jest.fn(),
    searchMemoriesDetailed: jest.fn(),
}));

const pinecone = require('../../services/pineconeMemory');
const { filterRelevantMemoriesAsync, getMemoryRecallStats } = require('../../agents/chatAgent');

const manyMemories = Array.from({ length: 12 }, (_, i) => `- זיכרון מספר ${i}`).join('\n');

beforeEach(() => {
    pinecone.isReady.mockReset();
    pinecone.searchMemoriesDetailed.mockReset();
});

describe('filterRelevantMemoriesAsync', () => {
    it('returns text unchanged when at or below topK lines', async () => {
        const few = '- א\n- ב';
        expect(await filterRelevantMemoriesAsync(few, 'שאלה')).toBe(few);
        expect(pinecone.searchMemoriesDetailed).not.toHaveBeenCalled();
    });

    it('uses the semantic path and counts a hit when Pinecone is ready', async () => {
        pinecone.isReady.mockReturnValue(true);
        // Pinecone's own top-K search returns hits already ranked by relevance;
        // content matches candidate lines after stripping the leading "- ".
        pinecone.searchMemoriesDetailed.mockResolvedValue(
            Array.from({ length: 5 }, (_, i) => ({ id: `${i}`, content: `זיכרון מספר ${i}`, score: 1 - i * 0.1 })),
        );

        const before = getMemoryRecallStats().semantic;
        const out = await filterRelevantMemoriesAsync(manyMemories, 'שאלה כלשהי', 5);
        expect(out.split('\n')).toHaveLength(5);
        expect(getMemoryRecallStats().semantic).toBe(before + 1);
    });

    it('falls back to token ranking and counts a fallback when Pinecone is down', async () => {
        pinecone.isReady.mockReturnValue(false);
        const before = getMemoryRecallStats().fallback;
        const out = await filterRelevantMemoriesAsync(manyMemories, 'זיכרון מספר 3', 5);
        expect(out.length).toBeGreaterThan(0);
        expect(getMemoryRecallStats().fallback).toBe(before + 1);
        expect(pinecone.searchMemoriesDetailed).not.toHaveBeenCalled();
    });

    it('falls back when the search throws', async () => {
        pinecone.isReady.mockReturnValue(true);
        pinecone.searchMemoriesDetailed.mockRejectedValue(new Error('search boom'));
        const before = getMemoryRecallStats().fallback;
        const out = await filterRelevantMemoriesAsync(manyMemories, 'שאלה', 5);
        expect(out.length).toBeGreaterThan(0);
        expect(getMemoryRecallStats().fallback).toBe(before + 1);
    });

    it('falls back when no returned hit matches a candidate line', async () => {
        pinecone.isReady.mockReturnValue(true);
        pinecone.searchMemoriesDetailed.mockResolvedValue([
            { id: 'x', content: 'זיכרון שלא קיים ברשימת המועמדים', score: 0.9 },
        ]);
        const before = getMemoryRecallStats().fallback;
        const out = await filterRelevantMemoriesAsync(manyMemories, 'שאלה', 5);
        expect(out.length).toBeGreaterThan(0);
        expect(getMemoryRecallStats().fallback).toBe(before + 1);
    });
});
