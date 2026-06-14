'use strict';

const { createShoppingRepo } = require('../../../services/dataAccess/shoppingRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('shoppingRepo', () => {
    test('listOpen filters unfinished items, ordered by created_at', async () => {
        const chain = makeChain([{ item: 'חלב' }]);
        const repo = createShoppingRepo({ from: () => chain });
        const rows = await repo.listOpen();
        expect(chain.eq).toHaveBeenCalledWith('done', false);
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: true });
        expect(rows).toEqual([{ item: 'חלב' }]);
    });

    test('deleteMatching escapes LIKE wildcards', async () => {
        const chain = makeChain([{ item: '100%_מיץ' }]);
        const repo = createShoppingRepo({ from: () => chain });
        const rows = await repo.deleteMatching('100%_מיץ');
        expect(chain.ilike).toHaveBeenCalledWith('item', '%100\\%\\_מיץ%');
        expect(rows).toEqual([{ item: '100%_מיץ' }]);
    });

    test('add inserts the item', async () => {
        const chain = makeChain([], null);
        const repo = createShoppingRepo({ from: () => chain });
        await repo.add('לחם');
        expect(chain.insert).toHaveBeenCalledWith([{ item: 'לחם' }]);
    });

    test('listAll returns every item ordered; throws on error', async () => {
        const chain = makeChain([{ id: 1, item: 'חלב' }]);
        expect(await createShoppingRepo({ from: () => chain }).listAll()).toEqual([{ id: 1, item: 'חלב' }]);
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: true });
        const bad = createShoppingRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.listAll()).rejects.toEqual({ message: 'boom' });
    });

    test('create inserts and returns the row; updateById / removeById target by id', async () => {
        const cr = makeChain({ id: 9, item: 'לחם' });
        await createShoppingRepo({ from: () => cr }).create('לחם');
        expect(cr.insert).toHaveBeenCalledWith([{ item: 'לחם' }]);
        const upd = makeChain({ id: 9 });
        await createShoppingRepo({ from: () => upd }).updateById('9', { done: true });
        expect(upd.update).toHaveBeenCalledWith({ done: true });
        expect(upd.eq).toHaveBeenCalledWith('id', '9');
        const del = makeChain([], null);
        await createShoppingRepo({ from: () => del }).removeById('9');
        expect(del.eq).toHaveBeenCalledWith('id', '9');
    });
});
