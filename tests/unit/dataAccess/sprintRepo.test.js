'use strict';

const { createSprintRepo } = require('../../../services/dataAccess/sprintRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('sprintRepo', () => {
    test('listForProject scopes + orders; throws on error', async () => {
        const chain = makeChain([{ id: 'sp1' }]);
        const repo = createSprintRepo({ from: () => chain });
        await repo.listForProject('p1');
        expect(chain.eq).toHaveBeenCalledWith('project_id', 'p1');
        expect(chain.order).toHaveBeenCalledWith('start_date', { ascending: false });
        const bad = createSprintRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.listForProject('p1')).rejects.toEqual({ message: 'boom' });
    });

    test('updateScoped constrains by id + project', async () => {
        const chain = makeChain({ id: 'sp1' });
        await createSprintRepo({ from: () => chain }).updateScoped('sp1', 'p1', { status: 'active' });
        expect(chain.update).toHaveBeenCalledWith({ status: 'active' });
        expect(chain.eq).toHaveBeenCalledWith('id', 'sp1');
        expect(chain.eq).toHaveBeenCalledWith('project_id', 'p1');
    });

    test('activeOthers excludes the given sprint', async () => {
        const chain = makeChain([]);
        await createSprintRepo({ from: () => chain }).activeOthers('p1', 'sp1');
        expect(chain.eq).toHaveBeenCalledWith('status', 'active');
        expect(chain.neq).toHaveBeenCalledWith('id', 'sp1');
    });

    test('releaseTasks detaches open tasks from the sprint', async () => {
        const chain = makeChain([], null);
        await createSprintRepo({ from: () => chain }).releaseTasks('sp1');
        expect(chain.update).toHaveBeenCalledWith({ sprint_id: null });
        expect(chain.eq).toHaveBeenCalledWith('sprint_id', 'sp1');
        expect(chain.eq).toHaveBeenCalledWith('done', false);
    });
});
