'use strict';

const express = require('express');
const request = require('supertest');
const { createNotesRouter } = require('../../routes/notes');
const { makeChain } = require('../helpers/supabaseMock');

function mountApp(supabase) {
  const app = express();
  app.use(express.json());
  app.use('/notes', createNotesRouter({ supabase }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /notes', () => {
  test('returns the { notes: [] } wrapper', async () => {
    const supabase = { from: jest.fn(() => makeChain([{ id: 1, title: 'a', content: 'b' }])) };
    const res = await request(mountApp(supabase)).get('/notes');
    expect(res.status).toBe(200);
    expect(res.body.notes).toHaveLength(1);
  });

  test('500 with empty notes on db failure', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const res = await request(mountApp(supabase)).get('/notes');
    expect(res.status).toBe(500);
    expect(res.body.notes).toEqual([]);
  });
});

describe('POST /notes', () => {
  test('rejects missing content', async () => {
    const supabase = { from: jest.fn(() => makeChain()) };
    const res = await request(mountApp(supabase)).post('/notes').send({});
    expect(res.status).toBe(400);
  });

  test('creates a note, defaulting an absent title to empty string', async () => {
    const chain = makeChain({ id: 5, title: '', content: 'תוכן' });
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).post('/notes').send({ content: 'תוכן' });
    expect(res.status).toBe(200);
    expect(chain.insert).toHaveBeenCalledWith([{ title: '', content: 'תוכן' }]);
    expect(res.body.note.id).toBe(5);
  });
});

describe('PUT /notes/:id', () => {
  test('rejects an empty update', async () => {
    const supabase = { from: jest.fn(() => makeChain()) };
    const res = await request(mountApp(supabase)).put('/notes/1').send({});
    expect(res.status).toBe(400);
  });

  test('updates only the provided fields', async () => {
    const chain = makeChain({ id: 1, title: 'חדש' });
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).put('/notes/1').send({ title: 'חדש' });
    expect(res.status).toBe(200);
    expect(chain.update).toHaveBeenCalledWith({ title: 'חדש' });
    expect(chain.eq).toHaveBeenCalledWith('id', '1');
  });

  test('500 when the update fails', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const res = await request(mountApp(supabase)).put('/notes/1').send({ content: 'x' });
    expect(res.status).toBe(500);
  });
});

describe('DELETE /notes/:id', () => {
  test('deletes by id', async () => {
    const chain = makeChain(null, null);
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).delete('/notes/1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(chain.eq).toHaveBeenCalledWith('id', '1');
  });

  test('500 when the delete fails', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const res = await request(mountApp(supabase)).delete('/notes/1');
    expect(res.status).toBe(500);
    expect(res.body.ok).toBe(false);
  });
});
