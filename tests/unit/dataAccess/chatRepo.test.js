'use strict';

const { createChatRepo } = require('../../../services/dataAccess/chatRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('chatRepo', () => {
    test('recentTail scopes to chat, newest-first, limited; throws on error', async () => {
        const chain = makeChain([{ role: 'user', text: 'hi' }]);
        const repo = createChatRepo({ from: () => chain });
        const rows = await repo.recentTail('s1', { limit: 30 });
        expect(chain.eq).toHaveBeenCalledWith('chat_id', 's1');
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
        expect(chain.limit).toHaveBeenCalledWith(30);
        expect(rows).toEqual([{ role: 'user', text: 'hi' }]);

        const bad = createChatRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.recentTail('s1')).rejects.toEqual({ message: 'boom' });
    });

    test('add inserts a row with chat_id', async () => {
        const chain = makeChain([], null);
        await createChatRepo({ from: () => chain }).add('user', 'hi', 's1');
        expect(chain.insert).toHaveBeenCalledWith([{ role: 'user', text: 'hi', chat_id: 's1' }]);
    });

    test('recentForSearch returns rows (swallows errors → [])', async () => {
        const chain = makeChain([{ role: 'user', text: 'a' }]);
        expect(await createChatRepo({ from: () => chain }).recentForSearch(200)).toEqual([{ role: 'user', text: 'a' }]);
        const bad = createChatRepo({ from: () => makeChain(null, { message: 'x' }) });
        expect(await bad.recentForSearch()).toEqual([]);
    });
});
