'use strict';

const { createTasksController } = require('../../controllers/tasksController');
const { makeTaskRepo } = require('../helpers/fakeRepos');

function makeRes() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

// The controller crosses the data-access seam via repos.tasks; the
// subtasks-relation fallback now lives in taskRepo (see dataAccess/taskRepo.test).
const ctrlWith = (repo) => createTasksController({ repos: { tasks: repo } });

describe('tasksController.list', () => {
  test('returns the rows the task repo yields', async () => {
    const rows = [{ id: 1, content: 'משימה', subtasks: [] }];
    const repo = makeTaskRepo({ rows });
    const res = makeRes();
    await ctrlWith(repo).list({}, res);
    expect(repo.listWithSubtasks).toHaveBeenCalled();
    expect(res.body.tasks).toEqual(rows);
  });
});

describe('tasksController.create', () => {
  test('rejects when content is missing', async () => {
    const repo = makeTaskRepo();
    const res = makeRes();
    await ctrlWith(repo).create({ body: { priority: 'high' } }, res);
    expect(res.statusCode).toBe(400);
    expect(repo.create).not.toHaveBeenCalled();
  });

  test('whitelists priority and category, dropping invalid values', async () => {
    const repo = makeTaskRepo({ rows: [{ id: 1 }] });
    const res = makeRes();
    await ctrlWith(repo).create({ body: { content: 'x', priority: 'urgent', category: 'bogus' } }, res);
    expect(repo.create).toHaveBeenCalledWith({ content: 'x' });
  });

  test('persists valid optional fields', async () => {
    const repo = makeTaskRepo({ rows: [{ id: 1 }] });
    const res = makeRes();
    await ctrlWith(repo).create({ body: { content: 'x', priority: 'high', category: 'work', due_date: '2026-06-10' } }, res);
    expect(repo.create).toHaveBeenCalledWith(
      expect.objectContaining({ content: 'x', priority: 'high', category: 'work', due_date: '2026-06-10' })
    );
  });

  test('persists a valid recurrence and nulls an invalid one', async () => {
    const repo = makeTaskRepo({ rows: [{ id: 1 }] });
    const res = makeRes();
    await ctrlWith(repo).create({ body: { content: 'x', recurrence: 'weekly' } }, res);
    expect(repo.create).toHaveBeenCalledWith(expect.objectContaining({ recurrence: 'weekly' }));

    repo.create.mockClear();
    await ctrlWith(repo).create({ body: { content: 'y', recurrence: 'none' } }, res);
    expect(repo.create).toHaveBeenCalledWith(expect.objectContaining({ recurrence: null }));
  });
});

describe('tasksController.update', () => {
  test('rejects an empty update', async () => {
    const repo = makeTaskRepo();
    const res = makeRes();
    await ctrlWith(repo).update({ params: { id: '1' }, body: {} }, res);
    expect(res.statusCode).toBe(400);
    expect(repo.update).not.toHaveBeenCalled();
  });

  test('updates whitelisted fields by id', async () => {
    const repo = makeTaskRepo({ rows: [{ id: 1, done: true }] });
    const res = makeRes();
    await ctrlWith(repo).update({ params: { id: '3' }, body: { done: true, priority: 'low' } }, res);
    expect(repo.update).toHaveBeenCalledWith('3', { done: true, priority: 'low' });
  });

  test('updates recurrence, coercing invalid values to null', async () => {
    const repo = makeTaskRepo({ rows: [{ id: 1 }] });
    const res = makeRes();
    await ctrlWith(repo).update({ params: { id: '3' }, body: { recurrence: 'monthly' } }, res);
    expect(repo.update).toHaveBeenCalledWith('3', { recurrence: 'monthly' });

    repo.update.mockClear();
    await ctrlWith(repo).update({ params: { id: '3' }, body: { recurrence: 'none' } }, res);
    expect(repo.update).toHaveBeenCalledWith('3', { recurrence: null });
  });
});

describe('tasksController.remove', () => {
  test('deletes by id', async () => {
    const repo = makeTaskRepo();
    const res = makeRes();
    await ctrlWith(repo).remove({ params: { id: '4' } }, res);
    expect(repo.deleteById).toHaveBeenCalledWith('4');
    expect(res.body).toEqual({ ok: true });
  });

  test('500 on delete error', async () => {
    const repo = makeTaskRepo({ removeResult: { error: { message: 'nope' } } });
    const res = makeRes();
    await ctrlWith(repo).remove({ params: { id: '4' } }, res);
    expect(res.statusCode).toBe(500);
    expect(res.body.ok).toBe(false);
  });
});
