'use strict';

const { createProfileRepo } = require('../../../services/dataAccess/profileRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('profileRepo', () => {
    test('latest returns the newest row; throws on error', async () => {
        const chain = makeChain([{ id: 'p1' }]);
        const repo = createProfileRepo({ from: () => chain });
        expect(await repo.latest()).toEqual([{ id: 'p1' }]);
        expect(chain.order).toHaveBeenCalledWith('updated_at', { ascending: false });
        const bad = createProfileRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.latest()).rejects.toEqual({ message: 'boom' });
    });

    test('update / removeById target by id', async () => {
        const upd = makeChain({ id: 'p1' });
        await createProfileRepo({ from: () => upd }).update('p1', { name: 'x' });
        expect(upd.update).toHaveBeenCalledWith({ name: 'x' });
        expect(upd.eq).toHaveBeenCalledWith('id', 'p1');
        const del = makeChain([], null);
        await createProfileRepo({ from: () => del }).removeById('p1');
        expect(del.eq).toHaveBeenCalledWith('id', 'p1');
    });

    test('saveCalendarToken upserts on the default row', async () => {
        const chain = makeChain([], null);
        await createProfileRepo({ from: () => chain }).saveCalendarToken('{"t":1}');
        expect(chain.upsert).toHaveBeenCalledWith(
            [{ id: 'default', google_calendar_token: '{"t":1}' }],
            { onConflict: 'id' },
        );
    });
});
