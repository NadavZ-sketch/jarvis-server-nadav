'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
  isReady: jest.fn().mockReturnValue(false),
  searchMemories: jest.fn(),
  upsertMemory: jest.fn().mockResolvedValue(true),
  deleteMemory: jest.fn().mockResolvedValue(),
  listAll: jest.fn().mockResolvedValue([]),
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn(), removeFromVault: jest.fn() }));
jest.mock('../../services/memoryContext', () => ({ invalidateCache: jest.fn(), savePendingData: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ getPendingMemory: jest.fn(), clearPendingMemory: jest.fn() }));
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn().mockResolvedValue('כללי') }));
jest.mock('../../services/memoryHealthCheck', () => ({ runHealthScan: jest.fn() }));
jest.mock('../../services/memoryHealthActions', () => ({ resolveFinding: jest.fn() }));

const express = require('express');
const request = require('supertest');
const pinecone = require('../../services/pineconeMemory');
const memoryContext = require('../../services/memoryContext');
const memoryAgent = require('../../agents/memoryAgent');
const memoryHealthCheck = require('../../services/memoryHealthCheck');
const memoryHealthActions = require('../../services/memoryHealthActions');
const { createMemoriesRouter } = require('../../routes/memories');
const { makeRepos } = require('../helpers/fakeRepos');

function mountApp(repos) {
  const app = express();
  app.use(express.json());
  app.use('/memories', createMemoriesRouter({ repos }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /memories', () => {
  test('uses Pinecone search when q is present and Pinecone is ready', async () => {
    pinecone.isReady.mockReturnValue(true);
    pinecone.searchMemories.mockResolvedValue(['hit one', 'hit two']);
    const res = await request(mountApp(makeRepos())).get('/memories?q=test');
    expect(res.status).toBe(200);
    expect(res.body.memories).toEqual([{ content: 'hit one' }, { content: 'hit two' }]);
  });

  test('falls back to repo listing when no query', async () => {
    const repos = makeRepos({ memories: [{ id: 1, content: 'a fact' }] });
    const res = await request(mountApp(repos)).get('/memories');
    expect(res.status).toBe(200);
    expect(res.body.memories).toEqual([{ id: 1, content: 'a fact' }]);
  });
});

describe('POST /memories', () => {
  test('rejects empty content', async () => {
    const res = await request(mountApp(makeRepos())).post('/memories').send({ content: '   ' });
    expect(res.status).toBe(400);
  });

  test('creates a memory and upserts to Pinecone', async () => {
    const repos = makeRepos({ memories: [{ id: 5, content: 'new fact' }] });
    const res = await request(mountApp(repos)).post('/memories').send({ content: 'new fact' });
    expect(res.status).toBe(200);
    expect(res.body.memory).toEqual({ id: 5, content: 'new fact' });
    expect(pinecone.upsertMemory).toHaveBeenCalledWith(5, 'new fact');
    expect(memoryContext.invalidateCache).toHaveBeenCalled();
  });

  test('classifies and persists a category on the created memory', async () => {
    const repos = makeRepos({ memories: [{ id: 5, content: 'new fact' }] });
    const res = await request(mountApp(repos)).post('/memories').send({ content: 'new fact' });
    expect(res.status).toBe(200);
    expect(repos.memories.create).toHaveBeenCalledWith(
      expect.objectContaining({ content: 'new fact', category: 'כללי' }));
  });
});

describe('GET /memories/pending', () => {
  test('lists pending memories', async () => {
    const repos = makeRepos();
    repos.memories.listByStatus = jest.fn(async () => [{ id: 1, status: 'pending' }]);
    const res = await request(mountApp(repos)).get('/memories/pending');
    expect(res.status).toBe(200);
    expect(res.body.memories).toEqual([{ id: 1, status: 'pending' }]);
  });
});

describe('POST /memories/:id/approve', () => {
  test('404s when memory not found', async () => {
    const repos = makeRepos();
    repos.memories.setStatus = jest.fn(async () => null);
    const res = await request(mountApp(repos)).post('/memories/999/approve');
    expect(res.status).toBe(404);
  });
});

describe('PUT/DELETE /memories/:id', () => {
  test('PUT rejects empty content', async () => {
    const res = await request(mountApp(makeRepos())).put('/memories/1').send({ content: '' });
    expect(res.status).toBe(400);
  });

  test('PUT classifies and persists a category on the updated memory', async () => {
    const repos = makeRepos();
    repos.memories.updateById = jest.fn(async () => [{ id: 1, content: 'updated', category: 'כללי' }]);
    const res = await request(mountApp(repos)).put('/memories/1').send({ content: 'updated' });
    expect(res.status).toBe(200);
    expect(repos.memories.updateById).toHaveBeenCalledWith('1',
      expect.objectContaining({ content: 'updated', category: 'כללי' }));
  });

  test('DELETE 404s when nothing removed', async () => {
    const repos = makeRepos();
    repos.memories.removeById = jest.fn(async () => []);
    const res = await request(mountApp(repos)).delete('/memories/1');
    expect(res.status).toBe(404);
  });
});

describe('POST /memories/confirm', () => {
  test('400 when chatId missing', async () => {
    const res = await request(mountApp(makeRepos())).post('/memories/confirm').send({});
    expect(res.status).toBe(400);
  });

  test('404 when no pending memory for chat', async () => {
    memoryAgent.getPendingMemory.mockReturnValue(null);
    const res = await request(mountApp(makeRepos())).post('/memories/confirm').send({ chatId: 'c1' });
    expect(res.status).toBe(404);
  });

  test('discard clears pending without saving', async () => {
    memoryAgent.getPendingMemory.mockReturnValue({ content: '[fact] x' });
    const res = await request(mountApp(makeRepos())).post('/memories/confirm').send({ chatId: 'c1', action: 'discard' });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(memoryAgent.clearPendingMemory).toHaveBeenCalledWith('c1');
    expect(memoryContext.savePendingData).not.toHaveBeenCalled();
  });

  test('save persists the pending memory', async () => {
    memoryAgent.getPendingMemory.mockReturnValue({ content: '[fact] x' });
    memoryContext.savePendingData.mockResolvedValue({ content: '[fact] x' });
    const repos = makeRepos();
    const res = await request(mountApp(repos)).post('/memories/confirm').send({ chatId: 'c1', action: 'save' });
    expect(res.status).toBe(200);
    expect(res.body.saved).toBe('[fact] x');
  });
});

describe('GET /memories/health/findings', () => {
  test('lists pending findings by default', async () => {
    const repos = makeRepos();
    repos.memoryHealth.listFindings = jest.fn(async () => [{ id: 'f1', type: 'duplicate', status: 'pending' }]);
    const res = await request(mountApp(repos)).get('/memories/health/findings');
    expect(res.status).toBe(200);
    expect(res.body.findings).toEqual([{ id: 'f1', type: 'duplicate', status: 'pending' }]);
  });
});

describe('POST /memories/health/run', () => {
  test('runs the scan and returns the summary', async () => {
    memoryHealthCheck.runHealthScan.mockResolvedValue({ created: 2, updated: 1, autoResolved: 0, errors: [] });
    const res = await request(mountApp(makeRepos())).post('/memories/health/run');
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ ok: true, created: 2, updated: 1 });
  });
});

