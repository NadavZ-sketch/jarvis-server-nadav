'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const express = require('express');
const request = require('supertest');
const { callGemma4 } = require('../../agents/models');
const { createTasksRouter } = require('../../routes/tasks');
const { makeChain } = require('../helpers/supabaseMock');

function mountApp(supabase) {
  const app = express();
  app.use(express.json());
  app.use('/tasks', createTasksRouter({ supabase }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /tasks/today', () => {
  test('buckets tasks into overdue/today/no_due_date and appends reminders', async () => {
    const now = new Date();
    const todayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const taskRows = [
      { id: 1, content: 'overdue task', done: false, due_date: '2000-01-01T00:00:00Z', priority: 'high' },
      { id: 2, content: 'today task', done: false, due_date: new Date(todayStart.getTime() + 3600000).toISOString(), priority: 'medium' },
      { id: 3, content: 'no-date task', done: false, due_date: null },
      { id: 4, content: 'future task', done: false, due_date: '2999-01-01T00:00:00Z' },
    ];
    const reminderRows = [{ id: 9, text: 'reminder', scheduled_time: todayStart.toISOString(), fired: false, recurrence: null }];
    const supabase = {
      from: jest.fn()
        .mockImplementationOnce(() => makeChain(taskRows))      // tasks query
        .mockImplementationOnce(() => makeChain(reminderRows)), // reminders query
    };

    const res = await request(mountApp(supabase)).get('/tasks/today');

    expect(res.status).toBe(200);
    const sections = res.body.items.map(i => i.section);
    expect(sections).toContain('overdue');
    expect(sections).toContain('today');
    expect(sections).toContain('no_due_date');
    expect(sections).toContain('reminder');
    // future task is excluded
    expect(res.body.items.find(i => i.title === 'future task')).toBeUndefined();
  });

  test('500 with empty items on db failure', async () => {
    const supabase = { from: jest.fn(() => { throw new Error('boom'); }) };
    const res = await request(mountApp(supabase)).get('/tasks/today');
    expect(res.status).toBe(500);
    expect(res.body.items).toEqual([]);
  });
});

describe('POST /tasks/:id/suggest', () => {
  test('parses suggestions out of the LLM JSON response', async () => {
    callGemma4.mockResolvedValue('בטח! {"suggestions":[{"text":"שלב א","reason":"להתחיל"}]} בהצלחה');
    const supabase = {
      from: jest.fn()
        .mockImplementationOnce(() => makeChain({ content: 'משימה', priority: 'high' })) // single task
        .mockImplementationOnce(() => makeChain([{ content: 'אחרת' }])),                 // other tasks
    };
    const res = await request(mountApp(supabase)).post('/tasks/5/suggest').send({});
    expect(res.status).toBe(200);
    expect(res.body.suggestions).toEqual([{ text: 'שלב א', reason: 'להתחיל' }]);
  });

  test('404 when the task does not exist', async () => {
    const supabase = {
      from: jest.fn()
        .mockImplementationOnce(() => makeChain(null))
        .mockImplementationOnce(() => makeChain([])),
    };
    const res = await request(mountApp(supabase)).post('/tasks/99/suggest').send({});
    expect(res.status).toBe(404);
  });

  test('returns empty suggestions when the LLM output is unparseable', async () => {
    callGemma4.mockResolvedValue('no json here');
    const supabase = {
      from: jest.fn()
        .mockImplementationOnce(() => makeChain({ content: 'משימה' }))
        .mockImplementationOnce(() => makeChain([])),
    };
    const res = await request(mountApp(supabase)).post('/tasks/5/suggest').send({});
    expect(res.status).toBe(200);
    expect(res.body.suggestions).toEqual([]);
  });
});

describe('subtasks endpoints', () => {
  test('POST /tasks/:id/subtasks rejects missing content', async () => {
    const supabase = { from: jest.fn(() => makeChain()) };
    const res = await request(mountApp(supabase)).post('/tasks/1/subtasks').send({});
    expect(res.status).toBe(400);
  });

  test('POST /tasks/:id/subtasks creates a subtask under the parent', async () => {
    const chain = makeChain({ id: 50, parent_task_id: '1', content: 'תת-משימה' });
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).post('/tasks/1/subtasks').send({ content: 'תת-משימה' });
    expect(res.status).toBe(200);
    expect(chain.insert).toHaveBeenCalledWith([{ parent_task_id: '1', content: 'תת-משימה' }]);
    expect(res.body.subtask.id).toBe(50);
  });

  test('GET /tasks/:id/subtasks lists by parent', async () => {
    const chain = makeChain([{ id: 50, content: 'a' }]);
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).get('/tasks/1/subtasks');
    expect(res.status).toBe(200);
    expect(chain.eq).toHaveBeenCalledWith('parent_task_id', '1');
    expect(res.body.subtasks).toHaveLength(1);
  });

  test('DELETE /tasks/:id/subtasks/:subId scopes the delete to the parent', async () => {
    const chain = makeChain([]);
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).delete('/tasks/1/subtasks/50');
    expect(res.status).toBe(200);
    expect(chain.eq).toHaveBeenCalledWith('id', '50');
    expect(chain.eq).toHaveBeenCalledWith('parent_task_id', '1');
  });
});

describe('controller routes wired through the router', () => {
  test('GET /tasks returns the { tasks: [] } wrapper', async () => {
    const supabase = { from: jest.fn(() => makeChain([{ id: 1, content: 'x' }])) };
    const res = await request(mountApp(supabase)).get('/tasks');
    expect(res.status).toBe(200);
    expect(res.body.tasks).toHaveLength(1);
  });

  test('POST /tasks validates content', async () => {
    const supabase = { from: jest.fn(() => makeChain({})) };
    const res = await request(mountApp(supabase)).post('/tasks').send({});
    expect(res.status).toBe(400);
  });
});
