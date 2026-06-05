'use strict';

const { createTasksController } = require('../../controllers/tasksController');
const { makeChain } = require('../helpers/supabaseMock');

function makeRes() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

describe('tasksController.list', () => {
  test('returns tasks with embedded subtasks when the relation exists', async () => {
    const rows = [{ id: 1, content: 'משימה', subtasks: [] }];
    const supabase = { from: jest.fn(() => makeChain(rows)) };
    const ctrl = createTasksController({ supabase });
    const res = makeRes();
    await ctrl.list({}, res);
    expect(res.body.tasks).toEqual(rows);
  });

  test('falls back to a plain select when the subtasks relation is missing', async () => {
    const rows = [{ id: 1, content: 'משימה' }];
    const supabase = {
      from: jest.fn()
        .mockImplementationOnce(() => makeChain(null, { message: 'relation "subtasks" does not exist' }))
        .mockImplementationOnce(() => makeChain(rows)),
    };
    const ctrl = createTasksController({ supabase });
    const res = makeRes();
    await ctrl.list({}, res);
    expect(supabase.from).toHaveBeenCalledTimes(2);
    expect(res.body.tasks).toEqual(rows);
  });
});

describe('tasksController.create', () => {
  test('rejects when content is missing', async () => {
    const ctrl = createTasksController({ supabase: { from: () => makeChain() } });
    const res = makeRes();
    await ctrl.create({ body: { priority: 'high' } }, res);
    expect(res.statusCode).toBe(400);
  });

  test('whitelists priority and category, dropping invalid values', async () => {
    const chain = makeChain({ id: 1 });
    const ctrl = createTasksController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.create({ body: { content: 'x', priority: 'urgent', category: 'bogus' } }, res);
    const inserted = chain.insert.mock.calls[0][0][0];
    expect(inserted).toEqual({ content: 'x' });
  });

  test('persists valid optional fields', async () => {
    const chain = makeChain({ id: 1 });
    const ctrl = createTasksController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.create({ body: { content: 'x', priority: 'high', category: 'work', due_date: '2026-06-10' } }, res);
    expect(chain.insert).toHaveBeenCalledWith([
      expect.objectContaining({ content: 'x', priority: 'high', category: 'work', due_date: '2026-06-10' }),
    ]);
  });
});

describe('tasksController.update', () => {
  test('rejects an empty update', async () => {
    const ctrl = createTasksController({ supabase: { from: () => makeChain() } });
    const res = makeRes();
    await ctrl.update({ params: { id: '1' }, body: {} }, res);
    expect(res.statusCode).toBe(400);
  });

  test('updates whitelisted fields by id', async () => {
    const chain = makeChain({ id: 1, done: true });
    const ctrl = createTasksController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.update({ params: { id: '3' }, body: { done: true, priority: 'low' } }, res);
    expect(chain.update).toHaveBeenCalledWith({ done: true, priority: 'low' });
    expect(chain.eq).toHaveBeenCalledWith('id', '3');
  });
});

describe('tasksController.remove', () => {
  test('deletes by id', async () => {
    const chain = makeChain([]);
    const ctrl = createTasksController({ supabase: { from: () => chain } });
    const res = makeRes();
    await ctrl.remove({ params: { id: '4' } }, res);
    expect(chain.eq).toHaveBeenCalledWith('id', '4');
    expect(res.body).toEqual({ ok: true });
  });

  test('500 on delete error', async () => {
    const ctrl = createTasksController({ supabase: { from: () => makeChain(null, { message: 'nope' }) } });
    const res = makeRes();
    await ctrl.remove({ params: { id: '4' } }, res);
    expect(res.statusCode).toBe(500);
    expect(res.body.ok).toBe(false);
  });
});
