'use strict';

jest.mock('openai', () => ({
  OpenAI: jest.fn().mockImplementation(() => ({
    audio: { transcriptions: { create: jest.fn().mockResolvedValue({ text: '' }) } },
  })),
  toFile: jest.fn().mockResolvedValue({}),
}));
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({
  createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn().mockResolvedValue({ messageId: 'm' }) }),
}));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: 'bW9jaw==' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({
  initSync: jest.fn().mockResolvedValue(undefined),
  fullSyncFromDb: jest.fn().mockResolvedValue(undefined),
  appendChatMessage: jest.fn().mockResolvedValue(undefined),
  syncAll: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../agents/models', () => ({
  callGemma4: jest.fn().mockResolvedValue('{}'),
  callGeminiVision: jest.fn(),
  callGeminiWithSearch: jest.fn(),
  callGemma4Stream: jest.fn(),
}));

const mockBacklog = { items: [], proposals: [], _nextId: 1 };
let mockOverrides = [];

jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  readFileSync: jest.fn((filePath) => {
    if (String(filePath).includes('backlog.json')) return JSON.stringify(mockBacklog);
    if (String(filePath).includes('router-overrides.json')) {
      return JSON.stringify({ overrides: mockOverrides });
    }
    return jest.requireActual('fs').readFileSync(filePath);
  }),
  writeFileSync: jest.fn((filePath, content) => {
    if (String(filePath).includes('router-overrides.json')) {
      mockOverrides = JSON.parse(content).overrides;
    }
  }),
  existsSync: jest.fn(() => true),
}));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');

let app;
let supabaseClient;
beforeAll(() => {
  ({ app } = require('../../server'));
  supabaseClient = createClient.mock.results[0].value;
});

function makeChain(data = [], error = null) {
  const chain = {
    select: jest.fn().mockReturnThis(),
    eq: jest.fn().mockReturnThis(),
    order: jest.fn().mockReturnThis(),
    limit: jest.fn().mockResolvedValue({ data, error }),
  };
  return chain;
}

beforeEach(() => {
  mockOverrides = [];
  jest.clearAllMocks();
  // Re-mock readFileSync after clearAllMocks
  const fs = require('fs');
  fs.readFileSync.mockImplementation((filePath) => {
    if (String(filePath).includes('backlog.json')) return JSON.stringify(mockBacklog);
    if (String(filePath).includes('router-overrides.json')) return JSON.stringify({ overrides: mockOverrides });
    return jest.requireActual('fs').readFileSync(filePath);
  });
  fs.writeFileSync.mockImplementation((filePath, content) => {
    if (String(filePath).includes('router-overrides.json')) {
      mockOverrides = JSON.parse(content).overrides;
    }
  });
  // Reset overrides cache so endpoints read fresh
  const router = require('../../agents/router');
  if (router.invalidateOverridesCache) router.invalidateOverridesCache();
  // Default supabase: return empty results
  supabaseClient.from.mockImplementation(() => makeChain([], null));
});

describe('GET /router/keywords', () => {
  it('returns empty overrides when file is empty', async () => {
    const res = await request(app)
      .get('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');
    expect(res.status).toBe(200);
    expect(res.body.overrides).toEqual([]);
  });

  it('returns existing overrides', async () => {
    mockOverrides = [{ keyword: 'חלב', intent: 'shopping' }];
    const res = await request(app)
      .get('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');
    expect(res.status).toBe(200);
    expect(res.body.overrides).toHaveLength(1);
    expect(res.body.overrides[0].keyword).toBe('חלב');
  });
});

