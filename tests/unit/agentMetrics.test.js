const agentMetrics = require('../../services/agentMetrics');

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
