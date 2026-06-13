'use strict';

const { createMemoryRepo } = require('../../../services/dataAccess/memoryRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('memoryRepo', () => {
    test('findByContent sanitizes the ilike pattern', async () => {
        const chain = makeChain([{ id: 1 }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.findByContent('50% off', { columns: 'id', limit: 1 });
        expect(chain.ilike).toHaveBeenCalledWith('content', '%50\\% off%');
        expect(rows).toEqual([{ id: 1 }]);
    });

    test('allContents maps rows to content strings', async () => {
        const chain = makeChain([{ content: 'a' }, { content: 'b' }]);
        const repo = createMemoryRepo({ from: () => chain });
        expect(await repo.allContents()).toEqual(['a', 'b']);
    });

    test('deleteByContent returns deleted rows and throws on error', async () => {
        const ok = makeChain([{ id: 1, content: 'x' }]);
        const repo = createMemoryRepo({ from: () => ok });
        expect(await repo.deleteByContent('x')).toEqual([{ id: 1, content: 'x' }]);

        const bad = createMemoryRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.deleteByContent('x')).rejects.toEqual({ message: 'boom' });
    });

    test('insert returns the inserted id rows', async () => {
        const chain = makeChain([{ id: 99 }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.insert({ content: 'c', scope: 'long_term' });
        expect(chain.insert).toHaveBeenCalledWith([{ content: 'c', scope: 'long_term' }]);
        expect(rows).toEqual([{ id: 99 }]);
    });
});
