'use strict';

const { recordEvent, aggregateEvents, SIGNAL_VALUE } = require('../../services/feedbackStore');
const { makeChain } = require('../helpers/supabaseMock');

function makeSupabase(chain) {
  return { from: jest.fn(() => chain) };
}

describe('SIGNAL_VALUE', () => {
  test('maps thumbs up/down to numeric values', () => {
    expect(SIGNAL_VALUE.up).toBe(1);
    expect(SIGNAL_VALUE.down).toBe(-1);
  });
});

describe('recordEvent', () => {
  test('rejects a missing event name without touching the db', async () => {
    const supabase = makeSupabase(makeChain());
    const res = await recordEvent(supabase, { eventName: '' });
    expect(res).toEqual({ ok: false, reason: 'missing_event_name' });
    expect(supabase.from).not.toHaveBeenCalled();
  });

  test('inserts a well-formed row and returns ok', async () => {
    const chain = makeChain([], null);
    const supabase = makeSupabase(chain);
    const res = await recordEvent(supabase, {
      userId: 'u1', eventName: 'feedback', value: -1, metadata: { reason: 'wrong' },
    });
    expect(res).toEqual({ ok: true });
    expect(supabase.from).toHaveBeenCalledWith('smart_telemetry_events');
    expect(chain.insert).toHaveBeenCalledWith([{
      user_id: 'u1', event_name: 'feedback', event_value: -1, metadata: { reason: 'wrong' },
    }]);
  });

  test('coerces a non-finite value to 0 and a non-object metadata to {}', async () => {
    const chain = makeChain([], null);
    const supabase = makeSupabase(chain);
    await recordEvent(supabase, { eventName: 'x', value: NaN, metadata: 'nope' });
    expect(chain.insert).toHaveBeenCalledWith([
      expect.objectContaining({ event_value: 0, metadata: {} }),
    ]);
  });

  test('defaults userId to "default"', async () => {
    const chain = makeChain([], null);
    const supabase = makeSupabase(chain);
    await recordEvent(supabase, { eventName: 'x' });
    expect(chain.insert).toHaveBeenCalledWith([
      expect.objectContaining({ user_id: 'default', event_value: 1 }),
    ]);
  });

  test('suppresses db errors and never throws', async () => {
    const supabase = makeSupabase(makeChain(null, { message: 'db down' }));
    const res = await recordEvent(supabase, { eventName: 'x' });
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
    const supabase = makeSupabase(makeChain(rows));
    const res = await aggregateEvents(supabase, { userId: 'u1' });
    expect(res.ok).toBe(true);
    expect(res.counts).toEqual({ feedback: 1, open_app: 1 });
    expect(res.total).toBe(4);
  });

  test('filters by the sinceDays window (gte on created_at)', async () => {
    const chain = makeChain([]);
    const supabase = makeSupabase(chain);
    await aggregateEvents(supabase, { userId: 'u1', sinceDays: 7 });
    expect(chain.gte).toHaveBeenCalledWith('created_at', expect.any(String));
    const sinceArg = chain.gte.mock.calls[0][1];
    const ageDays = (Date.now() - new Date(sinceArg).getTime()) / 86400000;
    expect(ageDays).toBeCloseTo(7, 0);
    expect(chain.eq).toHaveBeenCalledWith('user_id', 'u1');
  });

  test('returns a safe empty shape on db error', async () => {
    const supabase = makeSupabase(makeChain(null, { message: 'boom' }));
    const res = await aggregateEvents(supabase, {});
    expect(res).toEqual({ ok: false, reason: 'boom', counts: {}, total: 0, events: [] });
  });
});
