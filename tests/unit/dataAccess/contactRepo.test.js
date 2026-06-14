'use strict';

const { createContactRepo } = require('../../../services/dataAccess/contactRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('contactRepo', () => {
    test('listByName orders by name; throws on error', async () => {
        const chain = makeChain([{ id: 1, name: 'דנה' }]);
        expect(await createContactRepo({ from: () => chain }).listByName()).toEqual([{ id: 1, name: 'דנה' }]);
        expect(chain.order).toHaveBeenCalledWith('name', { ascending: true });
        const bad = createContactRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.listByName()).rejects.toEqual({ message: 'boom' });
    });

    test('create inserts the row', async () => {
        const chain = makeChain({ id: 7 });
        await createContactRepo({ from: () => chain }).create({ name: 'רון', phone: '050' });
        expect(chain.insert).toHaveBeenCalledWith([{ name: 'רון', phone: '050' }]);
    });

    test('updateById / removeById target by id', async () => {
        const upd = makeChain({ id: 7 });
        await createContactRepo({ from: () => upd }).updateById('7', { phone: '052' });
        expect(upd.update).toHaveBeenCalledWith({ phone: '052' });
        expect(upd.eq).toHaveBeenCalledWith('id', '7');
        const del = makeChain([], null);
        await createContactRepo({ from: () => del }).removeById('7');
        expect(del.eq).toHaveBeenCalledWith('id', '7');
    });
});
