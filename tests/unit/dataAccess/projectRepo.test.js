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

    test('countsForProjects fetches task + milestone flags by id set', async () => {
        const tasksChain = makeChain([{ project_id: 'p1', done: true }]);
        const msChain = makeChain([{ project_id: 'p1', completed: false }]);
        const supabase = { from: jest.fn().mockReturnValueOnce(tasksChain).mockReturnValueOnce(msChain) };
        const { tasks, milestones } = await createProjectRepo(supabase).countsForProjects(['p1']);
        expect(tasksChain.in).toHaveBeenCalledWith('project_id', ['p1']);
        expect(tasks).toEqual([{ project_id: 'p1', done: true }]);
        expect(milestones).toEqual([{ project_id: 'p1', completed: false }]);
    });

    test('updateMilestoneScoped constrains by milestone id + project', async () => {
        const chain = makeChain({ id: 'm1' });
        await createProjectRepo({ from: () => chain }).updateMilestoneScoped('m1', 'p1', { completed: true });
        expect(chain.update).toHaveBeenCalledWith({ completed: true });
        expect(chain.eq).toHaveBeenCalledWith('id', 'm1');
        expect(chain.eq).toHaveBeenCalledWith('project_id', 'p1');
    });

    test('getById returns a single row or null', async () => {
        expect(await createProjectRepo({ from: () => makeChain({ id: 'p1' }) }).getById('p1')).toEqual({ id: 'p1' });
        expect(await createProjectRepo({ from: () => makeChain(null) }).getById('x')).toBeNull();
    });
});
