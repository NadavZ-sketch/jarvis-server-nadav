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

let app;
beforeAll(() => {
  ({ app } = require('../../server'));
});

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
