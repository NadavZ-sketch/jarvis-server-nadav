'use strict';
const { createExecutionLogRepo } = require('../../services/dataAccess/executionLogRepo');

function makeSupabase({ rows = [], insertError = null } = {}) {
    const chain = {
        select: jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        limit:  jest.fn().mockResolvedValue({ data: rows, error: null }),
        insert: jest.fn().mockResolvedValue({ error: insertError }),
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('executionLogRepo', () => {
    test('recent returns up to N rows ordered by created_at desc', async () => {
        const rows = [{ id: '1', cmd: 'test', agent: 'chat', model: 'groq', duration_ms: 120, status: 'ok' }];
        const sb = makeSupabase({ rows });
        const repo = createExecutionLogRepo(sb);
        const result = await repo.recent(10);
        expect(result).toEqual(rows);
        expect(sb._chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
        expect(sb._chain.limit).toHaveBeenCalledWith(10);
    });

    test('insert writes a row and does not throw on success', async () => {
        const sb = makeSupabase();
        const repo = createExecutionLogRepo(sb);
        await expect(repo.insert({ cmd: 'hi', agent: 'chat', model: 'groq', duration_ms: 50, status: 'ok' }))
            .resolves.toBeUndefined();
    });

    test('insert swallows errors (degradation)', async () => {
        const sb = makeSupabase({ insertError: new Error('db down') });
        const repo = createExecutionLogRepo(sb);
        await expect(repo.insert({ cmd: 'hi', agent: 'chat', model: 'groq', duration_ms: 50, status: 'ok' }))
            .resolves.toBeUndefined();
    });
});
