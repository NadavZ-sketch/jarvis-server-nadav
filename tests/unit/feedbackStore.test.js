'use strict';

const { recordEvent, aggregateEvents, computeMisroutePatterns, SIGNAL_VALUE } = require('../../services/feedbackStore');
const { makeTelemetryRepo } = require('../helpers/fakeRepos');

// repos whose telemetry repo records/reads as configured.
function reposWith({ rows = [], recordError = null } = {}) {
  return { telemetry: makeTelemetryRepo({ rows, recordError }) };
}

describe('SIGNAL_VALUE', () => {
  test('maps thumbs up/down to numeric values', () => {
    expect(SIGNAL_VALUE.up).toBe(1);
    expect(SIGNAL_VALUE.down).toBe(-1);
  });
});

describe('recordEvent', () => {
  test('rejects a missing event name without touching the db', async () => {
    const repos = reposWith();
    const res = await recordEvent(repos, { eventName: '' });
    expect(res).toEqual({ ok: false, reason: 'missing_event_name' });
    expect(repos.telemetry.record).not.toHaveBeenCalled();
  });

  test('inserts a well-formed row and returns ok', async () => {
    const repos = reposWith();
    const res = await recordEvent(repos, {
      userId: 'u1', eventName: 'feedback', value: -1, metadata: { reason: 'wrong' },
    });
    expect(res).toEqual({ ok: true });
    expect(repos.telemetry.record).toHaveBeenCalledWith({
      user_id: 'u1', event_name: 'feedback', event_value: -1, metadata: { reason: 'wrong' },
    });
  });

  test('coerces a non-finite value to 0 and a non-object metadata to {}', async () => {
    const repos = reposWith();
    await recordEvent(repos, { eventName: 'x', value: NaN, metadata: 'nope' });
    expect(repos.telemetry.record).toHaveBeenCalledWith(
      expect.objectContaining({ event_value: 0, metadata: {} }),
    );
  });

  test('defaults userId to "default"', async () => {
    const repos = reposWith();
    await recordEvent(repos, { eventName: 'x' });
    expect(repos.telemetry.record).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: 'default', event_value: 1 }),
    );
  });

  test('suppresses db errors and never throws', async () => {
    const repos = reposWith({ recordError: { message: 'db down' } });
    const res = await recordEvent(repos, { eventName: 'x' });
    expect(res).toEqual({ ok: false, reason: 'db down' });
  });
});

describe('aggregateEvents', () => {
  test('sums event_value per event_name', async () => {
    const rows = [
      { event_name: 'feedback', event_value: 1 },
      { event_name: 'feedback', event_value: -1 },
      { event_name: 'feedback', event_value: 1 },
      { event_name: 'open_app', event_value: 1 },
    ];
    const res = await aggregateEvents(reposWith({ rows }), { userId: 'u1' });
    expect(res.ok).toBe(true);
    expect(res.counts).toEqual({ feedback: 1, open_app: 1 });
    expect(res.total).toBe(4);
  });

  test('passes the user + sinceDays window to the repo', async () => {
    const repos = reposWith({ rows: [] });
    await aggregateEvents(repos, { userId: 'u1', sinceDays: 7 });
    const [userId, sinceArg] = repos.telemetry.recentEvents.mock.calls[0];
    expect(userId).toBe('u1');
    const ageDays = (Date.now() - new Date(sinceArg).getTime()) / 86400000;
    expect(ageDays).toBeCloseTo(7, 0);
  });

  test('returns a safe empty shape on db error', async () => {
    const repos = { telemetry: { recentEvents: jest.fn(async () => { throw new Error('boom'); }) } };
    const res = await aggregateEvents(repos, {});
    expect(res).toEqual({ ok: false, reason: 'boom', counts: {}, total: 0, events: [] });
  });
});

describe('computeMisroutePatterns', () => {
  const row = (routedIntent, snippet, created_at, correction) => ({
    metadata: { routedIntent, snippet, ...(correction ? { correction } : {}) },
    created_at,
  });

  test('groups repeated misroutes of the same message + wrong intent', () => {
    const rows = [
      row('chat', 'תזכיר לי לקנות חלב', '2026-07-01T10:00:00Z'),
      row('chat', 'תזכיר לי לקנות חלב', '2026-07-02T10:00:00Z'),
    ];
    const res = computeMisroutePatterns(rows);
    expect(res).toHaveLength(1);
    expect(res[0]).toMatchObject({
      routedIntent: 'chat',
      count: 2,
      suggestedKeyword: 'תזכיר לי לקנות חלב',
      lastSeenAt: '2026-07-02T10:00:00Z',
    });
  });

  test('drops a single occurrence below the default threshold (noise, not a pattern)', () => {
    const res = computeMisroutePatterns([row('chat', 'משהו חד פעמי', '2026-07-01T10:00:00Z')]);
    expect(res).toEqual([]);
  });

  test('respects a custom minOccurrences', () => {
    const rows = [row('chat', 'x', 't1'), row('chat', 'x', 't2'), row('chat', 'x', 't3')];
    expect(computeMisroutePatterns(rows, { minOccurrences: 3 })).toHaveLength(1);
    expect(computeMisroutePatterns(rows, { minOccurrences: 4 })).toEqual([]);
  });

  test('normalizes whitespace/case so near-identical messages still group together', () => {
    const rows = [
      row('chat', '  שלח   הודעה  לאמא  ', 't1'),
      row('chat', 'שלח הודעה לאמא', 't2'),
    ];
    expect(computeMisroutePatterns(rows)).toHaveLength(1);
  });

  test('keeps different routedIntents for the same message as separate patterns', () => {
    const rows = [
      row('chat', 'קבע פגישה מחר', 't1'), row('chat', 'קבע פגישה מחר', 't2'),
      row('task', 'קבע פגישה מחר', 't3'), row('task', 'קבע פגישה מחר', 't4'),
    ];
    const res = computeMisroutePatterns(rows);
    expect(res).toHaveLength(2);
    expect(res.map(r => r.routedIntent).sort()).toEqual(['chat', 'task']);
  });

  test('sorts by count desc, then most-recent first', () => {
    const rows = [
      row('chat', 'a', 't1'), row('chat', 'a', 't2'),
      row('chat', 'b', 't3'), row('chat', 'b', 't4'), row('chat', 'b', 't5'),
    ];
    const res = computeMisroutePatterns(rows);
    expect(res.map(r => r.suggestedKeyword)).toEqual(['b', 'a']);
  });

  test('carries the first correction text seen for a group', () => {
    const rows = [
      row('chat', 'תזכיר לי', 't1', 'זה היה אמור להיות תזכורת'),
      row('chat', 'תזכיר לי', 't2'),
    ];
    expect(computeMisroutePatterns(rows)[0].correction).toBe('זה היה אמור להיות תזכורת');
  });

  test('ignores rows missing routedIntent or snippet', () => {
    const rows = [
      { metadata: { snippet: 'no intent here' }, created_at: 't1' },
      { metadata: { routedIntent: 'chat' }, created_at: 't1' },
      { metadata: null, created_at: 't1' },
      {},
    ];
    expect(computeMisroutePatterns(rows)).toEqual([]);
  });
});
