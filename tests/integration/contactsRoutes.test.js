'use strict';

const express = require('express');
const request = require('supertest');
const { createContactsRouter } = require('../../routes/contacts');
const { makeChain } = require('../helpers/supabaseMock');

// No requirePolicy injected — the router falls back to a pass-through
// middleware (see routes/contacts.js), same convention as memoriesRoutes.test.js.
// Policy behavior itself is exercised by the server.js-level policy tests.
function mountApp(supabase) {
  const app = express();
  app.use(express.json());
  app.use('/contacts', createContactsRouter({ supabase }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /contacts', () => {
  test('returns the { contacts: [] } wrapper', async () => {
    const supabase = { from: jest.fn(() => makeChain([{ id: 1, name: 'דנה' }])) };
    const res = await request(mountApp(supabase)).get('/contacts');
    expect(res.status).toBe(200);
    expect(res.body.contacts).toHaveLength(1);
  });

  test('500 with empty contacts on db failure', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const res = await request(mountApp(supabase)).get('/contacts');
    expect(res.status).toBe(500);
    expect(res.body.contacts).toEqual([]);
  });
});

describe('POST /contacts', () => {
  test('rejects a missing name', async () => {
    const supabase = { from: jest.fn(() => makeChain()) };
    const res = await request(mountApp(supabase)).post('/contacts').send({});
    expect(res.status).toBe(400);
  });

  test('creates a contact, including optional phone/email only when present', async () => {
    const chain = makeChain({ id: 2, name: 'דנה', phone: '050', email: undefined });
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).post('/contacts').send({ name: 'דנה', phone: '050' });
    expect(res.status).toBe(200);
    expect(chain.insert).toHaveBeenCalledWith([{ name: 'דנה', phone: '050' }]);
    expect(res.body.contact.id).toBe(2);
  });
});

describe('PUT /contacts/:id', () => {
  test('rejects an empty update', async () => {
    const supabase = { from: jest.fn(() => makeChain()) };
    const res = await request(mountApp(supabase)).put('/contacts/1').send({});
    expect(res.status).toBe(400);
  });

  test('updates only the provided fields', async () => {
    const chain = makeChain({ id: 1, phone: '052' });
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).put('/contacts/1').send({ phone: '052' });
    expect(res.status).toBe(200);
    expect(chain.update).toHaveBeenCalledWith({ phone: '052' });
    expect(chain.eq).toHaveBeenCalledWith('id', '1');
  });
});

describe('DELETE /contacts/:id', () => {
  test('deletes by id', async () => {
    const chain = makeChain(null, null);
    const supabase = { from: jest.fn(() => chain) };
    const res = await request(mountApp(supabase)).delete('/contacts/1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(chain.eq).toHaveBeenCalledWith('id', '1');
  });

  test('500 when the delete fails', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const res = await request(mountApp(supabase)).delete('/contacts/1');
    expect(res.status).toBe(500);
    expect(res.body.ok).toBe(false);
  });
});
