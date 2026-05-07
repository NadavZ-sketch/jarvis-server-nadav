'use strict';
const { computeDeltas, fingerprint } = require('../../agents/e2e/learning');

function fp(target, finding) { return fingerprint(target, finding); }

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
