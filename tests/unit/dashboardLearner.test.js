'use strict';

const { getDashboardLayout, DEFAULT_ORDER, MIN_SIGNAL } = require('../../services/dashboardLearner');
const { makeChain } = require('../helpers/supabaseMock');

// Build a supabase stub whose telemetry query resolves with the given event rows.
function makeSupabase(rows) {
  return { from: jest.fn(() => makeChain(rows, null)) };
}

// Convenience: N tab-view events for a given tab.
function views(tab, n) {
  return Array.from({ length: n }, () => ({
    event_name: 'dashboard_tab_view', event_value: 1, metadata: { tab }, created_at: new Date().toISOString(),
  }));
}

describe('dashboardLearner.getDashboardLayout', () => {
  test('returns the default order with no supabase client', async () => {
    const out = await getDashboardLayout(null);
    expect(out.learned).toBe(false);
    expect(out.order).toEqual(DEFAULT_ORDER);
    expect(out.spotlight).toBeNull();
  });

  test('keeps default order below the minimum signal threshold', async () => {
    const supabase = makeSupabase(views('analytics', MIN_SIGNAL - 1));
    const out = await getDashboardLayout(supabase, { userId: 'u1' });
    expect(out.learned).toBe(false);
    expect(out.order).toEqual(DEFAULT_ORDER);
  });

  test('reorders most-used tab first once there is enough signal', async () => {
    const rows = [...views('analytics', 8), ...views('agents', 3)];
    const supabase = makeSupabase(rows);
    const out = await getDashboardLayout(supabase, { userId: 'u1' });
    expect(out.learned).toBe(true);
    expect(out.order[0]).toBe('analytics');
    expect(out.spotlight).toBe('analytics');
    expect(out.counts.analytics).toBe(8);
    // Every canonical tab is still present exactly once.
    expect([...out.order].sort()).toEqual([...DEFAULT_ORDER].sort());
  });

  test('ignores unknown tab ids and non-view events', async () => {
    const rows = [
      ...views('overview', 6),
      { event_name: 'dashboard_tab_view', event_value: 1, metadata: { tab: 'bogus' }, created_at: new Date().toISOString() },
      { event_name: 'feedback_up', event_value: 1, metadata: {}, created_at: new Date().toISOString() },
    ];
    const supabase = makeSupabase(rows);
    const out = await getDashboardLayout(supabase, { userId: 'u1' });
    expect(out.order[0]).toBe('overview');
    expect(out.counts.bogus).toBeUndefined();
  });

  test('degrades gracefully when the query throws', async () => {
    const supabase = { from: jest.fn(() => { throw new Error('db down'); }) };
    const out = await getDashboardLayout(supabase, { userId: 'u1' });
    expect(out.learned).toBe(false);
    expect(out.order).toEqual(DEFAULT_ORDER);
  });
});
