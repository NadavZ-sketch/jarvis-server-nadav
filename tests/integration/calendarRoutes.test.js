'use strict';

jest.mock('../../agents/calendarAgent', () => ({ buildAuthUrl: jest.fn(() => 'https://accounts.google.com/mock') }));

const express = require('express');
const request = require('supertest');
const { createCalendarRouter } = require('../../routes/calendar');
const { makeRepos } = require('../helpers/fakeRepos');

function mountApp(repos, cacheInvalidate = jest.fn()) {
  const app = express();
  app.use(express.json());
  app.use('/', createCalendarRouter({ repos, supabase: {}, cacheInvalidate }));
  return app;
}

const ORIGINAL_ENV = process.env;
beforeEach(() => {
  jest.clearAllMocks();
  process.env = { ...ORIGINAL_ENV, GOOGLE_CLIENT_ID: 'id', GOOGLE_CLIENT_SECRET: 'secret' };
});
afterAll(() => { process.env = ORIGINAL_ENV; });

describe('GET /auth/google/start', () => {
  test('400s when Google OAuth env vars are missing', async () => {
    delete process.env.GOOGLE_CLIENT_ID;
    const res = await request(mountApp(makeRepos())).get('/auth/google/start');
    expect(res.status).toBe(400);
  });

  test('redirects to the Google auth URL when configured', async () => {
    const res = await request(mountApp(makeRepos())).get('/auth/google/start');
    expect(res.status).toBe(302);
    expect(res.headers.location).toBe('https://accounts.google.com/mock');
  });
});

describe('GET /auth/google/callback', () => {
  test('rejects an unknown/expired state nonce', async () => {
    const res = await request(mountApp(makeRepos())).get('/auth/google/callback?code=abc&state=unknown');
    expect(res.status).toBe(400);
  });

  test('400s when no code is provided', async () => {
    const res = await request(mountApp(makeRepos())).get('/auth/google/callback');
    expect(res.status).toBe(400);
  });
});

describe('GET /calendar-events', () => {
  test('merges dated tasks and reminders into a single events list', async () => {
    const repos = makeRepos();
    repos.tasks.datedAll = jest.fn(async () => [{ id: 1, content: 'task a', due_date: '2026-08-01T00:00:00Z', done: false }]);
    repos.reminders.allOrdered = jest.fn(async () => [{ id: 2, text: 'reminder a', scheduled_time: '2026-08-02T00:00:00Z', fired: false }]);
    const res = await request(mountApp(repos)).get('/calendar-events');
    expect(res.status).toBe(200);
    expect(res.body.events).toEqual([
      { id: 'task-1', type: 'task', title: 'task a', date: '2026-08-01T00:00:00.000Z', done: false },
      { id: 'reminder-2', type: 'reminder', title: 'reminder a', date: '2026-08-02T00:00:00.000Z', done: false },
    ]);
  });
});

describe('GET /upcoming-items', () => {
  test('merges and sorts upcoming tasks/reminders by date', async () => {
    const repos = makeRepos();
    repos.tasks.upcomingDated = jest.fn(async () => [{ content: 'later task', due_date: '2026-08-02T00:00:00Z' }]);
    repos.reminders.upcomingUnfired = jest.fn(async () => [{ text: 'sooner reminder', scheduled_time: '2026-08-01T00:00:00Z' }]);
    const res = await request(mountApp(repos)).get('/upcoming-items');
    expect(res.status).toBe(200);
    expect(res.body.upcoming.map(i => i.title)).toEqual(['sooner reminder', 'later task']);
  });
});
