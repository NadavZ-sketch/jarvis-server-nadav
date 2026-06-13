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
});
