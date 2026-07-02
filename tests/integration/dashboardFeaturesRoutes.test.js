'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

let mockFeatures;
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  readFileSync: jest.fn((filePath, enc) => {
    if (String(filePath).includes('features.json')) return JSON.stringify(mockFeatures);
    return jest.requireActual('fs').readFileSync(filePath, enc);
  }),
  writeFileSync: jest.fn((filePath, content) => {
    if (String(filePath).includes('features.json')) mockFeatures = JSON.parse(content);
  }),
  // writeJsonAtomic writes to a .tmp file then renames it into place — the
  // mocked writeFileSync never creates a real file, so rename must be a no-op.
  renameSync: jest.fn(),
}));

const express = require('express');
const request = require('supertest');
const { callGemma4 } = require('../../agents/models');
const { createDashboardFeaturesRouter } = require('../../routes/dashboardFeatures');

function mountApp() {
  const app = express();
  app.use(express.json());
  app.use('/dashboard/features', createDashboardFeaturesRouter());
  return app;
}

function seedFeatures() {
  mockFeatures = {
    lastUpdated: '2026-05-01',
    features: {
      done: [{ name: 'צ׳אט', desc: 'קיים' }],
      building: [{ name: 'Dashboard חדש', desc: '' }],
      planned: [],
    },
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  seedFeatures();
});

describe('GET /dashboard/features', () => {
  test('returns the raw features.json payload', async () => {
    const res = await request(mountApp()).get('/dashboard/features');
    expect(res.status).toBe(200);
    expect(res.body.features.done).toHaveLength(1);
  });

  test('500 when the file is unreadable/malformed', async () => {
    const fs = require('fs');
    fs.readFileSync.mockImplementationOnce(() => { throw new Error('boom'); });
    const res = await request(mountApp()).get('/dashboard/features');
    expect(res.status).toBe(500);
  });
});

describe('POST /dashboard/features', () => {
  test('rejects a blank name', async () => {
    const res = await request(mountApp()).post('/dashboard/features').send({ name: '  ' });
    expect(res.status).toBe(400);
  });

  test('adds a feature to the requested bucket', async () => {
    const res = await request(mountApp()).post('/dashboard/features')
      .send({ name: 'תכונה חדשה', desc: 'תיאור', status: 'planned' });
    expect(res.status).toBe(200);
    expect(mockFeatures.features.planned).toContainEqual({ name: 'תכונה חדשה', desc: 'תיאור' });
    expect(mockFeatures.lastUpdated).not.toBe('2026-05-01');
  });

  test('defaults an invalid status to planned', async () => {
    await request(mountApp()).post('/dashboard/features').send({ name: 'x', status: 'bogus' });
    expect(mockFeatures.features.planned.some(f => f.name === 'x')).toBe(true);
  });

  test('409 on a duplicate name across any bucket (case/whitespace-insensitive)', async () => {
    const res = await request(mountApp()).post('/dashboard/features').send({ name: '  צ׳אט  ' });
    expect(res.status).toBe(409);
  });
});

describe('PATCH /dashboard/features', () => {
  test('rejects a missing name or oldStatus', async () => {
    const res = await request(mountApp()).patch('/dashboard/features').send({ name: 'x' });
    expect(res.status).toBe(400);
  });

  test('rejects an invalid oldStatus', async () => {
    const res = await request(mountApp()).patch('/dashboard/features')
      .send({ name: 'x', oldStatus: 'bogus' });
    expect(res.status).toBe(400);
  });

  test('404 when the feature is not found in oldStatus', async () => {
    const res = await request(mountApp()).patch('/dashboard/features')
      .send({ name: 'לא קיים', oldStatus: 'planned' });
    expect(res.status).toBe(404);
  });

  test('moves a feature between buckets and updates its description', async () => {
    const res = await request(mountApp()).patch('/dashboard/features')
      .send({ name: 'Dashboard חדש', oldStatus: 'building', newStatus: 'done', desc: 'הושלם' });
    expect(res.status).toBe(200);
    expect(res.body.movedFrom).toBe('building');
    expect(res.body.movedTo).toBe('done');
    expect(mockFeatures.features.building).toHaveLength(0);
    expect(mockFeatures.features.done.find(f => f.name === 'Dashboard חדש').desc).toBe('הושלם');
  });

  test('keeps the same bucket when newStatus is invalid/omitted', async () => {
    const res = await request(mountApp()).patch('/dashboard/features')
      .send({ name: 'Dashboard חדש', oldStatus: 'building', desc: 'עדכון' });
    expect(res.status).toBe(200);
    expect(res.body.movedTo).toBe('building');
    expect(mockFeatures.features.building[0].desc).toBe('עדכון');
  });
});

