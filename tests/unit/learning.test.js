'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const {
    computeDeltas, fingerprint, loadContext, distill, PROMOTE_HITS,
} = require('../../agents/e2e/learning');
const { makeChain, makeSupabase } = require('../helpers/supabaseMock');

function fp(target, finding) { return fingerprint(target, finding); }

beforeEach(() => jest.clearAllMocks());

describe('learning.computeDeltas', () => {
    test('classifies new findings as new and counts resolved from last run', () => {
        const lastRun = [
            { target: 'POST /ask-jarvis', finding: 'Slow', fingerprint: fp('POST /ask-jarvis', 'Slow') },
            { target: 'GET /tasks',        finding: '500',  fingerprint: fp('GET /tasks', '500') },
        ];
        const current = [
            { target: 'GET /tasks',        finding: '500'  }, // regression
            { target: 'POST /chat',        finding: 'New thing' }, // new
        ];
        const ctx = {
            lastRunFindings: lastRun,
            regressions: [fp('GET /tasks', '500')],
            flakiness: [],
        };
        const d = computeDeltas(current, ctx);
        expect(d.regressionCount).toBe(1);
        expect(d.newCount).toBe(1);
        expect(d.resolvedCount).toBe(1); // POST /ask-jarvis no longer present
        expect(current[0].status).toBe('regression');
        expect(current[1].status).toBe('new');
    });

    test('flaky takes precedence over regression', () => {
        const f = { target: 'GET /x', finding: 'flake' };
        const fpx = fp('GET /x', 'flake');
        const ctx = {
            lastRunFindings: [],
            regressions: [fpx],
            flakiness: [fpx],
        };
        const d = computeDeltas([f], ctx);
        expect(f.status).toBe('flaky');
        expect(d.flakyCount).toBe(1);
        expect(d.regressionCount).toBe(0);
    });

    test('handles empty inputs', () => {
        const d = computeDeltas([], { lastRunFindings: [], regressions: [], flakiness: [] });
        expect(d).toEqual({ newCount: 0, regressionCount: 0, resolvedCount: 0, flakyCount: 0 });
    });

    test('fingerprint is deterministic and stable for same inputs', () => {
        expect(fp('a', 'b')).toBe(fp('a', 'b'));
        expect(fp('a', 'b')).not.toBe(fp('a', 'c'));
    });
});

describe('learning.loadContext', () => {
    test('returns the empty context when no supabase client is supplied', async () => {
        const ctx = await loadContext(null);
        expect(ctx.movingAvgScore).toBeNull();
        expect(ctx.regressions).toEqual([]);
        expect(ctx.learnedProbes).toEqual([]);
    });

    test('falls back to active learned-probes when there is no run history', async () => {
        const supabase = makeSupabase({
            e2e_reports: [],
            e2e_learned_probes: [{ id: 'p1', kind: 'api', active: true }],
        });
        const ctx = await loadContext(supabase);
        expect(ctx.lastRunFindings).toEqual([]);
        expect(ctx.learnedProbes).toEqual([{ id: 'p1', kind: 'api', active: true }]);
    });

    test('derives regressions, hot targets, sample bank and a moving-average score from history', async () => {
        // Both e2e_reports queries (run list, then findings) read the same seeded
        // rows; rows carry run_id + created_at so they serve as both.
        const reports = [
            { run_id: 'r3', created_at: '2026-06-05', severity: 'high', target: 'POST /ask-jarvis', finding: 'asked "מה השעה עכשיו" got nothing', fingerprint: 'fpA' },
            { run_id: 'r2', created_at: '2026-06-04', severity: 'high', target: 'POST /ask-jarvis', finding: 'asked "מה השעה עכשיו" got nothing', fingerprint: 'fpA' },
            { run_id: 'r1', created_at: '2026-06-03', severity: 'critical', target: 'GET /tasks', finding: '500', fingerprint: 'fpB' },
        ];
        const supabase = makeSupabase({
            e2e_reports: reports,
            e2e_learned_probes: [{ id: 'pp', active: true }],
        });
        const ctx = await loadContext(supabase);

        expect(ctx.regressions).toContain('fpA');        // present in r3 and r2
        expect(ctx.regressions).not.toContain('fpB');     // only one run
        expect(ctx.hotTargets).toContain('POST /ask-jarvis');
        expect(ctx.sampleBank).toContain('מה השעה עכשיו'); // quoted query mined from finding
        expect(typeof ctx.movingAvgScore).toBe('number');
        expect(ctx.learnedProbes).toEqual([{ id: 'pp', active: true }]);
    });

    test('a thrown supabase error degrades to the empty context', async () => {
        const supabase = { from: jest.fn(() => { throw new Error('db down'); }) };
        const ctx = await loadContext(supabase);
        expect(ctx.movingAvgScore).toBeNull();
        expect(ctx.regressions).toEqual([]);
    });
});

