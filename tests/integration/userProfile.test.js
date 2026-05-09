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

beforeEach(() => {
  jest.clearAllMocks();
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
});
