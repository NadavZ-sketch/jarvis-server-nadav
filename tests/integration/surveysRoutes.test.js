'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../agents/surveyAgent', () => {
  const actual = jest.requireActual('../../agents/surveyAgent');
  return { ...actual, generateSmartSurvey: jest.fn(async () => ({ q1: { question: 'How are we doing?' } })) };
});
jest.mock('../../services/agentMetrics', () => ({
  snapshot: jest.fn(async () => ({ latency: [], intent: { fast: 0, llm: 0 } })),
}));

const express = require('express');
const request = require('supertest');
const { createSurveysRouter } = require('../../routes/surveys');
const { makeRepos } = require('../helpers/fakeRepos');

function mountApp(repos) {
  const app = express();
  app.use(express.json());
  app.use('/', createSurveysRouter({ repos, supabase: {} }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /surveys/export', () => {
  test('returns a CSV attachment', async () => {
    const repos = makeRepos();
    repos.surveys.listAll = jest.fn(async () => [{ id: 1, question_id: 'q1', response: 'ok', created_at: 't' }]);
    const res = await request(mountApp(repos)).get('/surveys/export');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/csv/);
    expect(res.text).toContain('id,question_id,response,created_at');
  });
});

describe('POST /surveys/analyze-sentiment', () => {
  test('rejects a non-array body', async () => {
    const res = await request(mountApp(makeRepos())).post('/surveys/analyze-sentiment').send({});
    expect(res.status).toBe(400);
  });

  test('classifies positive/negative/neutral responses', async () => {
    const res = await request(mountApp(makeRepos())).post('/surveys/analyze-sentiment')
      .send({ responses: ['מעולה', 'גרוע', 'meh'] });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ positive: 1, negative: 1, neutral: 1, total: 3 });
  });
});

describe('GET /survey-check', () => {
  test('does not show survey below the minute/call thresholds', async () => {
    const res = await request(mountApp(makeRepos())).get('/survey-check?sessionMinutes=1&agentCallCount=1');
    expect(res.status).toBe(200);
    expect(res.body.showSurvey).toBe(false);
  });

  test('respects the cooldown when a recent completed survey exists', async () => {
    const repos = makeRepos();
    repos.surveys.recentCompleted = jest.fn(async () => [{ id: 1 }]);
    const res = await request(mountApp(repos)).get('/survey-check?sessionMinutes=30&userName=nadav');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ showSurvey: false, cooldown: true });
  });
});

describe('POST /survey-submit', () => {
  test('requires responses and userName', async () => {
    const res = await request(mountApp(makeRepos())).post('/survey-submit').send({});
    expect(res.status).toBe(400);
  });

  test('persists a graceful insert and returns a summary', async () => {
    const repos = makeRepos();
    repos.surveys.insertGraceful = jest.fn(async () => ({ error: null }));
    const res = await request(mountApp(repos)).post('/survey-submit')
      .send({ userName: 'nadav', responses: { dailyValue: 'מאוד' } });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(repos.surveys.insertGraceful).toHaveBeenCalled();
  });
});

describe('GET /survey-history', () => {
  test('requires userName', async () => {
    const res = await request(mountApp(makeRepos())).get('/survey-history');
    expect(res.status).toBe(400);
  });
});

describe('GET /survey-insights', () => {
  test('reports not-enough-data below the minimum survey count', async () => {
    const repos = makeRepos();
    repos.surveys.responsesForUser = jest.fn(async () => []);
    const res = await request(mountApp(repos)).get('/survey-insights?userName=nadav');
    expect(res.status).toBe(200);
    expect(res.body.enough).toBe(false);
  });
});

describe('GET /survey-smart-check', () => {
  test('generates LLM-crafted questions', async () => {
    const res = await request(mountApp(makeRepos())).get('/survey-smart-check?userName=nadav');
    expect(res.status).toBe(200);
    expect(res.body.showSurvey).toBe(true);
    expect(res.body.smart).toBe(true);
  });
});

describe('GET /survey-impact', () => {
  test('returns concerns derived from negative answers', async () => {
    const repos = makeRepos();
    repos.surveys.recentResponsesWithDateById = jest.fn(async () => [
      { responses: JSON.stringify({ responseQuality: 'בינונית' }), created_at: 't1' },
    ]);
    const res = await request(mountApp(repos)).get('/survey-impact?userName=nadav');
    expect(res.status).toBe(200);
    expect(res.body.totalSurveys).toBe(1);
    expect(res.body.concerns).toEqual([{ area: 'איכות התשובות שקיבלת?', answer: 'בינונית', date: 't1' }]);
  });
});
