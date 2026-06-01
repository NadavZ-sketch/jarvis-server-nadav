'use strict';

jest.mock('openai', () => ({
    OpenAI: jest.fn().mockImplementation(() => ({
        audio: { transcriptions: { create: jest.fn().mockResolvedValue({ text: '' }) } },
    })),
    toFile: jest.fn().mockResolvedValue({}),
}));
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({
    createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn().mockResolvedValue({}) }),
}));
jest.mock('google-tts-api', () => ({
    getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: 'bW9jaw==' }]),
}));
jest.mock('@supabase/supabase-js', () => ({
    createClient: jest.fn().mockReturnValue({ from: jest.fn() }),
}));
jest.mock('../../services/obsidianSync', () => ({
    initSync: jest.fn().mockResolvedValue(undefined),
    fullSyncFromDb: jest.fn().mockResolvedValue(undefined),
    appendChatMessage: jest.fn().mockResolvedValue(undefined),
    syncAll: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn().mockResolvedValue('בוקר טוב נדב! יש לך 2 משימות פתוחות.'),
    callGemma4Stream: jest.fn(),
}));

const request = require('supertest');
const { app, cacheInvalidate } = require('../../server');
const { callGemma4 } = require('../../agents/models');

const PROMPT = 'אתה ג׳רוויס. תן תובנה קצרה.';

beforeEach(() => {
    jest.clearAllMocks();
    callGemma4.mockResolvedValue('בוקר טוב נדב! יש לך 2 משימות פתוחות.');
    // Clear any cached insight from a previous test.
    ['default', 'u1'].forEach(u =>
        ['briefing', 'checkin', 'recap', 'winddown', 'auto'].forEach(m =>
            cacheInvalidate(`insight:${u}:${m}`)
        )
    );
});

describe('POST /insight-card', () => {
    it('returns 200 with an LLM-generated answer on a cache miss', async () => {
        const res = await request(app)
            .post('/insight-card')
            .send({ prompt: PROMPT, mode: 'briefing', userId: 'u1' });
        expect(res.status).toBe(200);
        expect(res.body.answer).toContain('בוקר טוב');
        expect(res.body.cached).toBe(false);
        expect(callGemma4).toHaveBeenCalledTimes(1);
    });

    it('serves the cached insight on a repeat call without hitting the LLM', async () => {
        await request(app).post('/insight-card').send({ prompt: PROMPT, mode: 'briefing', userId: 'u1' });
        callGemma4.mockClear();
        const res = await request(app)
            .post('/insight-card')
            .send({ prompt: PROMPT, mode: 'briefing', userId: 'u1' });
        expect(res.status).toBe(200);
        expect(res.body.cached).toBe(true);
        expect(callGemma4).not.toHaveBeenCalled();
    });

    it('bypasses the cache when fresh:true is passed', async () => {
        await request(app).post('/insight-card').send({ prompt: PROMPT, mode: 'briefing', userId: 'u1' });
        callGemma4.mockClear();
        const res = await request(app)
            .post('/insight-card')
            .send({ prompt: PROMPT, mode: 'briefing', userId: 'u1', fresh: true });
        expect(res.status).toBe(200);
        expect(res.body.cached).toBe(false);
        expect(callGemma4).toHaveBeenCalledTimes(1);
    });

    it('caches per mode (different modes do not collide)', async () => {
        await request(app).post('/insight-card').send({ prompt: PROMPT, mode: 'briefing', userId: 'u1' });
        callGemma4.mockClear();
        const res = await request(app)
            .post('/insight-card')
            .send({ prompt: PROMPT, mode: 'recap', userId: 'u1' });
        expect(res.body.cached).toBe(false);
        expect(callGemma4).toHaveBeenCalledTimes(1);
    });

    it('returns 400 when prompt is missing', async () => {
        const res = await request(app).post('/insight-card').send({ mode: 'briefing' });
        expect(res.status).toBe(400);
        expect(callGemma4).not.toHaveBeenCalled();
    });

    it('returns 500 when the LLM call fails', async () => {
        callGemma4.mockRejectedValueOnce(new Error('LLM timeout'));
        const res = await request(app)
            .post('/insight-card')
            .send({ prompt: PROMPT, mode: 'checkin', userId: 'u1' });
        expect(res.status).toBe(500);
    });
});
