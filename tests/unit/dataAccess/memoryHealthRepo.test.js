'use strict';

const { createMemoryHealthRepo } = require('../../../services/dataAccess/memoryHealthRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('memoryHealthRepo', () => {
    test('listFindings defaults to status=pending', async () => {
        const chain = makeChain([{ id: 'f1', type: 'duplicate', status: 'pending' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const rows = await repo.listFindings();
        expect(chain.eq).toHaveBeenCalledWith('status', 'pending');
        expect(rows).toEqual([{ id: 'f1', type: 'duplicate', status: 'pending' }]);
    });

    test('listFindings filters by type when provided', async () => {
        const chain = makeChain([]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        await repo.listFindings({ status: 'pending', type: 'conflict' });
        expect(chain.eq).toHaveBeenCalledWith('type', 'conflict');
    });

    test('findExisting looks up by type + memory_id + related_memory_id', async () => {
        const chain = makeChain([{ id: 'f1' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const row = await repo.findExisting('duplicate', '1', '2');
        expect(chain.eq).toHaveBeenCalledWith('type', 'duplicate');
        expect(chain.eq).toHaveBeenCalledWith('memory_id', '1');
        expect(chain.eq).toHaveBeenCalledWith('related_memory_id', '2');
        expect(row).toEqual({ id: 'f1' });
    });

    test('findExisting uses .is for a null related_memory_id', async () => {
        const chain = makeChain([]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        await repo.findExisting('stale', '1', null);
        expect(chain.is).toHaveBeenCalledWith('related_memory_id', null);
    });

    test('insertFinding returns the inserted row', async () => {
        const chain = makeChain([{ id: 'f2', type: 'stale' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const row = await repo.insertFinding({ type: 'stale', memory_id: '3' });
        expect(chain.insert).toHaveBeenCalledWith([{ type: 'stale', memory_id: '3' }]);
        expect(row).toEqual({ id: 'f2', type: 'stale' });
    });

    test('setStatus sets resolved_at for a non-pending status', async () => {
        const chain = makeChain([{ id: 'f3', status: 'approved' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        await repo.setStatus('f3', 'approved');
        const [patch] = chain.update.mock.calls[0];
        expect(patch.status).toBe('approved');
        expect(typeof patch.resolved_at).toBe('string');
    });

    test('getById returns null when no row matches', async () => {
        const chain = makeChain([]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        expect(await repo.getById('missing')).toBeNull();
    });

    test('updateFinding patches by id and returns the updated row', async () => {
        const chain = makeChain([{ id: 'f4', suggested_action: 'archive' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const row = await repo.updateFinding('f4', { suggested_action: 'archive' });
        expect(chain.update).toHaveBeenCalledWith({ suggested_action: 'archive' });
        expect(chain.eq).toHaveBeenCalledWith('id', 'f4');
        expect(row).toEqual({ id: 'f4', suggested_action: 'archive' });
    });

    test('setStatus does not set resolved_at when the status is pending', async () => {
        const chain = makeChain([{ id: 'f5', status: 'pending' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        await repo.setStatus('f5', 'pending');
        const [patch] = chain.update.mock.calls[0];
        expect(patch).toEqual({ status: 'pending' });
        expect(patch.resolved_at).toBeUndefined();
    });

    test('getById returns the row when one matches', async () => {
        const chain = makeChain([{ id: 'f6', type: 'stale' }]);
        const repo = createMemoryHealthRepo({ from: () => chain });
        const row = await repo.getById('f6');
        expect(row).toEqual({ id: 'f6', type: 'stale' });
    });
});
