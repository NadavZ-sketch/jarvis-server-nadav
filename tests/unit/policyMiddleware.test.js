'use strict';

// Standard server bootstrap mocks (mirrors tests/integration/*) so requiring
// server.js doesn't open real sockets/timers. The policy engine itself is NOT
// mocked — we exercise the real config/policyRules.json.
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

const express = require('express');
const request = require('supertest');
const { evaluatePolicy, requirePolicy } = require('../../server');

const freeMember = { userId: 'u1', role: 'member', plan: 'free' };
const proMember = { userId: 'u2', role: 'member', plan: 'pro' };

describe('evaluatePolicy (pure decision)', () => {
  test('blocklisted action → blocked (403 ACTION_BLOCKED), even for pro', () => {
    const d = evaluatePolicy({ actionType: 'admin.reset_system', actor: proMember });
    expect(d).toMatchObject({ result: 'blocked', status: 403, code: 'ACTION_BLOCKED' });
  });

  test('action outside the role/plan allowlist → denied_not_allowed (403)', () => {
    const d = evaluatePolicy({ actionType: 'admin.tweak', actor: freeMember });
    expect(d).toMatchObject({ result: 'denied_not_allowed', status: 403, code: 'INSUFFICIENT_PERMISSION' });
  });

  test('pro/member wildcard allows an arbitrary non-blocked action', () => {
    const d = evaluatePolicy({ actionType: 'admin.tweak', actor: proMember });
    expect(d.result).toBe('allowed');
  });

  test('allowed non-sensitive action passes with no consent to store', () => {
    const d = evaluatePolicy({ actionType: 'reminders.create', actor: freeMember });
    expect(d).toEqual({ result: 'allowed', storeConsent: false });
  });

  test('sensitive action without consent → CONSENT_REQUIRED (403)', () => {
    const d = evaluatePolicy({ actionType: 'contacts.delete', sensitive: true, actor: freeMember });
    expect(d).toMatchObject({ result: 'denied_no_consent', status: 403, code: 'CONSENT_REQUIRED' });
  });

  test('sensitive action with explicit consent → allowed + storeConsent', () => {
    const d = evaluatePolicy({ actionType: 'contacts.delete', sensitive: true, explicitConsent: true, actor: freeMember });
    expect(d).toEqual({ result: 'allowed', storeConsent: true });
  });

  test('sensitive action with previously stored consent → allowed, no re-store', () => {
    const d = evaluatePolicy({ actionType: 'contacts.delete', sensitive: true, consentAlreadyGranted: true, actor: freeMember });
    expect(d).toEqual({ result: 'allowed', storeConsent: false });
  });

  test('irreversible action without confirmation → CONFIRMATION_REQUIRED (409)', () => {
    const d = evaluatePolicy({ actionType: 'contacts.delete', irreversible: true, actor: freeMember });
    expect(d).toMatchObject({ result: 'denied_missing_confirmation', status: 409, code: 'CONFIRMATION_REQUIRED' });
  });

  test('sensitive+irreversible with consent but no confirm still persists consent', () => {
    const d = evaluatePolicy({
      actionType: 'contacts.delete', sensitive: true, irreversible: true,
      explicitConsent: true, confirmed: false, actor: freeMember,
    });
    expect(d).toMatchObject({ result: 'denied_missing_confirmation', storeConsent: true });
  });

  test('fully satisfied sensitive+irreversible action → allowed', () => {
    const d = evaluatePolicy({
      actionType: 'contacts.delete', sensitive: true, irreversible: true,
      explicitConsent: true, confirmed: true, actor: freeMember,
    });
    expect(d.result).toBe('allowed');
  });
});

describe('requirePolicy middleware wiring', () => {
  const realEnv = process.env.NODE_ENV;
  afterEach(() => { process.env.NODE_ENV = realEnv; });

  function appWith(actionType, options) {
    const app = express();
    app.use(express.json());
    app.post('/x', requirePolicy(actionType, options), (_req, res) => res.json({ ok: true, passed: true }));
    return app;
  }

  test('bypasses entirely under NODE_ENV=test', async () => {
    process.env.NODE_ENV = 'test';
    const res = await request(appWith('admin.reset_system', {})).post('/x').send({});
    expect(res.status).toBe(200);
    expect(res.body.passed).toBe(true);
  });

  test('maps a blocked decision to a 403 ACTION_BLOCKED response', async () => {
    process.env.NODE_ENV = 'production';
    const res = await request(appWith('admin.reset_system', {})).post('/x').send({});
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('ACTION_BLOCKED');
  });

  test('sensitive action is gated, then passes once consent is given (and remembered)', async () => {
    process.env.NODE_ENV = 'production';
    const app = appWith('contacts.delete', { sensitive: true });

    // 1) no consent → blocked
    const blocked = await request(app).post('/x').set('x-user-id', 'consent-user').send({});
    expect(blocked.status).toBe(403);
    expect(blocked.body.code).toBe('CONSENT_REQUIRED');

    // 2) explicit consent header → passes and is stored in the ledger
    const granted = await request(app).post('/x').set('x-user-id', 'consent-user').set('x-user-consent', 'true').send({});
    expect(granted.status).toBe(200);

    // 3) same user, no consent header → still passes (consent remembered)
    const remembered = await request(app).post('/x').set('x-user-id', 'consent-user').send({});
    expect(remembered.status).toBe(200);
  });

  test('irreversible action requires confirmation (409 then 200)', async () => {
    process.env.NODE_ENV = 'production';
    const app = appWith('contacts.delete', { irreversible: true });
    const noConfirm = await request(app).post('/x').set('x-user-id', 'confirm-user').send({});
    expect(noConfirm.status).toBe(409);
    expect(noConfirm.body.code).toBe('CONFIRMATION_REQUIRED');

    const confirmed = await request(app).post('/x').set('x-user-id', 'confirm-user').set('x-confirm-action', 'yes').send({});
    expect(confirmed.status).toBe(200);
  });
});
