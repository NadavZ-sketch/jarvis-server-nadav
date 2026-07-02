'use strict';

const express = require('express');
const request = require('supertest');
const { createShoppingRouter } = require('../../routes/shopping');
const { makeChain } = require('../helpers/supabaseMock');

function mountApp(supabase) {
  const app = express();
  app.use(express.json());
  app.use('/shopping', createShoppingRouter({ supabase }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /shopping', () => {
  test('returns the { items: [] } wrapper', async () => {
    const supabase = { from: jest.fn(() => makeChain([{ id: 1, item: 'חלב' }])) };
    const res = await request(mountApp(supabase)).get('/shopping');
    expect(res.status).toBe(200);
    expect(res.body.items).toHaveLength(1);
  });

  test('500 with empty items on db failure', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const res = await request(mountApp(supabase)).get('/shopping');
    expect(res.status).toBe(500);
    expect(res.body.items).toEqual([]);
  });
});

describe('POST /shopping', () => {
  test('rejects a missing item', async () => {
    const supabase = { from: jest.fn(() => makeChain()) };
    const res = await request(mountApp(supabase)).post('/shopping').send({});
    expect(res.status).toBe(400);
  });

  test('creates an item', async () => {
    const chain = makeChain({ id: 3, item: 'לחם', done: false });
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).post('/shopping').send({ item: 'לחם' });
    expect(res.status).toBe(200);
    expect(chain.insert).toHaveBeenCalledWith([{ item: 'לחם' }]);
    expect(res.body.item.id).toBe(3);
  });
});

describe('PATCH /shopping/:id', () => {
  test('rejects an empty update', async () => {
    const supabase = { from: jest.fn(() => makeChain()) };
    const res = await request(mountApp(supabase)).patch('/shopping/1').send({});
    expect(res.status).toBe(400);
  });

  test('toggles done', async () => {
    const chain = makeChain({ id: 1, done: true });
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).patch('/shopping/1').send({ done: true });
    expect(res.status).toBe(200);
    expect(chain.update).toHaveBeenCalledWith({ done: true });
    expect(chain.eq).toHaveBeenCalledWith('id', '1');
  });
});

describe('DELETE /shopping/:id', () => {
  test('deletes by id', async () => {
    const chain = makeChain(null, null);
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).delete('/shopping/1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(chain.eq).toHaveBeenCalledWith('id', '1');
  });

  test('500 when the delete fails', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const res = await request(mountApp(supabase)).delete('/shopping/1');
    expect(res.status).toBe(500);
    expect(res.body.ok).toBe(false);
  });
});
