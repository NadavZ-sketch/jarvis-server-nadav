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

describe('memoryRepo.findByScope', () => {
    test('returns rows matching scope', async () => {
        const chain = makeChain([{ id: 1, content: '[fact] test', scope: 'archive' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.findByScope('archive');
        expect(chain.eq).toHaveBeenCalledWith('scope', 'archive');
        expect(rows).toHaveLength(1);
        expect(rows[0].content).toBe('[fact] test');
    });

    test('returns empty array when no rows match', async () => {
        const chain = makeChain([]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.findByScope('archive');
        expect(rows).toEqual([]);
    });
});

describe('memoryRepo.listByStatus', () => {
    test('filters memories by status', async () => {
        const rows = [{ id: 1, content: 'test', scope: 'session', status: 'pending' }];
        const chain = makeChain(rows);
        const repo = createMemoryRepo({ from: () => chain });
        const result = await repo.listByStatus('pending', 50);
        expect(chain.eq).toHaveBeenCalledWith('status', 'pending');
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
        expect(chain.limit).toHaveBeenCalledWith(50);
        expect(result).toEqual(rows);
    });

    test('returns [] on error (defensive — column may not exist)', async () => {
        const chain = makeChain(null, { message: 'column "status" does not exist', code: '42703' });
        const repo = createMemoryRepo({ from: () => chain });
        const result = await repo.listByStatus('pending');
        expect(result).toEqual([]);
    });
});

describe('memoryRepo.setStatus', () => {
    test('updates status and returns the row including content', async () => {
        const updated = [{ id: 5, content: 'hello', scope: 'session', status: 'approved' }];
        const chain = makeChain(updated);
        const repo = createMemoryRepo({ from: () => chain });
        const row = await repo.setStatus(5, 'approved');
        expect(chain.update).toHaveBeenCalledWith({ status: 'approved' });
        expect(chain.eq).toHaveBeenCalledWith('id', 5);
        expect(row).toEqual(updated[0]);
    });

    test('returns null when no row is found', async () => {
        const chain = makeChain([]);
        const repo = createMemoryRepo({ from: () => chain });
        const row = await repo.setStatus(999, 'approved');
        expect(row).toBeNull();
    });

    test('returns null on error (defensive — column may not exist)', async () => {
        const chain = makeChain(null, { message: 'column "status" does not exist', code: '42703' });
        const repo = createMemoryRepo({ from: () => chain });
        const row = await repo.setStatus(1, 'approved');
        expect(row).toBeNull();
    });
});

describe('memoryRepo.allContents — excludes pending', () => {
    test('filters out pending memories via .neq', async () => {
        const rows = [{ content: 'approved fact' }];
        const chain = makeChain(rows);
        const repo = createMemoryRepo({ from: () => chain });
        const contents = await repo.allContents();
        expect(chain.neq).toHaveBeenCalledWith('status', 'pending');
        expect(contents).toEqual(['approved fact']);
    });

    test('falls back to plain select when status column is missing', async () => {
        // First call fails with column-missing error; second succeeds
        const failChain = makeChain(null, { message: 'column "status" does not exist', code: '42703' });
        const successChain = makeChain([{ content: 'fallback' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? failChain : successChain) });
        const contents = await repo.allContents();
        expect(contents).toEqual(['fallback']);
    });
});

describe('memoryRepo.insert — status column fallback', () => {
    test('inserts with status when column exists', async () => {
        const chain = makeChain([{ id: 10 }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.insert({ content: 'c', scope: 'session', status: 'pending' });
        expect(chain.insert).toHaveBeenCalledWith([{ content: 'c', scope: 'session', status: 'pending' }]);
        expect(rows).toEqual([{ id: 10 }]);
    });

    test('retries without status when status column is missing', async () => {
        // First call fails with scope error; second call fails with status error;
        // third call (without both) succeeds.
        const scopeErrChain  = makeChain(null, { message: 'scope column missing', code: '42703' });
        const statusErrChain = makeChain(null, { message: 'status column missing', code: '42703' });
        const okChain        = makeChain([{ id: 20 }]);
        let call = 0;
        const chains = [scopeErrChain, statusErrChain, okChain];
        const repo = createMemoryRepo({ from: () => chains[call++] });
        const rows = await repo.insert({ content: 'c', scope: 'session', status: 'pending' });
        expect(rows).toEqual([{ id: 20 }]);
    });
});

describe('memoryRepo.category', () => {
    test('listAll includes category in the row when present', async () => {
        const chain = makeChain([{ id: 1, content: 'a', scope: 'long_term', category: 'עבודה', created_at: '2026-01-01' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.listAll();
        expect(rows[0].category).toBe('עבודה');
    });

    test('listAll falls back to the pre-category column set when category is missing', async () => {
        const noCatChain = makeChain(null, { message: 'column "category" does not exist', code: '42703' });
        const okChain = makeChain([{ id: 1, content: 'a', scope: 'long_term', created_at: '2026-01-01' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? noCatChain : okChain) });
        const rows = await repo.listAll();
        expect(rows).toEqual([{ id: 1, content: 'a', scope: 'long_term', created_at: '2026-01-01' }]);
    });

    test('create includes category in the insert payload and echoes it back', async () => {
        const chain = makeChain([{ id: 9, content: 'x', scope: 'long_term', category: 'תחביב', created_at: '2026-01-01' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.create({ content: 'x', scope: 'long_term', category: 'תחביב' });
        expect(chain.insert).toHaveBeenCalledWith([{ content: 'x', scope: 'long_term', category: 'תחביב' }]);
        expect(rows[0].category).toBe('תחביב');
    });

    test('create retries without category when the column is missing', async () => {
        const catErrChain = makeChain(null, { message: 'column "category" does not exist', code: '42703' });
        const okChain = makeChain([{ id: 9, content: 'x', scope: 'long_term', created_at: '2026-01-01' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? catErrChain : okChain) });
        const rows = await repo.create({ content: 'x', scope: 'long_term', category: 'תחביב' });
        expect(rows[0].id).toBe(9);
    });

    test('insert retries without category when missing, then still applies the scope/status fallback chain', async () => {
        const catErrChain    = makeChain(null, { message: 'column "category" does not exist' });
        const scopeErrChain  = makeChain(null, { message: 'scope column missing', code: '42703' });
        const statusErrChain = makeChain(null, { message: 'status column missing', code: '42703' });
        const okChain        = makeChain([{ id: 20 }]);
        const chains = [catErrChain, scopeErrChain, statusErrChain, okChain];
        let call = 0;
        const repo = createMemoryRepo({ from: () => chains[call++] });
        const rows = await repo.insert({ content: 'c', scope: 'session', status: 'pending', category: 'כללי' });
        expect(rows).toEqual([{ id: 20 }]);
    });

    test('updateById includes category in the select and patch', async () => {
        const chain = makeChain([{ id: 7, content: 'new', scope: 'long_term', category: 'בריאות' }]);
        const repo = createMemoryRepo({ from: () => chain });
        const rows = await repo.updateById('7', { category: 'בריאות' });
        expect(chain.update).toHaveBeenCalledWith({ category: 'בריאות' });
        expect(rows[0].category).toBe('בריאות');
    });

    test('updateById falls back without category when the column is missing', async () => {
        const catErrChain = makeChain(null, { message: 'column "category" does not exist' });
        const okChain = makeChain([{ id: 7, content: 'new', scope: 'long_term' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? catErrChain : okChain) });
        const rows = await repo.updateById('7', { content: 'new' });
        expect(rows[0].id).toBe(7);
    });

    test('updateById strips category from the retried write payload, not just the select', async () => {
        const catErrChain = makeChain(null, { message: 'column "category" does not exist' });
        const okChain = makeChain([{ id: 7, content: 'new', scope: 'long_term' }]);
        let call = 0;
        const repo = createMemoryRepo({ from: () => (call++ === 0 ? catErrChain : okChain) });
        await repo.updateById('7', { content: 'new', category: 'עבודה' });
        expect(okChain.update).toHaveBeenCalledWith({ content: 'new' });
    });
});
