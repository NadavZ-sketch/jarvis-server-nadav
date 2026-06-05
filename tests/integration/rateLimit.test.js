'use strict';
// Infra mocks so requiring server.js doesn't open sockets/timers.
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

const request = require('supertest');
const { app } = require('../../server');

describe('rate limiting', () => {
    test('/send-email allows 5 requests/min then returns 429', async () => {
        const statuses = [];
        for (let i = 0; i < 6; i++) {
            const res = await request(app).post('/send-email').send({ to: 'x@y.com', message: 'hi' });
            statuses.push(res.status);
        }
        // First five pass the limiter (whatever the handler returns, not 429).
        expect(statuses.slice(0, 5).every(s => s !== 429)).toBe(true);
        // The sixth is throttled.
        expect(statuses[5]).toBe(429);
    });
});
