'use strict';

const { createTaskRepo } = require('../../../services/dataAccess/taskRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('taskRepo', () => {
    test('findByContent sanitizes the ilike pattern and gates open-only', async () => {
        const chain = makeChain([{ id: 1, content: 'a' }]);
        const repo = createTaskRepo({ from: () => chain });
        const rows = await repo.findByContent('50% off', { openOnly: true });
        expect(chain.ilike).toHaveBeenCalledWith('content', '%50\\% off%');
        expect(chain.eq).toHaveBeenCalledWith('done', false);
        expect(rows).toEqual([{ id: 1, content: 'a' }]);
    });

    test('addGraceful retries without optional columns on a column error', async () => {
        const errChain = makeChain(null, { message: 'column "category" does not exist' });
        const okChain  = makeChain([], null);
        const supabase = { from: jest.fn().mockReturnValueOnce(errChain).mockReturnValueOnce(okChain) };
        const repo = createTaskRepo(supabase);
        await repo.addGraceful({ content: 'x', category: 'work', recurrence: 'daily' });
        expect(okChain.insert).toHaveBeenCalledWith([{ content: 'x' }]);
    });

    test('listWithSubtasks falls back to a plain select when the relation is missing', async () => {
        const supabase = {
            from: jest.fn()
                .mockReturnValueOnce(makeChain(null, { message: 'relation "subtasks" does not exist' }))
                .mockReturnValueOnce(makeChain([{ id: 1 }])),
        };
        const repo = createTaskRepo(supabase);
        const rows = await repo.listWithSubtasks();
        expect(supabase.from).toHaveBeenCalledTimes(2);
        expect(rows).toEqual([{ id: 1 }]);
    });

    test('deleteById removes by id', async () => {
        const chain = makeChain([], null);
        const repo = createTaskRepo({ from: () => chain });
        await repo.deleteById(5);
        expect(chain.delete).toHaveBeenCalled();
        expect(chain.eq).toHaveBeenCalledWith('id', 5);
    });
});
