'use strict';

jest.mock('openai', () => ({
  OpenAI: jest.fn().mockImplementation(() => ({
    audio: { transcriptions: { create: jest.fn().mockResolvedValue({ text: '' }) } },
  })),
  toFile: jest.fn().mockResolvedValue({}),
}));
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({
  createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn().mockResolvedValue({ messageId: 'mock-id' }) }),
}));
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
const { app } = require('../../server');

const backlogPath = path.join(__dirname, '../../backlog.json');
let originalBacklog = null;

beforeAll(() => {
  if (fs.existsSync(backlogPath)) {
    originalBacklog = fs.readFileSync(backlogPath, 'utf8');
  }
});

afterAll(() => {
  if (originalBacklog !== null) {
    fs.writeFileSync(backlogPath, originalBacklog, 'utf8');
  }
});

beforeEach(() => {
  const seed = {
    items: [],
    proposals: [
      { id: 1001, title: 'בדיקת lifecycle', plan: 'plan', status: 'proposal', priority: 'high', category: 'feature' },
    ],
    _nextId: 1002,
  };
  fs.writeFileSync(backlogPath, JSON.stringify(seed, null, 2), 'utf8');
});

describe('Backlog proposal lifecycle', () => {
  test('creates draft plan from proposal and records audit', async () => {
    const res = await request(app)
      .post('/dashboard/backlog/proposals/1001/draft-plan')
      .send({ actor: 'test_user', reason: 'initial planning' });

    expect(res.status).toBe(200);
    expect(res.body.item.status).toBe('draft_plan');
    expect(res.body.item.owner).toBe('agent');
    expect(Array.isArray(res.body.item.checklist)).toBe(true);
    expect(res.body.item.auditTrail[0].by).toBe('test_user');
  });

  test('enforces validation before done', async () => {
    await request(app)
      .post('/dashboard/backlog/proposals/1001/draft-plan')
      .send({ actor: 'test_user', reason: 'initial planning' });

    const illegal = await request(app)
      .patch('/dashboard/backlog/proposals/1001')
      .send({ status: 'done', actor: 'test_user', reason: 'skip validation' });

    expect(illegal.status).toBe(400);
    expect(illegal.body.error).toMatch(/invalid transition|validation/);
  });

  test('allows full valid lifecycle path', async () => {
    await request(app).post('/dashboard/backlog/proposals/1001/draft-plan').send({ actor: 'test_user' });

    const active = await request(app)
      .patch('/dashboard/backlog/proposals/1001')
      .send({ status: 'active', actor: 'test_user', reason: 'start execution' });
    expect(active.status).toBe(200);

    const validation = await request(app)
      .patch('/dashboard/backlog/proposals/1001')
      .send({ status: 'validation', actor: 'test_user', reason: 'ready to validate' });
    expect(validation.status).toBe(200);

    const done = await request(app)
      .patch('/dashboard/backlog/proposals/1001')
      .send({ status: 'done', actor: 'test_user', reason: 'validated' });
    expect(done.status).toBe(200);
    expect(done.body.item.status).toBe('done');
    expect(done.body.item.auditTrail.length).toBeGreaterThanOrEqual(3);
  });
});
