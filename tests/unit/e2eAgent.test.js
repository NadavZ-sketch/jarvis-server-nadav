'use strict';

// Mock probe modules and learning before requiring the agent
jest.mock('../../agents/e2e/apiProbe', () => ({
    runApiProbe: jest.fn(async () => ({
        findings: [{ severity: 'high', category: 'reliability', target: 'GET /tasks', finding: '500', recommendation: 'fix' }],
        samples: [{ query: 'שלום', answer: 'היי', latency_ms: 100 }],
        reachable: true,
    })),
}));
jest.mock('../../agents/e2e/staticScan', () => ({
    runStaticScan: jest.fn(async () => ({
        findings: [{ severity: 'low', category: 'performance', target: 'server.js', finding: 'sync IO', recommendation: 'use async' }],
        summary: 'all good',
    })),
}));
jest.mock('../../agents/e2e/flutterScan', () => ({
    runFlutterScan: jest.fn(async () => ({ findings: [] })),
}));
jest.mock('../../agents/e2e/uxScan', () => ({
    runUxScan: jest.fn(async () => ({ findings: [] })),
}));
jest.mock('../../agents/e2e/codeErrorScanner', () => ({
    runCodeErrorScanner: jest.fn(async () => ({
        findings: [
            { severity: 'critical', category: 'security', target: 'server.js:5', finding: 'eval used', recommendation: 'remove eval', source: 'pattern' },
            { severity: 'medium', category: 'bug', target: 'agents/x.js', finding: 'maybe race', recommendation: 'add lock', source: 'llm' },
        ],
    })),
}));
jest.mock('../../agents/e2e/learning', () => ({
    loadContext: jest.fn(async () => ({
        regressions: [], flakiness: [], stableTargets: [], hotTargets: [],
        sampleBank: [], lastRunFindings: [], movingAvgScore: 80, learnedProbes: [],
    })),
    computeDeltas: jest.fn(() => ({ newCount: 2, regressionCount: 0, resolvedCount: 0, flakyCount: 0 })),
    distill: jest.fn(async () => ({ added: 1, pruned: 0, promoted: [] })),
    fingerprint: (t, f) => `${t}:${f}`,
}));

const { runE2EAgent } = require('../../agents/e2eAgent');

describe('runE2EAgent', () => {
    test('aggregates findings, formats Hebrew answer, returns action', async () => {
        const supabase = { from: jest.fn(() => ({ insert: jest.fn(async () => ({})) })) };

        const result = await runE2EAgent('בצע בדיקות קצה', supabase, false, { disableLearning: true });

        expect(result.answer).toContain('דוח בדיקות E2E');
        expect(result.answer).toContain('🔴 קריטי');
        expect(result.action.type).toBe('e2e_report');
        expect(typeof result.action.runId).toBe('string');
        expect(result.action.counts.high).toBeGreaterThanOrEqual(1);
    });

    test('skipProbes excludes a probe', async () => {
        const { runApiProbe } = require('../../agents/e2e/apiProbe');
        runApiProbe.mockClear();

        await runE2EAgent('', null, false, { skipProbes: ['api'], disableLearning: true });
        expect(runApiProbe).not.toHaveBeenCalled();
    });

    test('separates measured findings from AI evaluations in the report', async () => {
        const result = await runE2EAgent('בצע בדיקות קצה', null, false, { disableLearning: true });
        // Headers for both buckets are present
        expect(result.answer).toContain('נמדד ודאית');
        expect(result.answer).toContain('הערכת AI');
        // Measured: API finding + the regex (pattern) code finding; Evaluated: static + llm code finding
        expect(result.answer).toContain('eval used');   // pattern → measured
        expect(result.answer).toContain('sync IO');      // static → evaluated
        expect(result.action.inconclusive).toBe(false);
    });

    test('reports "no data" (no score) when the server is unreachable and nothing measured', async () => {
        const { runApiProbe } = require('../../agents/e2e/apiProbe');
        const { runCodeErrorScanner } = require('../../agents/e2e/codeErrorScanner');
        runApiProbe.mockResolvedValueOnce({
            findings: [{ severity: 'critical', category: 'reliability', target: 'GET /health', finding: 'Network error', recommendation: 'start server' }],
            samples: [],
            reachable: false,
        });
        // Only AI evaluations available, no measured findings
        runCodeErrorScanner.mockResolvedValueOnce({ findings: [] });

        const result = await runE2EAgent('בצע בדיקות קצה', null, false, { disableLearning: true });
        expect(result.action.inconclusive).toBe(true);
        expect(result.action.score).toBeNull();
        expect(result.answer).toContain('לא נאספו מספיק נתונים');
    });
});
