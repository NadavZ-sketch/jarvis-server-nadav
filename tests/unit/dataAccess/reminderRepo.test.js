'use strict';

const { createReminderRepo } = require('../../../services/dataAccess/reminderRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('reminderRepo', () => {
    test('listUpcoming filters unfired, ordered, and throws on error', async () => {
        const ok = makeChain([{ id: 1, text: 'a' }]);
        const repo = createReminderRepo({ from: () => ok });
        const rows = await repo.listUpcoming();
        expect(ok.eq).toHaveBeenCalledWith('fired', false);
        expect(ok.order).toHaveBeenCalledWith('scheduled_time', { ascending: true });
        expect(rows).toEqual([{ id: 1, text: 'a' }]);

        const bad = createReminderRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.listUpcoming()).rejects.toEqual({ message: 'boom' });
    });

    test('deleteByText sanitizes the pattern and scopes to unfired', async () => {
        const chain = makeChain([{ id: 1, text: '50% off' }]);
        const repo = createReminderRepo({ from: () => chain });
        const rows = await repo.deleteByText('50% off');
        expect(chain.delete).toHaveBeenCalled();
        expect(chain.eq).toHaveBeenCalledWith('fired', false);
        expect(chain.ilike).toHaveBeenCalledWith('text', '%50\\% off%');
        expect(rows).toEqual([{ id: 1, text: '50% off' }]);
    });

    test('deleteMany removes by id set', async () => {
        const chain = makeChain([], null);
        const repo = createReminderRepo({ from: () => chain });
        await repo.deleteMany([1, 2, 3]);
        expect(chain.delete).toHaveBeenCalled();
        expect(chain.in).toHaveBeenCalledWith('id', [1, 2, 3]);
    });
});
