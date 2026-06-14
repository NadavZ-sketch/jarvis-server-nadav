'use strict';

const { createMetricsRepo } = require('../../../services/dataAccess/metricsRepo');
const { createDeviceRepo } = require('../../../services/dataAccess/deviceRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('metricsRepo', () => {
    test('insertBatch inserts the rows as given', async () => {
        const chain = makeChain([], null);
        await createMetricsRepo({ from: () => chain }).insertBatch([{ agent: 'a', ms: 1 }]);
        expect(chain.insert).toHaveBeenCalledWith([{ agent: 'a', ms: 1 }]);
    });

    test('recentSince filters by window, ordered + limited; throws on error', async () => {
        const chain = makeChain([{ agent: 'a' }]);
        const repo = createMetricsRepo({ from: () => chain });
        const rows = await repo.recentSince('2026-06-01', 5000);
        expect(chain.gte).toHaveBeenCalledWith('created_at', '2026-06-01');
        expect(chain.limit).toHaveBeenCalledWith(5000);
        expect(rows).toEqual([{ agent: 'a' }]);
        const bad = createMetricsRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.recentSince('2026-06-01', 10)).rejects.toEqual({ message: 'boom' });
    });
});

describe('deviceRepo', () => {
    test('upsertToken targets the token conflict key', async () => {
        const chain = makeChain([], null);
        await createDeviceRepo({ from: () => chain }).upsertToken({ token: 't1', platform: 'android' });
        expect(chain.upsert).toHaveBeenCalledWith({ token: 't1', platform: 'android' }, { onConflict: 'token' });
    });

    test('list returns rows; deleteTokens removes by token set', async () => {
        const listChain = makeChain([{ token: 't1', platform: 'android' }]);
        expect(await createDeviceRepo({ from: () => listChain }).list()).toEqual([{ token: 't1', platform: 'android' }]);
        const del = makeChain([], null);
        await createDeviceRepo({ from: () => del }).deleteTokens(['t1', 't2']);
        expect(del.in).toHaveBeenCalledWith('token', ['t1', 't2']);
    });
});
