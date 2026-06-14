'use strict';
jest.mock('../../services/pineconeMemory', () => ({ deleteMemory: jest.fn().mockResolvedValue() }));

const { cleanupExpiredMemories, SESSION_TTL_MS, RECENT_TTL_MS } = require('../../services/memoryCleanup');

// repos whose memories.expiredByScope yields per-scope rows and deleteMany
// captures the deleted id sets.
function makeReposMock(rowsByScope, deleteError = null) {
    const calls = [];
    const repos = {
        memories: {
            expiredByScope: jest.fn(async (scope) => rowsByScope[scope] || []),
            deleteMany: jest.fn(async (ids) => { calls.push({ ids }); return { error: deleteError }; }),
        },
    };
    repos._calls = calls;
    return repos;
}

describe('cleanupExpiredMemories', () => {
    test('returns 0 deleted when no repos', async () => {
        const res = await cleanupExpiredMemories(null);
        expect(res.deleted).toBe(0);
    });

    test('TTLs are 24h for session and 7d for recent', () => {
        expect(SESSION_TTL_MS).toBe(24 * 60 * 60 * 1000);
        expect(RECENT_TTL_MS).toBe(7 * 24 * 60 * 60 * 1000);
    });

    test('deletes expired session + recent rows and returns count', async () => {
        const repos = makeReposMock({
            session: [{ id: 1 }, { id: 2 }],
            recent:  [{ id: 3 }],
        });
        const res = await cleanupExpiredMemories(repos);
        expect(res.deleted).toBe(3);
        const allDeletedIds = repos._calls.flatMap(c => c.ids).sort();
        expect(allDeletedIds).toEqual([1, 2, 3]);
    });

    test('no rows → no delete attempted', async () => {
        const repos = makeReposMock({ session: [], recent: [] });
        const res = await cleanupExpiredMemories(repos);
        expect(res.deleted).toBe(0);
        expect(repos._calls.length).toBe(0);
    });

    test('delete error is captured in errors[] without throwing', async () => {
        const repos = makeReposMock({ session: [{ id: 9 }], recent: [] }, { message: 'permission denied' });
        const res = await cleanupExpiredMemories(repos);
        expect(res.deleted).toBe(0);
        expect(res.errors.some(e => /permission denied/.test(e))).toBe(true);
    });
});
