const agentMetrics = require('../../services/agentMetrics');

// repos whose metrics repo records batches / returns DB rows as configured.
function reposWith({ insertBatch, recentSince } = {}) {
    return {
        metrics: {
            insertBatch: insertBatch || jest.fn(async () => ({ error: null })),
            recentSince: recentSince || jest.fn(async () => []),
        },
    };
}

describe('agentMetrics (in-memory fallback)', () => {
    // No supabase client → snapshot uses the lifetime in-memory aggregate.
    it('records latency and reports per-agent averages', async () => {
        agentMetrics.record('weatherAgent', 100, 'fast');
        agentMetrics.record('weatherAgent', 300, 'fast');
        agentMetrics.record('taskAgent', 50, 'llm');

        const snap = await agentMetrics.snapshot();
        const weather = snap.latency.find(l => l.agent === 'weatherAgent');
        const task = snap.latency.find(l => l.agent === 'taskAgent');

        expect(weather).toBeTruthy();
        expect(weather.avgMs).toBe(200);
        expect(weather.count).toBe(2);
        expect(task.avgMs).toBe(50);
    });

    it('counts intent classification modes', async () => {
        const snap = await agentMetrics.snapshot();
        expect(snap.intent.fast).toBeGreaterThanOrEqual(2);
        expect(snap.intent.llm).toBeGreaterThanOrEqual(1);
    });

    it('ignores non-numeric / missing input', async () => {
        const before = await agentMetrics.snapshot();
        agentMetrics.record('', 100, 'fast');
        agentMetrics.record('ghostAgent', NaN, 'fast');
        const after = await agentMetrics.snapshot();
        expect(after.latency.find(l => l.agent === 'ghostAgent')).toBeFalsy();
        expect(after.latency.length).toBe(before.latency.length);
    });
});

describe('agentMetrics (supabase-backed)', () => {
    afterEach(() => agentMetrics.stop()); // prevent timer leak between tests

    test('flush writes the pending batch to agent_metrics and then no-ops when empty', async () => {
        const insertBatch = jest.fn(async () => ({ error: null }));
        agentMetrics.init(reposWith({ insertBatch }));
        agentMetrics.record('flushAgent', 120, 'fast');

        await agentMetrics.flush();
        expect(insertBatch).toHaveBeenCalledWith(expect.arrayContaining([
            expect.objectContaining({ agent: 'flushAgent', ms: 120, intent_mode: 'fast' }),
        ]));

        insertBatch.mockClear();
        await agentMetrics.flush();             // nothing pending → no insert
        expect(insertBatch).not.toHaveBeenCalled();
    });

    test('a failed flush re-queues the batch so a later flush still sends it', async () => {
        const insertBatch = jest.fn()
            .mockResolvedValueOnce({ error: { message: 'db down' } })
            .mockResolvedValueOnce({ error: null });
        agentMetrics.init(reposWith({ insertBatch }));
        agentMetrics.record('retryAgent', 200, 'llm');

        await agentMetrics.flush();             // fails → row stays pending
        await agentMetrics.flush();             // recovers
        expect(insertBatch).toHaveBeenLastCalledWith(expect.arrayContaining([
            expect.objectContaining({ agent: 'retryAgent' }),
        ]));
    });

    test('snapshot aggregates the DB window and merges still-pending rows', async () => {
        const dbRows = [
            { agent: 'dbAgent', ms: 100, intent_mode: 'fast', created_at: '2026-06-05T10:00:00Z' },
            { agent: 'dbAgent', ms: 300, intent_mode: 'llm', created_at: '2026-06-05T11:00:00Z' },
        ];
        agentMetrics.init(reposWith({ recentSince: jest.fn(async () => dbRows) }));
        agentMetrics.record('dbAgent', 200, 'fast'); // unflushed → must be merged on top

        const snap = await agentMetrics.snapshot();
        const db = snap.latency.find(l => l.agent === 'dbAgent');
        expect(db.count).toBe(3);              // 2 from DB + 1 pending
        expect(db.avgMs).toBe(200);            // (100+300+200)/3
    });

    test('snapshot falls back to the in-memory lifetime aggregate on a DB error', async () => {
        agentMetrics.init(reposWith({ recentSince: jest.fn(async () => { throw new Error('read failed'); }) }));

        const snap = await agentMetrics.snapshot();
        expect(Array.isArray(snap.latency)).toBe(true);
        expect(snap.latency.length).toBeGreaterThan(0); // lifetime accrued from earlier tests
    });
});
