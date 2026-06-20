'use strict';
const { createTestCasesRepo } = require('../../services/dataAccess/testCasesRepo');

const SAMPLE = {
    id: 'tc1', name: 'תזכורת', source: 'recorded',
    turns: [{ input: 'תזכיר לי בשעה 8', expected_intent: 'reminder', expected_action_type: 'reminder_set', expected_contains: ['8:00'] }],
    last_status: 'pending', recorded_at: '2026-06-20T10:00:00Z',
};

function makeSb(rows = []) {
    const single = jest.fn().mockResolvedValue({ data: rows[0] || SAMPLE, error: null });
    const chain = {
        select: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        order:  jest.fn().mockResolvedValue({ data: rows, error: null }),
        single,
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('testCasesRepo', () => {
    test('listAll returns rows', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createTestCasesRepo(sb);
        expect(await repo.listAll()).toEqual([SAMPLE]);
    });

    test('create inserts and returns row', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createTestCasesRepo(sb);
        const result = await repo.create({ name: 'test', turns: SAMPLE.turns });
        expect(result).toEqual(SAMPLE);
        expect(sb._chain.insert).toHaveBeenCalled();
    });

    test('markResult updates last_status and last_run', async () => {
        // For markResult, update().eq() needs to resolve
        const chain = {
            select: jest.fn().mockReturnThis(),
            eq:     jest.fn().mockResolvedValue({ error: null }),
            update: jest.fn().mockReturnThis(),
            order:  jest.fn().mockResolvedValue({ data: [], error: null }),
            single: jest.fn().mockResolvedValue({ data: SAMPLE, error: null }),
        };
        const sb = { from: jest.fn(() => chain), _chain: chain };
        const repo = createTestCasesRepo(sb);
        await repo.markResult('tc1', 'pass', []);
        expect(sb._chain.update).toHaveBeenCalled();
    });

    test('byId returns single row', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createTestCasesRepo(sb);
        const result = await repo.byId('tc1');
        expect(result).toEqual(SAMPLE);
    });
});
