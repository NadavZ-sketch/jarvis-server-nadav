'use strict';

jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({ createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn() }) }));
jest.mock('openai', () => ({ OpenAI: jest.fn().mockImplementation(() => ({ audio: { transcriptions: { create: jest.fn() } } })), toFile: jest.fn() }));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: '' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({ initSync: jest.fn(), fullSyncFromDb: jest.fn(), appendChatMessage: jest.fn(), syncAll: jest.fn() }));
jest.mock('../../services/weatherSource', () => ({ getWeatherSummary: jest.fn().mockResolvedValue(null) }));
jest.mock('../../services/newsSource', () => ({ getNewsSummary: jest.fn().mockResolvedValue(null), getTopicHeadlines: jest.fn().mockResolvedValue(null) }));
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGemma4Stream: jest.fn(),
}));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { callGemma4 } = require('../../agents/models');
const { app, cacheInvalidate } = require('../../server');

function makeChain(data = []) {
    const chain = {
        select: jest.fn().mockReturnThis(),
        eq: jest.fn().mockReturnThis(),
        order: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
        then: (resolve) => resolve({ data, error: null }),
    };
    return chain;
}

let supabaseClient;
beforeEach(() => {
    supabaseClient = createClient.mock.results[0]?.value || { from: jest.fn() };
    supabaseClient.from = jest.fn().mockImplementation(() => makeChain([]));
    jest.clearAllMocks();
    supabaseClient.from = jest.fn().mockImplementation(() => makeChain([]));
    cacheInvalidate('smart-suggestions');
});

describe('GET /smart-suggestions', () => {
    it('returns 200 with suggestions array', async () => {
        // Provide a user chat message so the endpoint sends content to the LLM
        supabaseClient.from = jest.fn().mockImplementation(() =>
            makeChain([{ role: 'user', text: 'צריך לחזור לאביב בענין ההצעה', created_at: new Date().toISOString() }])
        );
        callGemma4.mockResolvedValue(
            '[{"text":"לחזור לאביב לגבי ההצעה","sourceType":"chat","sourceLabel":"לפני 2 ימים"}]'
        );
        const res = await request(app).get('/smart-suggestions');
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('suggestions');
        expect(Array.isArray(res.body.suggestions)).toBe(true);
    });

    it('returns empty array when LLM returns invalid JSON', async () => {
        callGemma4.mockResolvedValue('לא הצלחתי לנתח');
        const res = await request(app).get('/smart-suggestions');
        expect(res.status).toBe(200);
        expect(res.body.suggestions).toEqual([]);
    });

    it('returns empty array when LLM call fails', async () => {
        callGemma4.mockRejectedValue(new Error('LLM down'));
        const res = await request(app).get('/smart-suggestions');
        expect(res.status).toBe(200);
        expect(res.body.suggestions).toEqual([]);
    });

    it('assigns an id to each suggestion', async () => {
        // Provide a user chat message so the endpoint has content to send to the LLM
        supabaseClient.from = jest.fn().mockImplementation(() =>
            makeChain([{ role: 'user', text: 'צריך לדבר עם אביב', created_at: new Date().toISOString() }])
        );
        callGemma4.mockResolvedValue(
            '[{"text":"משימה לדוגמה","sourceType":"task","sourceLabel":"פגת תוקף"}]'
        );
        const res = await request(app).get('/smart-suggestions');
        expect(res.body.suggestions[0]).toHaveProperty('id');
        expect(typeof res.body.suggestions[0].id).toBe('string');
    });
});
