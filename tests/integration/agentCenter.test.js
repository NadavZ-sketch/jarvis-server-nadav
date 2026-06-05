'use strict';

jest.mock('../../services/agentRegistryService', () => ({
  getAgentRegistry: jest.fn(),
  setAgentStatus: jest.fn(),
  setAgentRisk: jest.fn(),
  isProtectedAgent: jest.fn().mockReturnValue(false),
}));

const express = require('express');
const request = require('supertest');
const registry = require('../../services/agentRegistryService');
const { createAgentCenterRouter } = require('../../routes/agentCenter');

function mountApp({ callGemma4 = jest.fn(), agentMetrics = null } = {}) {
  const app = express();
  app.use(express.json());
  app.use('/agent-center', createAgentCenterRouter({ callGemma4, agentMetrics }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /agent-center/agents', () => {
  test('attaches live metrics and a health score per agent', async () => {
    registry.getAgentRegistry.mockResolvedValue([
      { id: 'task', nameHe: 'משימות', status: 'active', risk: 'low', mode: 'sync' },
      { id: 'slow', nameHe: 'איטי', status: 'active', risk: 'high', mode: 'sync' },
      { id: 'off', nameHe: 'כבוי', status: 'disabled', risk: 'low', mode: 'sync' },
    ]);
    const agentMetrics = {
      snapshot: jest.fn().mockResolvedValue({
        latency: [
          { agent: 'task', avgMs: 200, count: 5, lastCalledAt: new Date().toISOString() },
          { agent: 'slow', avgMs: 4000, count: 3, lastCalledAt: new Date().toISOString() },
        ],
        intent: { fast: 10, llm: 2 },
      }),
    };

    const res = await request(mountApp({ agentMetrics })).get('/agent-center/agents');

    expect(res.status).toBe(200);
    const byId = Object.fromEntries(res.body.agents.map(a => [a.id, a]));
    expect(byId.task.healthScore).toBe(100);          // fast + recent
    expect(byId.slow.healthScore).toBeLessThan(100);  // slow (>3s) + high risk
    expect(byId.off.healthScore).toBe(0);             // disabled
    expect(byId.task.metrics.count).toBe(5);
  });

  test('500 when the registry throws', async () => {
    registry.getAgentRegistry.mockRejectedValue(new Error('registry down'));
    const res = await request(mountApp()).get('/agent-center/agents');
    expect(res.status).toBe(500);
  });
});

describe('POST /agent-center/agents/:id/toggle', () => {
  test('404 for an unknown agent', async () => {
    registry.getAgentRegistry.mockResolvedValue([{ id: 'task', status: 'active' }]);
    const res = await request(mountApp()).post('/agent-center/agents/ghost/toggle').send({});
    expect(res.status).toBe(404);
  });

  test('flips an active agent to disabled when no explicit status given', async () => {
    registry.getAgentRegistry.mockResolvedValue([{ id: 'task', status: 'active' }]);
    registry.setAgentStatus.mockResolvedValue({ updatedAt: '2026-06-05T00:00:00Z' });
    const res = await request(mountApp()).post('/agent-center/agents/task/toggle').send({});
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('disabled');
    expect(registry.setAgentStatus).toHaveBeenCalledWith('task', 'disabled');
  });
});

describe('POST /agent-center/agents/:id/risk', () => {
  test('persists a new risk level', async () => {
    registry.getAgentRegistry.mockResolvedValue([{ id: 'task' }]);
    registry.setAgentRisk.mockResolvedValue({ updatedAt: '2026-06-05T00:00:00Z' });
    const res = await request(mountApp()).post('/agent-center/agents/task/risk').send({ riskLevel: 'high' });
    expect(res.status).toBe(200);
    expect(registry.setAgentRisk).toHaveBeenCalledWith('task', 'high');
  });
});

describe('POST /agent-center/analyze', () => {
  test('detects the safety category and a destructive-action risk signal', async () => {
    registry.getAgentRegistry.mockResolvedValue([{ id: 'task', nameHe: 'משימות', risk: 'low', mode: 'sync', autonomy: 50 }]);
    const callGemma4 = jest.fn().mockResolvedValue('[{"label":"q","reason":"r","options":[]}]');
    const res = await request(mountApp({ callGemma4 }))
      .post('/agent-center/analyze')
      .send({ agentId: 'task', changeRequest: 'אפשר לסוכן מחיקה של קבצים ללא אישור' });
    expect(res.status).toBe(200);
    expect(res.body.category).toBe('safety');
    const keys = res.body.riskSignals.map(s => s.key);
    expect(keys).toEqual(expect.arrayContaining(['autonomy_increase', 'destructive_action']));
    expect(res.body.confidence).toBeLessThan(0.75); // lowered by risk signals
  });

  test('400 when changeRequest is missing', async () => {
    const res = await request(mountApp()).post('/agent-center/analyze').send({});
    expect(res.status).toBe(400);
  });

  test('survives an unparseable LLM response with a default missingContext', async () => {
    registry.getAgentRegistry.mockResolvedValue([]);
    const callGemma4 = jest.fn().mockResolvedValue('not json');
    const res = await request(mountApp({ callGemma4 }))
      .post('/agent-center/analyze')
      .send({ changeRequest: 'שנה את הפרומפט' });
    expect(res.status).toBe(200);
    expect(res.body.category).toBe('prompt');
    expect(res.body.questions).toEqual([]);
    expect(res.body.missingContext.length).toBeGreaterThan(0);
  });
});

describe('POST /agent-center/build-prompt', () => {
  test('falls back to a templated prompt when the LLM returns nothing usable', async () => {
    registry.getAgentRegistry.mockResolvedValue([{ id: 'task', nameHe: 'משימות', risk: 'low' }]);
    const callGemma4 = jest.fn().mockResolvedValue('garbage');
    const res = await request(mountApp({ callGemma4 }))
      .post('/agent-center/build-prompt')
      .send({ agentId: 'task', changeRequest: 'הוסף יכולת חדשה' });
    expect(res.status).toBe(200);
    expect(res.body.prompt).toContain('agents/task.js');
    expect(res.body.reviewText.length).toBeGreaterThan(0);
  });

  test('400 when changeRequest is missing', async () => {
    const res = await request(mountApp()).post('/agent-center/build-prompt').send({});
    expect(res.status).toBe(400);
  });
});

describe('POST /agent-center/metrics/query', () => {
  test('400 when question is missing', async () => {
    const res = await request(mountApp()).post('/agent-center/metrics/query').send({});
    expect(res.status).toBe(400);
  });
});
