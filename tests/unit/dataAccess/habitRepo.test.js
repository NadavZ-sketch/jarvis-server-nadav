'use strict';

const { createHabitRepo } = require('../../../services/dataAccess/habitRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('habitRepo', () => {
    test('findActiveByName filters active + sanitized name; empty hint short-circuits', async () => {
        const chain = makeChain([{ id: 'h1', name: 'ריצה' }]);
        const repo = createHabitRepo({ from: () => chain });
        const rows = await repo.findActiveByName('ריצה');
        expect(chain.eq).toHaveBeenCalledWith('active', true);
        expect(chain.ilike).toHaveBeenCalledWith('name', '%ריצה%');
        expect(rows).toEqual([{ id: 'h1', name: 'ריצה' }]);

        const fromSpy = jest.fn(() => makeChain([]));
        expect(await createHabitRepo({ from: fromSpy }).findActiveByName('')).toEqual([]);
        expect(fromSpy).not.toHaveBeenCalled();
    });

    test('logToday upserts with the habit_id,date conflict target', async () => {
        const chain = makeChain([], null);
        const repo = createHabitRepo({ from: () => chain });
        await repo.logToday('h1', '2026-06-13');
        expect(chain.upsert).toHaveBeenCalledWith(
            [{ habit_id: 'h1', date: '2026-06-13', done: true }],
            { onConflict: 'habit_id,date' }
        );
    });

    test('doneDates returns a flat array of date strings', async () => {
        const chain = makeChain([{ date: '2026-06-12' }, { date: '2026-06-13' }]);
        const repo = createHabitRepo({ from: () => chain });
        expect(await repo.doneDates('h1')).toEqual(['2026-06-12', '2026-06-13']);
    });

    test('deactivate flips active to false by id', async () => {
        const chain = makeChain([], null);
        const repo = createHabitRepo({ from: () => chain });
        await repo.deactivate('h1');
        expect(chain.update).toHaveBeenCalledWith({ active: false });
        expect(chain.eq).toHaveBeenCalledWith('id', 'h1');
    });
});