describe('POST /memories/health/findings/:id/resolve', () => {
  test('404s when the finding is missing or already resolved', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => null);
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/resolve').send({ action: 'delete' });
    expect(res.status).toBe(404);
  });

  test('applies the action and marks the finding approved', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => ({ id: 'f1', type: 'thin_content', status: 'pending', memory_id: '1' }));
    repos.memoryHealth.setStatus = jest.fn(async (id, status) => ({ id, status }));
    memoryHealthActions.resolveFinding.mockResolvedValue({ id: 1 });
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/resolve').send({ action: 'delete' });
    expect(res.status).toBe(200);
    expect(memoryHealthActions.resolveFinding).toHaveBeenCalled();
    expect(repos.memoryHealth.setStatus).toHaveBeenCalledWith('f1', 'approved');
  });

  test('propagates a 400 from an invalid action', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => ({ id: 'f1', type: 'thin_content', status: 'pending', memory_id: '1' }));
    const err = new Error('Invalid action "merge" for finding type "thin_content"');
    err.status = 400;
    memoryHealthActions.resolveFinding.mockRejectedValue(err);
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/resolve').send({ action: 'merge' });
    expect(res.status).toBe(400);
  });
});

describe('POST /memories/health/findings/:id/dismiss', () => {
  test('marks the finding rejected', async () => {
    const repos = makeRepos();
    repos.memoryHealth.getById = jest.fn(async () => ({ id: 'f1', status: 'pending' }));
    repos.memoryHealth.setStatus = jest.fn(async (id, status) => ({ id, status }));
    const res = await request(mountApp(repos)).post('/memories/health/findings/f1/dismiss');
    expect(res.status).toBe(200);
    expect(repos.memoryHealth.setStatus).toHaveBeenCalledWith('f1', 'rejected');
  });
});
