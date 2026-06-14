'use strict';

const { createE2eRepo } = require('../../../services/dataAccess/e2eRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('e2eRepo', () => {
    test('byRun scopes to run_id ordered by severity; throws on error', async () => {
        const chain = makeChain([{ run_id: 'r1' }]);
        const repo = createE2eRepo({ from: () => chain });
        await repo.byRun('r1');
        expect(chain.eq).toHaveBeenCalledWith('run_id', 'r1');
        expect(chain.order).toHaveBeenCalledWith('severity', { ascending: true });
        const bad = createE2eRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.byRun('r1')).rejects.toEqual({ message: 'boom' });
    });

    test('markDone updates status by run + fingerprint set', async () => {
        const chain = makeChain([], null);
        await createE2eRepo({ from: () => chain }).markDone('r1', ['fp1', 'fp2']);
        expect(chain.update).toHaveBeenCalledWith({ status: 'done' });
        expect(chain.eq).toHaveBeenCalledWith('run_id', 'r1');
        expect(chain.in).toHaveBeenCalledWith('fingerprint', ['fp1', 'fp2']);
    });

    test('recentFailures filters status=fail and swallows errors', async () => {
        const chain = makeChain([{ summary: 's' }]);
        expect(await createE2eRepo({ from: () => chain }).recentFailures(3)).toEqual([{ summary: 's' }]);
        expect(chain.eq).toHaveBeenCalledWith('status', 'fail');
    });
});
