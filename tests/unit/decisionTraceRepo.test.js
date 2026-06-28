'use strict';
const { createDecisionTraceRepo } = require('../../services/dataAccess/decisionTraceRepo');

function makeSupabase({ rows = [], insertError = null } = {}) {
    const insertMock = insertError
        ? jest.fn().mockRejectedValue(insertError)
        : jest.fn().mockResolvedValue({ error: null });
    const chain = {
        select: jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        limit:  jest.fn().mockResolvedValue({ data: rows, error: null }),
        insert: insertMock,
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('decisionTraceRepo', () => {
    test('recent returns up to N rows ordered by created_at desc', async () => {
        const rows = [{ id: '1', chat_id: 'c1', input: 'hi', intent: 'chat', candidates: '[]', ambiguous: false, route_mode: 'fast', agent: 'chat', model: 'groq', duration_ms: 100 }];
        const sb = makeSupabase({ rows });
        const repo = createDecisionTraceRepo(sb);
        const result = await repo.recent(10);
        expect(result).toEqual(rows);
        expect(sb._chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
        expect(sb._chain.limit).toHaveBeenCalledWith(10);
    });

    test('insert writes a row and does not throw on success', async () => {
        const sb = makeSupabase();
        const repo = createDecisionTraceRepo(sb);
        await expect(repo.insert({
            chatId: 'c1', input: 'שלום', intent: 'chat', candidates: ['chat'],
            ambiguous: false, route_mode: 'fast', agent: 'chat', model: 'groq', duration_ms: 42,
        })).resolves.toBeUndefined();
    });

    test('insert swallows errors (degradation)', async () => {
        const sb = makeSupabase({ insertError: new Error('db down') });
        const repo = createDecisionTraceRepo(sb);
        await expect(repo.insert({
            chatId: 'c1', input: 'שלום', intent: 'chat', candidates: [],
            ambiguous: false, route_mode: 'fast', agent: 'chat', model: 'groq', duration_ms: 42,
        })).resolves.toBeUndefined();
    });
});
