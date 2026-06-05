'use strict';

const { createRemindersController } = require('../../controllers/remindersController');
const { makeChain } = require('../helpers/supabaseMock');

function makeRes() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

describe('remindersController.list', () => {
  test('returns only unfired reminders ordered by time', async () => {
    const rows = [{ id: 1, text: 'a', scheduled_time: '2026-06-05T18:00:00Z', fired: false }];
    const chain = makeChain(rows);
    const ctrl = createRemindersController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.list({}, res);
    expect(chain.eq).toHaveBeenCalledWith('fired', false);
    expect(res.body.reminders).toHaveLength(1);
  });

  test('500 with empty list on error', async () => {
    const ctrl = createRemindersController({ supabase: { from: () => makeChain(null, { message: 'x' }) } });
    const res = makeRes();
    await ctrl.list({}, res);
    expect(res.statusCode).toBe(500);
    expect(res.body.reminders).toEqual([]);
  });
});

describe('remindersController.create', () => {
  test('rejects when text or scheduled_time is missing', async () => {
    const ctrl = createRemindersController({ supabase: { from: () => makeChain() } });
    const res = makeRes();
    await ctrl.create({ body: { text: 'only text' } }, res);
    expect(res.statusCode).toBe(400);
  });

  test('persists a valid reminder and echoes the row', async () => {
    const row = { id: 9, text: 'להתקשר', scheduled_time: '2026-06-05T18:00:00Z', fired: false };
    const chain = makeChain(row);
    const ctrl = createRemindersController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.create({ body: { text: 'להתקשר', scheduled_time: '2026-06-05T18:00:00Z' } }, res);
    expect(chain.insert).toHaveBeenCalledWith([
      { text: 'להתקשר', scheduled_time: '2026-06-05T18:00:00Z', fired: false },
    ]);
    expect(res.body.reminder).toEqual(row);
  });

  test('only persists recurrence from the allowed set', async () => {
    const chain = makeChain({ id: 1 });
    const ctrl = createRemindersController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.create({ body: { text: 't', scheduled_time: 's', recurrence: 'hourly' } }, res);
    expect(chain.insert).toHaveBeenCalledWith([
      expect.not.objectContaining({ recurrence: expect.anything() }),
    ]);
  });
});

describe('remindersController.update', () => {
  test('rejects an empty update', async () => {
    const ctrl = createRemindersController({ supabase: { from: () => makeChain() } });
    const res = makeRes();
    await ctrl.update({ params: { id: '1' }, body: {} }, res);
    expect(res.statusCode).toBe(400);
  });

  test('coerces fired to a boolean and updates by id', async () => {
    const chain = makeChain({ id: 1, fired: true });
    const ctrl = createRemindersController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.update({ params: { id: '1' }, body: { fired: 1 } }, res);
    expect(chain.update).toHaveBeenCalledWith({ fired: true });
    expect(chain.eq).toHaveBeenCalledWith('id', '1');
  });
});

describe('remindersController.remove', () => {
  test('deletes by id and returns ok', async () => {
    const chain = makeChain([]);
    const ctrl = createRemindersController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.remove({ params: { id: '7' } }, res);
    expect(chain.delete).toHaveBeenCalled();
    expect(chain.eq).toHaveBeenCalledWith('id', '7');
    expect(res.body).toEqual({ ok: true });
  });
});

describe('remindersController.check', () => {
  test('fires due reminders, deletes them, and enriches with pinecone context', async () => {
    const due = [{ id: 1, text: 'תרופה', scheduled_time: '2000-01-01T00:00:00Z' }];
    const supabase = { from: jest.fn(() => makeChain(due)) };
    const pinecone = {
      isReady: () => true,
      searchMemories: jest.fn().mockResolvedValue(['לקחת תרופה בבוקר']),
    };
    const ctrl = createRemindersController({ supabase, pinecone });
    const res = makeRes();
    await ctrl.check({}, res);
    expect(pinecone.searchMemories).toHaveBeenCalledWith('תרופה', 2);
    expect(res.body.reminders[0].text).toContain('הקשר:');
  });

  test('returns an empty list when nothing is due', async () => {
    const future = [{ id: 2, text: 'מחר', scheduled_time: '2999-01-01T00:00:00Z' }];
    const ctrl = createRemindersController({ supabase: { from: () => makeChain(future) } });
    const res = makeRes();
    await ctrl.check({}, res);
    expect(res.body.reminders).toEqual([]);
  });
});
