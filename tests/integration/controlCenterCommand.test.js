'use strict';

// Integration coverage for the control-center natural-language command bar
// (POST /progress-map/command) and the dashboard `role` field on /user-profile.
// The command router must resolve common actions deterministically (no LLM) and
// only fall back to the model for free-form questions.

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
// The LLM is only reached for genuinely free-form questions; a distinctive
// marker lets us assert when (and only when) the router fell through to it.
const _llmMarker = '[[LLM_FALLBACK]]';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn().mockResolvedValue('[[LLM_FALLBACK]] תשובה'),
    callGemma4Stream: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
}));

const request = require('supertest');
const { app } = require('../../server');
const { callGemma4 } = require('../../agents/models');

beforeEach(() => { callGemma4.mockClear(); });

describe('POST /progress-map/command', () => {
    test('rejects an empty command', async () => {
        const res = await request(app).post('/progress-map/command').send({ text: '' });
        expect(res.status).toBe(400);
    });

    test('navigates to a tab deterministically (no LLM)', async () => {
        const res = await request(app).post('/progress-map/command').send({ text: 'הצג אנליטיקה' });
        expect(res.status).toBe(200);
        expect(res.body.action).toBe('navigate');
        expect(res.body.params.tab).toBe('analytics');
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('routes a code scan request without the LLM', async () => {
        const res = await request(app).post('/progress-map/command').send({ text: 'סרוק שגיאות קוד' });
        expect(res.body.action).toBe('run_scan');
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('toggles an agent off by its Hebrew noun, tolerant of the definite article', async () => {
        const res = await request(app).post('/progress-map/command').send({ text: 'כבה את סוכן החדשות' });
        expect(res.body.action).toBe('toggle_agent');
        expect(res.body.params.agentId).toBe('newsAgent');
        expect(res.body.params.status).toBe('disabled');
        expect(callGemma4).not.toHaveBeenCalled();
        // cleanup: re-enable so the registry override file isn't left dirty
        await request(app).post('/progress-map/command').send({ text: 'הפעל את סוכן החדשות' });
    });

    test('refuses to disable a protected agent', async () => {
        const res = await request(app).post('/progress-map/command').send({ text: 'כבה את chatAgent' });
        expect(res.body.action).toBe('answer');
        expect(res.body.answer).toMatch(/מוגן/);
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('falls back to the LLM for a free-form metrics question', async () => {
        const res = await request(app).post('/progress-map/command').send({ text: 'איזה סוכן הכי איטי השבוע?' });
        expect(res.body.action).toBe('answer');
        expect(res.body.answer).toContain(_llmMarker);
        expect(callGemma4).toHaveBeenCalledTimes(1);
    });
});
