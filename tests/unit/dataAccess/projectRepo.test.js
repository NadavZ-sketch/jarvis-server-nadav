'use strict';

const { createProjectRepo } = require('../../../services/dataAccess/projectRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('projectRepo', () => {
    test('searchByName trims + ilikes; empty hint short-circuits without a query', async () => {
        const chain = makeChain([{ id: 'p1' }]);
        const repo = createProjectRepo({ from: () => chain });
        const rows = await repo.searchByName('  אפליקציה  ');
        expect(chain.ilike).toHaveBeenCalledWith('name', '%אפליקציה%');
        expect(rows).toEqual([{ id: 'p1' }]);

        const fromSpy = jest.fn(() => makeChain([]));
        expect(await createProjectRepo({ from: fromSpy }).searchByName('')).toEqual([]);
        expect(fromSpy).not.toHaveBeenCalled();
    });

    test('listNonArchived excludes archived, newest first', async () => {
        const chain = makeChain([{ id: 'p1' }]);
        const repo = createProjectRepo({ from: () => chain });
        await repo.listNonArchived();
        expect(chain.not).toHaveBeenCalledWith('status', 'eq', 'archived');
        expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: false });
    });

    test('completeMilestone sets completed + completed_at by id', async () => {
        const chain = makeChain([], null);
        const repo = createProjectRepo({ from: () => chain });
        await repo.completeMilestone('m1');
        const arg = chain.update.mock.calls[0][0];
        expect(arg.completed).toBe(true);
        expect(typeof arg.completed_at).toBe('string');
        expect(chain.eq).toHaveBeenCalledWith('id', 'm1');
    });

    test('sprintBacklog filters open, sprint-less tasks for the project', async () => {
        const chain = makeChain([{ id: 't1' }]);
        const repo = createProjectRepo({ from: () => chain });
        await repo.sprintBacklog('p1');
        expect(chain.eq).toHaveBeenCalledWith('project_id', 'p1');
        expect(chain.is).toHaveBeenCalledWith('sprint_id', null);
        expect(chain.eq).toHaveBeenCalledWith('done', false);
    });
});
