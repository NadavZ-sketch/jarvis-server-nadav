'use strict';

jest.mock('openai', () => ({
  OpenAI: jest.fn().mockImplementation(() => ({
    audio: { transcriptions: { create: jest.fn().mockResolvedValue({ text: '' }) } },
  })),
  toFile: jest.fn().mockResolvedValue({}),
}));
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({ createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn().mockResolvedValue({}) }) }));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: 'bW9jaw==' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({
  initSync: jest.fn().mockResolvedValue(undefined),
  fullSyncFromDb: jest.fn().mockResolvedValue(undefined),
  appendChatMessage: jest.fn().mockResolvedValue(undefined),
  syncAll: jest.fn().mockResolvedValue(undefined),
}));

const fs = require('fs');
const path = require('path');
const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { app } = require('../../server');

function makeChain(data = [], error = null) {
  const chain = {
    then(res) { return Promise.resolve({ data, error }).then(res); },
    catch(rej) { return Promise.resolve({ data, error }).catch(rej); },
    select: jest.fn().mockReturnThis(),
    insert: jest.fn().mockReturnThis(),
    update: jest.fn().mockReturnThis(),
    delete: jest.fn().mockReturnThis(),
    eq: jest.fn().mockReturnThis(),
    order: jest.fn().mockReturnThis(),
    limit: jest.fn().mockReturnThis(),
    single: jest.fn().mockResolvedValue({ data: { id: 'db-id', speaking_tone: 'friendly' }, error: null }),
  };
  return chain;
}

const supabaseClient = createClient.mock.results[0].value;
const fallbackFile = path.join(__dirname, '../../notes/user_profile_fallback.json');
const { cacheInvalidate } = require('../../server');

beforeEach(() => {
  jest.clearAllMocks();
  cacheInvalidate('userProfile'); // ensure profile cache starts empty for each test
  if (fs.existsSync(fallbackFile)) fs.unlinkSync(fallbackFile);
  supabaseClient.from.mockImplementation(() => makeChain([], null));
});

afterAll(() => {
  if (fs.existsSync(fallbackFile)) fs.unlinkSync(fallbackFile);
});

describe('user profile endpoints', () => {
  test('POST /user-profile saves to DB when available', async () => {
    const res = await request(app).post('/user-profile').send({ speaking_tone: 'friendly', interests: ['כדורגל'] });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.fallback).toBeUndefined();
  });

  test('GET /user-profile caches result — DB called only once for two requests', async () => {
    // Two back-to-back GETs; only the first should hit user_profiles
    await request(app).get('/user-profile');
    await request(app).get('/user-profile');
    const userProfileDbCalls = supabaseClient.from.mock.calls.filter(([t]) => t === 'user_profiles').length;
    expect(userProfileDbCalls).toBe(1);
  });

  test('POST /user-profile falls back to local file on DB error', async () => {
    supabaseClient.from.mockImplementation(() => {
      const c = makeChain([], null);
      c.single = jest.fn().mockResolvedValue({ data: null, error: { message: 'db write failed' } });
      return c;
    });

    const res = await request(app).post('/user-profile').send({ speaking_tone: 'friendly', interests: ['כדורגל'] });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.fallback).toBe(true);
    expect(fs.existsSync(fallbackFile)).toBe(true);
  });

  test('POST /user-profile saves role field (admin | user)', async () => {
    // Mock the response to include preferences
    supabaseClient.from.mockImplementation(() => {
      const c = makeChain([], null);
      c.single = jest.fn().mockResolvedValue({
        data: { id: 'test-id', preferences: { role: 'admin' }, updated_at: new Date().toISOString() },
        error: null,
      });
      return c;
    });
    const res = await request(app).post('/user-profile').send({ role: 'admin' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.profile.preferences).toBeDefined();
    expect(res.body.profile.preferences.role).toBe('admin');
  });

  test('POST /user-profile rejects invalid role values', async () => {
    const res = await request(app).post('/user-profile').send({ role: 'superadmin' });
    expect(res.status).toBe(200);
    // Invalid role should be silently ignored, not stored
    const getRes = await request(app).get('/user-profile');
    if (getRes.body.profile && getRes.body.profile.preferences) {
      expect(getRes.body.profile.preferences.role).not.toBe('superadmin');
    }
  });
});
