'use strict';

const { createNoteRepo } = require('../../../services/dataAccess/noteRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('noteRepo', () => {
    test('search builds a sanitized title/content or-filter', async () => {
        const chain = makeChain([{ id: 1, content: 'x' }]);
        const repo = createNoteRepo({ from: () => chain });
        const rows = await repo.search('50%');
        expect(chain.or).toHaveBeenCalledWith('title.ilike.%50\\%%,content.ilike.%50\\%%');
        expect(rows).toEqual([{ id: 1, content: 'x' }]);
    });

    test('listRecent orders by created_at desc with a limit', async () => {
        const chain = makeChain([{ id: 1 }]);
        const repo = createNoteRepo({ from: () => chain });
        await repo.listRecent(10);
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
        expect(chain.limit).toHaveBeenCalledWith(10);
    });

    test('add returns the inserted row', async () => {
        const chain = makeChain({ id: 'n1', content: 'hi' });
        const repo = createNoteRepo({ from: () => chain });
        expect(await repo.add({ title: '', content: 'hi' })).toEqual({ id: 'n1', content: 'hi' });
        expect(chain.insert).toHaveBeenCalledWith([{ title: '', content: 'hi' }]);
    });
});
