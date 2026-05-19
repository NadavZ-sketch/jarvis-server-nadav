'use strict';
jest.mock('../../services/pineconeMemory', () => ({ deleteMemory: jest.fn().mockResolvedValue() }));

const { cleanupExpiredMemories, SESSION_TTL_MS, RECENT_TTL_MS } = require('../../services/memoryCleanup');

function makeSupabaseMock(rowsByScope, deleteError = null) {
    const calls = [];
    const supabase = {
        from: jest.fn(() => {
            const chain = {
                _scope: null,
                _isDelete: false,
                select() { return chain; },
                eq(field, value) { if (field === 'scope') chain._scope = value; return chain; },
                lt() { return chain; },
                delete() { chain._isDelete = true; return chain; },
                in(_field, ids) {
                    calls.push({ scope: chain._scope, ids });
                    return Promise.resolve({ error: deleteError });
                },
                // The select() chain awaits on .limit(); return the row data here.
                limit() {
                    return Promise.resolve({ data: rowsByScope[chain._scope] || [], error: null });
                },
            };
            return chain;
        }),
    };
    supabase._calls = calls;
    return supabase;
}

describe('cleanupExpiredMemories', () => {
    test('returns 0 deleted when no supabase client', async () => {
        const res = await cleanupExpiredMemories(null);
        expect(res.deleted).toBe(0);
    });

    test('TTLs are 24h for session and 7d for recent', () => {
        expect(SESSION_TTL_MS).toBe(24 * 60 * 60 * 1000);
        expect(RECENT_TTL_MS).toBe(7 * 24 * 60 * 60 * 1000);
    });

    test('deletes expired session + recent rows and returns count', async () => {
        const supabase = makeSupabaseMock({
            session: [{ id: 1 }, { id: 2 }],
            recent:  [{ id: 3 }],
        });
        const res = await cleanupExpiredMemories(supabase);
        expect(res.deleted).toBe(3);
        // Two delete calls were issued (one per non-empty scope) with the right ids.
        const allDeletedIds = supabase._calls.flatMap(c => c.ids).sort();
        expect(allDeletedIds).toEqual([1, 2, 3]);
    });

    test('no rows → no delete attempted', async () => {
        const supabase = makeSupabaseMock({ session: [], recent: [] });
        const res = await cleanupExpiredMemories(supabase);
        expect(res.deleted).toBe(0);
        expect(supabase._calls.length).toBe(0);
    });

    test('delete error is captured in errors[] without throwing', async () => {
        const supabase = makeSupabaseMock(
            { session: [{ id: 9 }], recent: [] },
            { message: 'permission denied' },
        );
        const res = await cleanupExpiredMemories(supabase);
        expect(res.deleted).toBe(0);
        expect(res.errors.some(e => /permission denied/.test(e))).toBe(true);
    });
});
