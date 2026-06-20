'use strict';
const { createPromptLibraryRepo } = require('../../services/dataAccess/promptLibraryRepo');

const SAMPLE = { id: 'p1', name: 'System Prompt', content: 'You are Jarvis.', version: 1, is_active: true };

// Minimal Supabase chain mock
function makeSb(rows = []) {
    const single = jest.fn().mockResolvedValue({ data: rows[0] || SAMPLE, error: null });
    const chain = {
        select: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        order:  jest.fn().mockResolvedValue({ data: rows, error: null }),
        single,
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('promptLibraryRepo', () => {
    test('listAll returns rows ordered by created_at desc', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createPromptLibraryRepo(sb);
        const result = await repo.listAll();
        expect(result).toEqual([SAMPLE]);
        expect(sb._chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
    });

    test('create inserts and returns the new row', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createPromptLibraryRepo(sb);
        const result = await repo.create({ name: 'Test', content: 'Hello' });
        expect(result).toEqual(SAMPLE);
        expect(sb._chain.insert).toHaveBeenCalled();
    });

    test('update increments version when content changes', async () => {
        // Mock that tracks call order: first single() returns version, second returns full SAMPLE
        let singleCallCount = 0;
        const chain = {
            select: jest.fn().mockReturnThis(),
            eq: jest.fn().mockReturnThis(),
            single: jest.fn().mockImplementation(() => {
                singleCallCount++;
                if (singleCallCount === 1) {
                    // First call: fetching current version
                    return Promise.resolve({ data: { version: 1 }, error: null });
                } else {
                    // Second call: after update, return full SAMPLE
                    return Promise.resolve({ data: SAMPLE, error: null });
                }
            }),
            update: jest.fn().mockReturnThis(),
        };

        const sb = { from: jest.fn(() => chain) };
        const repo = createPromptLibraryRepo(sb);
        const result = await repo.update('p1', { content: 'New content' });
        expect(result).toEqual(SAMPLE);
        expect(chain.update).toHaveBeenCalled();
    });

    test('update can change name and is_active without incrementing version', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createPromptLibraryRepo(sb);
        const result = await repo.update('p1', { name: 'Updated' });
        expect(result).toEqual(SAMPLE);
        expect(sb._chain.update).toHaveBeenCalled();
    });

    test('remove calls delete with correct id', async () => {
        const sb = makeSb();
        // delete chain needs to resolve
        sb._chain.delete = jest.fn().mockReturnThis();
        sb._chain.eq = jest.fn().mockResolvedValue({ error: null });
        const repo = createPromptLibraryRepo(sb);
        await repo.remove('p1');
        expect(sb._chain.delete).toHaveBeenCalled();
    });

    test('update throws if no fields provided', async () => {
        const sb = makeSb([SAMPLE]);
        const repo = createPromptLibraryRepo(sb);
        await expect(repo.update('p1', {})).rejects.toThrow('nothing to update');
    });
});
