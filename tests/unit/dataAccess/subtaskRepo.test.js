'use strict';

const { createSubtaskRepo } = require('../../../services/dataAccess/subtaskRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('subtaskRepo', () => {
    test('listForParent scopes to the parent, ordered; throws on error', async () => {
        const chain = makeChain([{ id: 1 }]);
        const repo = createSubtaskRepo({ from: () => chain });
        const rows = await repo.listForParent('p1');
        expect(chain.eq).toHaveBeenCalledWith('parent_task_id', 'p1');
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: true });
        expect(rows).toEqual([{ id: 1 }]);

        const bad = createSubtaskRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.listForParent('p1')).rejects.toEqual({ message: 'boom' });
    });

    test('add inserts under the parent', async () => {
        const chain = makeChain({ id: 50 });
        const repo = createSubtaskRepo({ from: () => chain });
        await repo.add('p1', 'תת-משימה');
        expect(chain.insert).toHaveBeenCalledWith([{ parent_task_id: 'p1', content: 'תת-משימה' }]);
    });

    test('updateScoped and removeScoped constrain by id + parent', async () => {
        const upd = makeChain({ id: 50 });
        await createSubtaskRepo({ from: () => upd }).updateScoped('50', 'p1', { done: true });
        expect(upd.eq).toHaveBeenCalledWith('id', '50');
        expect(upd.eq).toHaveBeenCalledWith('parent_task_id', 'p1');

        const del = makeChain([], null);
        await createSubtaskRepo({ from: () => del }).removeScoped('50', 'p1');
        expect(del.eq).toHaveBeenCalledWith('id', '50');
        expect(del.eq).toHaveBeenCalledWith('parent_task_id', 'p1');
    });
});
