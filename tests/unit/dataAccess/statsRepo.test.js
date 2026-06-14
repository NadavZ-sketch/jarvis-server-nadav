'use strict';

const { createStatsRepo } = require('../../../services/dataAccess/statsRepo');

// Every count query resolves to { count: 5 }; the category query yields one
// 'work' row. Chain methods (select/gte/eq) return the thenable chain.
function makeSupabase() {
    const chain = {
        select() { return chain; },
        gte() { return chain; },
        eq() { return chain; },
        then(res) { return Promise.resolve({ count: 5, data: [{ category: 'work' }], error: null }).then(res); },
    };
    return { from: () => chain };
}

describe('statsRepo.dashboardCounts', () => {
    test('aggregates counts and the pending-by-category breakdown', async () => {
        const repo = createStatsRepo(makeSupabase());
        const out = await repo.dashboardCounts('2026-06-14T00:00:00Z');
        expect(out.chat).toEqual({ total: 5, today: 5 });
        expect(out.tasks.total).toBe(5);
        expect(out.tasks.done).toBe(5);
        expect(out.tasks.pending).toBe(0);
        expect(out.tasks.byCategory.work).toBe(1);
        expect(out.shopping).toEqual({ total: 5, checked: 5 });
    });

    test('degrades to 0 when a count query errors', async () => {
        const errChain = {
            select() { return errChain; }, gte() { return errChain; }, eq() { return errChain; },
            then(res) { return Promise.resolve({ count: null, error: { message: 'x' } }).then(res); },
        };
        const repo = createStatsRepo({ from: () => errChain });
        const out = await repo.dashboardCounts('2026-06-14T00:00:00Z');
        expect(out.chat.total).toBe(0);
        expect(out.tasks.byCategory).toEqual({ work: 0, personal: 0, financial: 0, project: 0, general: 0 });
    });
});
