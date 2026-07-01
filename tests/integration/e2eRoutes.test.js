'use strict';

jest.mock('../../agents/e2eAgent', () => ({
  runE2EAgent: jest.fn(),
  buildClaudePrompt: jest.fn(() => 'prompt'),
  countsBySeverity: jest.fn(() => ({ critical: 0, high: 0, medium: 0, low: 0 })),
  computeScore: jest.fn(() => 100),
}));

const express = require('express');
const request = require('supertest');
const { runE2EAgent } = require('../../agents/e2eAgent');
const { createE2ERouter } = require('../../routes/e2e');
const { makeRepos } = require('../helpers/fakeRepos');

function mountApp(repos, cacheInvalidate = jest.fn()) {
  const app = express();
  app.use(express.json());
  app.use('/', createE2ERouter({ repos, supabase: {}, cacheInvalidate }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET/PUT /e2e-schedule', () => {
  test('GET returns null when no profile row exists', async () => {
    const res = await request(mountApp(makeRepos())).get('/e2e-schedule');
    expect(res.status).toBe(200);
    expect(res.body.schedule).toBeNull();
  });

  test('PUT rejects a non-object schedule', async () => {
    const res = await request(mountApp(makeRepos())).put('/e2e-schedule').send({ schedule: 'nope' });
    expect(res.status).toBe(400);
  });

  test('PUT creates a profile row when none exists', async () => {
    const repos = makeRepos();
    const res = await request(mountApp(repos)).put('/e2e-schedule').send({ schedule: { cron: '0 3 * * *' } });
    expect(res.status).toBe(200);
    expect(repos.profile.create).toHaveBeenCalledWith({ preferences: { 'e2e-schedule': { cron: '0 3 * * *' } } });
  });
});

describe('GET /e2e-reports', () => {
  test('groups findings by run_id and scores each run', async () => {
    const repos = makeRepos();
    repos.e2e.listRecent = jest.fn(async () => [
      { run_id: 'r1', kind: 'e2e', created_at: '2026-01-01', severity: 'critical', status: 'open' },
      { run_id: 'r1', kind: 'e2e', created_at: '2026-01-02', severity: 'low', status: 'open' },
    ]);
    const res = await request(mountApp(repos)).get('/e2e-reports');
    expect(res.status).toBe(200);
    expect(res.body.reports).toHaveLength(1);
    expect(res.body.reports[0]).toMatchObject({ run_id: 'r1', critical: 1, low: 1 });
  });
});

describe('DELETE /e2e-reports/:runId', () => {
  test('invalidates the chat history cache on success', async () => {
    const repos = makeRepos();
    const cacheInvalidate = jest.fn();
    const res = await request(mountApp(repos, cacheInvalidate)).delete('/e2e-reports/r1');
    expect(res.status).toBe(200);
    expect(cacheInvalidate).toHaveBeenCalledWith('chatHistory');
  });
});

describe('POST /e2e-reports/:runId/prompt and /mark-done', () => {
  test('prompt requires a fingerprints array', async () => {
    const res = await request(mountApp(makeRepos())).post('/e2e-reports/r1/prompt').send({});
    expect(res.status).toBe(400);
  });

  test('mark-done requires a fingerprints array', async () => {
    const res = await request(mountApp(makeRepos())).post('/e2e-reports/r1/mark-done').send({});
    expect(res.status).toBe(400);
  });

  test('mark-done updates the given fingerprints', async () => {
    const repos = makeRepos();
    repos.e2e.markDone = jest.fn(async () => ({ error: null }));
    const res = await request(mountApp(repos)).post('/e2e-reports/r1/mark-done').send({ fingerprints: ['a', 'b'] });
    expect(res.status).toBe(200);
    expect(res.body.updated).toBe(2);
  });
});

describe('POST /e2e/trigger', () => {
  test('responds immediately and fires the agent in the background', async () => {
    const res = await request(mountApp(makeRepos())).post('/e2e/trigger');
    expect(res.status).toBe(200);
    expect(res.body.triggered).toBe(true);
    await new Promise(r => setImmediate(r));
    expect(runE2EAgent).toHaveBeenCalled();
  });
});