describe('learning.distill', () => {
    test('returns a no-op summary without a supabase client', async () => {
        const res = await distill(null, [], {});
        expect(res).toEqual({ added: 0, pruned: 0, promoted: [] });
    });

    test('reinforces a hit and promotes a probe that crosses the hit threshold', async () => {
        // Track every chain so we can assert the reinforcement update payload.
        const chains = [];
        const supabase = { from: jest.fn(() => { const c = makeChain([]); chains.push(c); return c; }) };
        callGemma4.mockResolvedValue('[]'); // no new proposals

        const probe = { id: 'p1', target: 'GET /tasks', hits: PROMOTE_HITS - 1, misses: 0 };
        const findings = [{ target: 'GET /tasks', finding: '500', fingerprint: 'x' }];
        const res = await distill(supabase, findings, { learnedProbes: [probe] });

        expect(res.promoted).toContainEqual(probe);
        // first chain is the reinforcement update for p1
        expect(chains[0].update).toHaveBeenCalledWith(expect.objectContaining({ hits: PROMOTE_HITS }));
    });

    test('counts a miss when no current finding matches the probe', async () => {
        const chains = [];
        const supabase = { from: jest.fn(() => { const c = makeChain([]); chains.push(c); return c; }) };
        callGemma4.mockResolvedValue('[]');

        const probe = { id: 'p2', target: 'GET /unrelated', query: 'nope', hits: 0, misses: 1 };
        const res = await distill(supabase, [{ target: 'GET /tasks', finding: '500' }], { learnedProbes: [probe] });

        expect(res.promoted).toEqual([]);
        expect(chains[0].update).toHaveBeenCalledWith(expect.objectContaining({ misses: 2 }));
    });

    test('persists up to five valid LLM-proposed probes and reports the added count', async () => {
        // Queue results per .from() call: [reinforce?, prune, insert, active-cap].
        // No existing probes, so the sequence is prune → insert → active select.
        const results = [
            [[]],                 // prune .select('id')
            [[{ id: 'new1' }]],   // insert .select('id') → 1 added
            [[]],                 // active-cap select
        ];
        let i = 0;
        const supabase = { from: jest.fn(() => makeChain(...(results[i++] || [[]]))) };
        callGemma4.mockResolvedValue(JSON.stringify([
            { kind: 'api', target: 'POST /ask-jarvis', query: 'בדיקה', reason: 'r' },
            { kind: 'bogus', target: 'x' }, // filtered out — invalid kind
        ]));

        const res = await distill(supabase, [{ target: 'GET /tasks', finding: '500' }], { learnedProbes: [] });
        expect(res.added).toBe(1);
    });

    test('swallows an LLM/database error and still returns a summary', async () => {
        const supabase = { from: jest.fn(() => { throw new Error('boom'); }) };
        const res = await distill(supabase, [{ target: 'x', finding: 'y' }], { learnedProbes: [] });
        expect(res).toEqual({ added: 0, pruned: 0, promoted: [] });
    });
});
