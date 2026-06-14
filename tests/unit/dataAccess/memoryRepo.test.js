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

    test('listAll returns full rows newest-first; throws on error', async () => {
        const chain = makeChain([{ id: 1, content: 'a', scope: 'long_term' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.listAll();
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
        expect(rows).toEqual([{ id: 1, content: 'a', scope: 'long_term' }]);

        const bad = createMemoryRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.listAll()).rejects.toEqual({ message: 'boom' });
    });

    test('create echoes the inserted row', async () => {
        const chain = makeChain([{ id: 5, content: 'x', scope: 'session' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.create({ content: 'x', scope: 'session' });
        expect(chain.insert).toHaveBeenCalledWith([{ content: 'x', scope: 'session' }]);
        expect(rows[0].id).toBe(5);
    });

    test('updateById patches by id; removeById deletes by id', async () => {
        const upd = makeChain([{ id: 7, content: 'new' }]);
        await createMemoryRepo({ from: () => upd }).updateById('7', { content: 'new' });
        expect(upd.update).toHaveBeenCalledWith({ content: 'new' });
        expect(upd.eq).toHaveBeenCalledWith('id', '7');

        const del = makeChain([{ id: 7, content: 'new' }]);
        const rows = await createMemoryRepo({ from: () => del }).removeById('7');
        expect(del.delete).toHaveBeenCalled();
        expect(del.eq).toHaveBeenCalledWith('id', '7');
        expect(rows).toEqual([{ id: 7, content: 'new' }]);
    });
});
