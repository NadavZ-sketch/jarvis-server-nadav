'use strict';

// Standard server bootstrap mocks so requiring server.js doesn't open real sockets/timers.
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
  callGemma4: jest.fn().mockResolvedValue(
    'Sure! Here is my thoughts.\n```json\n{"name":"Test Feature","type":"feature","description":"A test feature","acceptanceCriteria":["Works correctly"]}\n```'
  ),
  callGeminiVision: jest.fn(),
  callGeminiWithSearch: jest.fn(),
  callGemma4Stream: jest.fn(),
}));

const mockBacklog = {
  items: [],
  proposals: [{ id: 1, title: 'Test', type: 'feature', status: 'proposal', plan: '', priority: 'medium', auditTrail: [], checklist: [], blockers: [], acceptanceCriteria: [] }],
  _nextId: 2,
};
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  readFileSync: jest.fn((path) => {
    if (path.includes('backlog.json')) return JSON.stringify(mockBacklog);
    return jest.requireActual('fs').readFileSync(path);
  }),
  writeFileSync: jest.fn(),
  existsSync: jest.fn(() => true),
}));

const request = require('supertest');

let app;
beforeAll(() => {
  ({ app } = require('../../server'));
});

describe('POST /workshop/:proposalId/chat', () => {
  it('returns reply and spec on valid request', async () => {
    const res = await request(app)
      .post('/workshop/1/chat')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ message: 'I want a feature that does X', history: [] });
    expect(res.status).toBe(200);
    expect(res.body.reply).toBeTruthy();
    expect(res.body.spec).toBeDefined();
    expect(res.body.spec.name).toBe('Test Feature');
    expect(res.body.spec.acceptanceCriteria).toBeInstanceOf(Array);
  });

  it('returns 404 for unknown proposal', async () => {
    const res = await request(app)
      .post('/workshop/9999/chat')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ message: 'hello', history: [] });
    expect(res.status).toBe(404);
  });

  it('returns 400 when message is missing', async () => {
    const res = await request(app)
      .post('/workshop/1/chat')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({ history: [] });
    expect(res.status).toBe(400);
  });
});

describe('POST /workshop/:proposalId/save-spec', () => {
  it('returns 200 with path on valid spec', async () => {
    const res = await request(app)
      .post('/workshop/1/save-spec')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({
        spec: {
          name: 'My Feature',
          type: 'feature',
          description: 'Does something cool',
          acceptanceCriteria: ['Works', 'Fast'],
        },
      });
    expect(res.status).toBe(200);
    expect(res.body.path).toMatch(/\.md$/);
  });

  it('returns 400 when spec is missing', async () => {
    const res = await request(app)
      .post('/workshop/1/save-spec')
      .set('x-user-role', 'member')
      .set('x-user-plan', 'free')
      .send({});
    expect(res.status).toBe(400);
  });
});
