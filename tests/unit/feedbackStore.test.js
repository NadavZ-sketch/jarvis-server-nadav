'use strict';

const { recordEvent, aggregateEvents, SIGNAL_VALUE } = require('../../services/feedbackStore');
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
