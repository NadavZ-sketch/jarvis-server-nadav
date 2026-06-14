'use strict';

const { createTelemetryRepo } = require('../../../services/dataAccess/telemetryRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('telemetryRepo', () => {
    test('record inserts the event row', async () => {
        const chain = makeChain([], null);
        await createTelemetryRepo({ from: () => chain }).record({ event_name: 'feedback', event_value: 1 });
        expect(chain.insert).toHaveBeenCalledWith([{ event_name: 'feedback', event_value: 1 }]);
    });

    test('recentEvents filters by window + user, ordered, limited; throws on error', async () => {
        const chain = makeChain([{ event_name: 'x', event_value: 1 }]);
        const repo = createTelemetryRepo({ from: () => chain });
        const rows = await repo.recentEvents('u1', '2026-06-01', 1000);
        expect(chain.gte).toHaveBeenCalledWith('created_at', '2026-06-01');
        expect(chain.eq).toHaveBeenCalledWith('user_id', 'u1');
        expect(chain.limit).toHaveBeenCalledWith(1000);
        expect(rows).toEqual([{ event_name: 'x', event_value: 1 }]);

        const bad = createTelemetryRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.recentEvents('u1', '2026-06-01', 10)).rejects.toEqual({ message: 'boom' });
    });

    test('recentEvents omits the user filter when no userId', async () => {
        const chain = makeChain([]);
        await createTelemetryRepo({ from: () => chain }).recentEvents(null, '2026-06-01', 10);
        expect(chain.eq).not.toHaveBeenCalled();
    });
});
