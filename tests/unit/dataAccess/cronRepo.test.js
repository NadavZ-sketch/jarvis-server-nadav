'use strict';

const { createCronRepo } = require('../../../services/dataAccess/cronRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('cronRepo', () => {
    test('markOk upserts last_ok_at on the job_name conflict target', async () => {
        const chain = makeChain([], null);
        await createCronRepo({ from: () => chain }).markOk('morning_briefing');
        const [row, opts] = chain.upsert.mock.calls[0];
        expect(row.job_name).toBe('morning_briefing');
        expect(typeof row.last_ok_at).toBe('string');
        expect(opts).toEqual({ onConflict: 'job_name' });
    });

    test('markError truncates the message to 500 chars', async () => {
        const chain = makeChain([], null);
        await createCronRepo({ from: () => chain }).markError('job', 'x'.repeat(900));
        const [row] = chain.upsert.mock.calls[0];
        expect(row.last_error.length).toBe(500);
    });

    test('lastOkAt returns the timestamp or null', async () => {
        const ok = createCronRepo({ from: () => makeChain({ last_ok_at: '2026-06-14T07:00:00Z' }) });
        expect(await ok.lastOkAt('job')).toBe('2026-06-14T07:00:00Z');
        const none = createCronRepo({ from: () => makeChain(null) });
        expect(await none.lastOkAt('job')).toBeNull();
    });
});
