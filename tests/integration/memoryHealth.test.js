// tests/integration/memoryHealth.test.js
'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
  isReady: jest.fn().mockReturnValue(true),
  searchMemoriesDetailed: jest.fn(),
  listAll: jest.fn().mockResolvedValue([]),
  upsertMemory: jest.fn().mockResolvedValue(true),
  deleteMemory: jest.fn().mockResolvedValue(),
  searchMemories: jest.fn().mockResolvedValue(null),
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn(), removeFromVault: jest.fn() }));
jest.mock('../../services/memoryContext', () => ({ invalidateCache: jest.fn(), savePendingData: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ getPendingMemory: jest.fn(), clearPendingMemory: jest.fn() }));

const express = require('express');
const request = require('supertest');
const pinecone = require('../../services/pineconeMemory');
const { callGemma4 } = require('../../agents/models');
const { createMemoriesRouter } = require('../../routes/memories');
const { makeRepos } = require('../helpers/fakeRepos');

function mountApp(repos) {
  const app = express();
  app.use(express.json());
  app.use('/memories', createMemoriesRouter({ repos }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('memory health check — scan then resolve a merge', () => {
  test('a scan-detected duplicate can be merged via the resolve endpoint', async () => {
    const memA = { id: 1, content: 'אוהב קפה שחור בבוקר', scope: 'long_term', status: 'approved', category: 'כללי', created_at: new Date().toISOString() };
    const memB = { id: 2, content: 'שותה קפה שחור כל בוקר', scope: 'long_term', status: 'approved', category: 'כללי', created_at: new Date().toISOString() };
    const repos = makeRepos({ memories: [memA, memB] });
    repos.memories.create = jest.fn(async () => [{ id: 9, content: 'אוהב לשתות קפה שחור כל בוקר' }]);
    repos.memories.updateById = jest.fn(async (id) => [{ id, scope: 'archive' }]);

    pinecone.searchMemoriesDetailed.mockImplementation(async (query) => {
      if (query === memA.content) return [{ id: '1', content: memA.content, score: 1 }, { id: '2', content: memB.content, score: 0.95 }];
      return [{ id: '2', content: memB.content, score: 1 }, { id: '1', content: memA.content, score: 0.95 }];
    });
    callGemma4.mockImplementation(async (messages) => {
      const text = Array.isArray(messages) ? messages[0].content : messages;
      if (text.includes('מזג')) return '{"merged":"אוהב לשתות קפה שחור כל בוקר"}';
      return '{"category":"כללי"}';
    });

    const app = mountApp(repos);

    const runRes = await request(app).post('/memories/health/run');
    expect(runRes.status).toBe(200);
    expect(runRes.body.created).toBeGreaterThanOrEqual(1);
    expect(repos.memoryHealth.insertFinding).toHaveBeenCalled();

    const [findingRow] = repos.memoryHealth.insertFinding.mock.calls[0];
    expect(findingRow.type).toBe('duplicate');
    const findingId = 'f-test-1';
    repos.memoryHealth.getById = jest.fn(async () => ({
      id: findingId, type: 'duplicate', status: 'pending',
      memory_id: findingRow.memory_id, related_memory_id: findingRow.related_memory_id,
      suggested_payload: findingRow.suggested_payload,
    }));

    const resolveRes = await request(app)
      .post(`/memories/health/findings/${findingId}/resolve`)
      .send({ action: 'merge' });

    expect(resolveRes.status).toBe(200);
    expect(repos.memories.create).toHaveBeenCalledWith(
      expect.objectContaining({ content: 'אוהב לשתות קפה שחור כל בוקר', scope: 'long_term' }));
    expect(repos.memories.updateById).toHaveBeenCalledWith(findingRow.memory_id, { scope: 'archive' });
    expect(repos.memories.updateById).toHaveBeenCalledWith(findingRow.related_memory_id, { scope: 'archive' });
  });

  test('a dismissed finding does not resurface on the next identical scan', async () => {
    const mem = { id: 1, content: 'אוהב פיצה', scope: 'long_term', status: 'approved', category: 'כללי', created_at: new Date().toISOString() };
    const repos = makeRepos({ memories: [mem] });
    pinecone.searchMemoriesDetailed.mockResolvedValue([]);
    callGemma4.mockResolvedValue('{"category":"כללי"}');

    const app = mountApp(repos);
    await request(app).post('/memories/health/run'); // first scan creates the thin_content finding

    const [firstFinding] = repos.memoryHealth.insertFinding.mock.calls
      .map(([r]) => r).filter(r => r.type === 'thin_content');
    expect(firstFinding).toBeTruthy();

    // Simulate it now existing with status 'rejected' and an unchanged content hash
    repos.memoryHealth.findExisting = jest.fn(async () => ({
      id: 'existing-1', status: 'rejected', content_hash: firstFinding.content_hash,
    }));
    repos.memoryHealth.insertFinding.mockClear();

    await request(app).post('/memories/health/run'); // second scan, same content

    const reCreated = repos.memoryHealth.insertFinding.mock.calls
      .map(([r]) => r).find(r => r.type === 'thin_content');
    expect(reCreated).toBeUndefined();
    expect(repos.memoryHealth.updateFinding).not.toHaveBeenCalled();
  });
});