describe('DELETE /dashboard/features', () => {
  test('rejects a missing name or status', async () => {
    const res = await request(mountApp()).delete('/dashboard/features').send({ name: 'x' });
    expect(res.status).toBe(400);
  });

  test('404 when the feature is not found', async () => {
    const res = await request(mountApp()).delete('/dashboard/features')
      .send({ name: 'לא קיים', status: 'planned' });
    expect(res.status).toBe(404);
  });

  test('removes the feature from its bucket', async () => {
    const res = await request(mountApp()).delete('/dashboard/features')
      .send({ name: 'צ׳אט', status: 'done' });
    expect(res.status).toBe(200);
    expect(mockFeatures.features.done).toHaveLength(0);
  });
});

describe('POST /dashboard/features/suggest-description', () => {
  test('rejects a blank name', async () => {
    const res = await request(mountApp()).post('/dashboard/features/suggest-description').send({});
    expect(res.status).toBe(400);
  });

  test('returns a trimmed, quote-stripped description from the LLM', async () => {
    callGemma4.mockResolvedValue('"תיאור נחמד."');
    const res = await request(mountApp()).post('/dashboard/features/suggest-description')
      .send({ name: 'תכונה', status: 'building' });
    expect(res.status).toBe(200);
    expect(res.body.description).toBe('תיאור נחמד.');
  });

  test('500 when the LLM call throws', async () => {
    callGemma4.mockRejectedValue(new Error('llm down'));
    const res = await request(mountApp()).post('/dashboard/features/suggest-description').send({ name: 'x' });
    expect(res.status).toBe(500);
  });
});

describe('POST /dashboard/features/generate-descriptions', () => {
  test('returns an empty list when nothing needs a description', async () => {
    const res = await request(mountApp()).post('/dashboard/features/generate-descriptions')
      .send({ features: [{ name: 'x', desc: 'כבר יש' }] });
    expect(res.status).toBe(200);
    expect(res.body.descriptions).toEqual([]);
    expect(callGemma4).not.toHaveBeenCalled();
  });

  test('parses the LLM JSON array response', async () => {
    callGemma4.mockResolvedValue('הנה: [{"name":"x","description":"תיאור"}]');
    const res = await request(mountApp()).post('/dashboard/features/generate-descriptions')
      .send({ features: [{ name: 'x', status: 'planned' }] });
    expect(res.status).toBe(200);
    expect(res.body.descriptions).toEqual([{ name: 'x', description: 'תיאור' }]);
  });

  test('returns an empty list when the LLM output is unparseable', async () => {
    callGemma4.mockResolvedValue('no json here');
    const res = await request(mountApp()).post('/dashboard/features/generate-descriptions')
      .send({ features: [{ name: 'x' }] });
    expect(res.status).toBe(200);
    expect(res.body.descriptions).toEqual([]);
  });

  test('caps the batch at 12 features needing a description', async () => {
    callGemma4.mockResolvedValue('[]');
    const many = Array.from({ length: 20 }, (_, i) => ({ name: `f${i}` }));
    await request(mountApp()).post('/dashboard/features/generate-descriptions').send({ features: many });
    const promptArg = callGemma4.mock.calls[0][0];
    // 12 dash-bullet lines, not 20
    expect((promptArg.match(/^- /gm) || []).length).toBe(12);
  });
});