describe('POST /router/keywords', () => {
  it('adds a new override', async () => {
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'תשלח לאמא', intent: 'messaging' });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.overrides).toHaveLength(1);
    expect(res.body.overrides[0]).toEqual({ keyword: 'תשלח לאמא', intent: 'messaging' });
  });

  it('does not add duplicate keyword+intent pair', async () => {
    mockOverrides = [{ keyword: 'חלב', intent: 'shopping' }];
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב', intent: 'shopping' });
    expect(res.status).toBe(200);
    expect(res.body.overrides).toHaveLength(1);
  });

  it('returns 400 when keyword is missing', async () => {
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ intent: 'shopping' });
    expect(res.status).toBe(400);
  });

  it('returns 400 when intent is missing', async () => {
    const res = await request(app)
      .post('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב' });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /router/keywords', () => {
  it('removes the matching override', async () => {
    mockOverrides = [
      { keyword: 'חלב', intent: 'shopping' },
      { keyword: 'תשלח לאמא', intent: 'messaging' },
    ];
    const res = await request(app)
      .delete('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב', intent: 'shopping' });
    expect(res.status).toBe(200);
    expect(res.body.overrides).toHaveLength(1);
    expect(res.body.overrides[0].keyword).toBe('תשלח לאמא');
  });

  it('returns 400 when keyword or intent missing', async () => {
    const res = await request(app)
      .delete('/router/keywords')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ keyword: 'חלב' });
    expect(res.status).toBe(400);
  });
});

describe('GET /router/training-events', () => {
  it('returns mapped events list from supabase', async () => {
    const fakeData = [
      { id: 'uuid-1', metadata: { message: 'שלח לאמא שלום' }, created_at: '2026-06-22T10:00:00Z' },
      { id: 'uuid-2', metadata: { message: 'מה מזג האוויר' }, created_at: '2026-06-22T09:00:00Z' },
    ];
    supabaseClient.from.mockReturnValue(makeChain(fakeData, null));

    const res = await request(app)
      .get('/router/training-events')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');

    expect(res.status).toBe(200);
    expect(res.body.events).toHaveLength(2);
    expect(res.body.events[0].id).toBe('uuid-1');
    expect(res.body.events[0].message).toBe('שלח לאמא שלום');
    expect(res.body.events[0].created_at).toBe('2026-06-22T10:00:00Z');
    expect(res.body.events[1].message).toBe('מה מזג האוויר');
  });

  it('returns empty events array when supabase returns no rows', async () => {
    supabaseClient.from.mockReturnValue(makeChain([], null));

    const res = await request(app)
      .get('/router/training-events')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');

    expect(res.status).toBe(200);
    expect(res.body.events).toEqual([]);
  });

  it('maps missing metadata.message to empty string', async () => {
    const fakeData = [
      { id: 'uuid-3', metadata: {}, created_at: '2026-06-22T08:00:00Z' },
      { id: 'uuid-4', metadata: null, created_at: '2026-06-22T07:00:00Z' },
    ];
    supabaseClient.from.mockReturnValue(makeChain(fakeData, null));

    const res = await request(app)
      .get('/router/training-events')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');

    expect(res.status).toBe(200);
    expect(res.body.events[0].message).toBe('');
    expect(res.body.events[1].message).toBe('');
  });

  it('returns 500 when supabase returns an error', async () => {
    const chain = {
      select: jest.fn().mockReturnThis(),
      eq: jest.fn().mockReturnThis(),
      order: jest.fn().mockReturnThis(),
      limit: jest.fn().mockResolvedValue({ data: null, error: new Error('db connection failed') }),
    };
    supabaseClient.from.mockReturnValue(chain);

    const res = await request(app)
      .get('/router/training-events')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');

    expect(res.status).toBe(500);
    expect(res.body.error).toBeDefined();
  });

  it('respects the ?limit query parameter (up to 100)', async () => {
    supabaseClient.from.mockReturnValue(makeChain([], null));

    await request(app)
      .get('/router/training-events?limit=10')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');

    const chain = supabaseClient.from.mock.results[0].value;
    expect(chain.limit).toHaveBeenCalledWith(10);
  });

  it('caps limit at 100 even when higher value is requested', async () => {
    supabaseClient.from.mockReturnValue(makeChain([], null));

    await request(app)
      .get('/router/training-events?limit=999')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free');

    const chain = supabaseClient.from.mock.results[0].value;
    expect(chain.limit).toHaveBeenCalledWith(100);
  });
});
