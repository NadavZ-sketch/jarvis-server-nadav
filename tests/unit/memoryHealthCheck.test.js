'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
    isReady: jest.fn().mockReturnValue(true),
    searchMemoriesDetailed: jest.fn(),
    listAll: jest.fn().mockResolvedValue([]),
    upsertMemory: jest.fn().mockResolvedValue(true),
    deleteMemory: jest.fn().mockResolvedValue(),
}));
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const pinecone = require('../../services/pineconeMemory');
const { classifyCategory } = require('../../services/memoryCategory');
const { runHealthScan } = require('../../services/memoryHealthCheck');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => {
    jest.clearAllMocks();
    pinecone.isReady.mockReturnValue(true);
    pinecone.searchMemoriesDetailed.mockResolvedValue([]);
    pinecone.listAll.mockResolvedValue([]);
    classifyCategory.mockResolvedValue('כללי');
});

const longTermMem = (id, content, extra = {}) => ({
    id, content, scope: 'long_term', status: 'approved', created_at: new Date().toISOString(), ...extra,
});

describe('runHealthScan — duplicates', () => {
    test('creates a duplicate finding with a merge suggestion above 0.92', async () => {
        // Content is deliberately ≥5 words and category is pre-set to match the
        // mocked classifier — otherwise the thin_content or category_mismatch
        // detectors would also fire and break the exact-call-count assertion below.
        const memA = longTermMem(1, 'אני אוהב לשתות קפה שחור כל בוקר', { category: 'כללי' });
        const memB = longTermMem(2, 'אני שותה קפה שחור בכל בוקר בשבוע', { category: 'כללי' });
        const repos = makeRepos({ memories: [memA, memB] });
        pinecone.searchMemoriesDetailed.mockImplementation(async (query) => {
            if (query === memA.content) return [{ id: '1', content: memA.content, score: 1 }, { id: '2', content: memB.content, score: 0.95 }];
            return [{ id: '2', content: memB.content, score: 1 }, { id: '1', content: memA.content, score: 0.95 }];
        });
        callGemma4.mockResolvedValue('{"merged":"אוהב לשתות קפה שחור כל בוקר"}');

        const summary = await runHealthScan(repos);

        expect(repos.memoryHealth.insertFinding).toHaveBeenCalledTimes(1);
        const [row] = repos.memoryHealth.insertFinding.mock.calls[0];
        expect(row.type).toBe('duplicate');
        expect(row.suggested_action).toBe('merge');
        expect(row.suggested_payload.mergedContent).toBe('אוהב לשתות קפה שחור כל בוקר');
        expect(summary.created).toBe(1);
    });

    test('does not flag the memory against itself', async () => {
        const mem = longTermMem(1, 'תוכן ייחודי שלא דומה לשום זיכרון אחר בכלל', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });
        pinecone.searchMemoriesDetailed.mockResolvedValue([{ id: '1', content: mem.content, score: 1 }]);

        await runHealthScan(repos);

        expect(repos.memoryHealth.insertFinding).not.toHaveBeenCalled();
    });
});

describe('runHealthScan — conflicts', () => {
    test('creates a conflict finding in the 0.70-0.92 band with an archive suggestion', async () => {
        const memA = longTermMem(1, 'עובד בחברת נאווה כבר שלוש שנים', { category: 'כללי' });
        const memB = longTermMem(2, 'התחיל תפקיד חדש בחברת קוואנטום סופט', { category: 'כללי' });
        const repos = makeRepos({ memories: [memA, memB] });
        pinecone.searchMemoriesDetailed.mockImplementation(async (query) => {
            if (query === memA.content) return [{ id: '1', content: memA.content, score: 1 }, { id: '2', content: memB.content, score: 0.8 }];
            return [{ id: '2', content: memB.content, score: 1 }, { id: '1', content: memA.content, score: 0.8 }];
        });

        const summary = await runHealthScan(repos);

        expect(repos.memoryHealth.insertFinding).toHaveBeenCalledTimes(1);
        const [row] = repos.memoryHealth.insertFinding.mock.calls[0];
        expect(row.type).toBe('conflict');
        expect(row.suggested_action).toBe('archive');
        expect(callGemma4).not.toHaveBeenCalled(); // no merge synthesis for conflicts
        expect(summary.created).toBe(1);
    });
});

describe('runHealthScan — category', () => {
    test('backfills a null category directly without creating a finding', async () => {
        const mem = longTermMem(1, 'יש לו פגישה עם הרופא', { category: null });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('בריאות');

        const summary = await runHealthScan(repos);

        expect(repos.memories.updateById).toHaveBeenCalledWith(1, { category: 'בריאות' });
        expect(repos.memoryHealth.insertFinding).not.toHaveBeenCalledWith(
            expect.objectContaining({ type: 'category_mismatch' }));
        expect(summary.autoResolved).toBeGreaterThanOrEqual(1);
    });

    test('creates a category_mismatch finding when an already-categorized memory disagrees', async () => {
        const mem = longTermMem(1, 'קונה כרטיסים למשחק כדורגל', { category: 'משפחה' });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('תחביב');

        const summary = await runHealthScan(repos);

        const call = repos.memoryHealth.insertFinding.mock.calls.find(([r]) => r.type === 'category_mismatch');
        expect(call[0].suggested_action).toBe('move');
        expect(call[0].suggested_payload).toEqual({ category: 'תחביב' });
        expect(summary.created).toBeGreaterThanOrEqual(1);
    });

    test('does nothing when the classified category matches the stored one', async () => {
        const mem = longTermMem(1, 'תוכן כלשהו', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('כללי');

        await runHealthScan(repos);

        expect(repos.memories.updateById).not.toHaveBeenCalled();
        expect(repos.memoryHealth.insertFinding).not.toHaveBeenCalledWith(
            expect.objectContaining({ type: 'category_mismatch' }));
    });
});

describe('runHealthScan — stale and thin content', () => {
    test('flags content under 5 words as thin_content', async () => {
        const mem = longTermMem(1, 'אוהב פיצה', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });

        await runHealthScan(repos);

        const call = repos.memoryHealth.insertFinding.mock.calls.find(([r]) => r.type === 'thin_content');
        expect(call[0].suggested_action).toBe('delete');
    });

    test('flags a long_term memory older than 6 months as stale', async () => {
        const old = new Date(Date.now() - 200 * 24 * 60 * 60 * 1000).toISOString();
        const mem = longTermMem(1, 'מתכנן לנסוע לטיול בתאילנד בקיץ הקרוב', { category: 'כללי', created_at: old });
        const repos = makeRepos({ memories: [mem] });

        await runHealthScan(repos);

        const call = repos.memoryHealth.insertFinding.mock.calls.find(([r]) => r.type === 'stale');
        expect(call[0].suggested_action).toBe('archive');
    });
});

describe('runHealthScan — orphans (auto-resolved, no approval needed)', () => {
    test('re-upserts a Supabase row missing from Pinecone', async () => {
        const mem = longTermMem(1, 'זיכרון תקין', { category: 'כללי' });
        const repos = makeRepos({ memories: [mem] });
        pinecone.listAll.mockResolvedValue([]); // no vectors at all → row 1 is orphaned

        const summary = await runHealthScan(repos);

        expect(pinecone.upsertMemory).toHaveBeenCalledWith(1, 'זיכרון תקין');
        expect(summary.autoResolved).toBeGreaterThanOrEqual(1);
    });

    test('deletes a Pinecone vector missing from Supabase', async () => {
        const repos = makeRepos({ memories: [] });
        pinecone.listAll.mockResolvedValue([{ id: '99', content: 'orphaned vector' }]);

        await runHealthScan(repos);

        expect(pinecone.deleteMemory).toHaveBeenCalledWith('99');
    });

    test('skips pending-status rows — they are intentionally excluded from Pinecone', async () => {
        const pendingMem = { id: 5, content: 'ממתין לאישור', scope: 'session', status: 'pending', created_at: new Date().toISOString() };
        const repos = makeRepos({ memories: [pendingMem] });
        pinecone.listAll.mockResolvedValue([]);

        await runHealthScan(repos);

        expect(pinecone.upsertMemory).not.toHaveBeenCalledWith(5, expect.anything());
    });
});

describe('runHealthScan — skips detection when Pinecone is not ready', () => {
    test('skips duplicate/conflict scan but still runs category/stale/thin', async () => {
        pinecone.isReady.mockReturnValue(false);
        const mem = longTermMem(1, 'אוהב פיצה', { category: null });
        const repos = makeRepos({ memories: [mem] });
        classifyCategory.mockResolvedValue('כללי');

        await runHealthScan(repos);

        expect(pinecone.searchMemoriesDetailed).not.toHaveBeenCalled();
        expect(repos.memories.updateById).toHaveBeenCalledWith(1, { category: 'כללי' });
    });
});
