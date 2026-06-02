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

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { app } = require('../../server');

const supabaseClient = createClient.mock.results[0].value;

// Captures rows inserted into smart_telemetry_events.
let inserted = [];
function makeChain(table) {
    return {
        insert: jest.fn((rows) => {
            if (table === 'smart_telemetry_events') inserted.push(...rows);
            return Promise.resolve({ data: rows, error: null });
        }),
        select: jest.fn().mockReturnThis(),
        eq: jest.fn().mockReturnThis(),
        gte: jest.fn().mockReturnThis(),
        order: jest.fn().mockReturnThis(),
        limit: jest.fn().mockResolvedValue({ data: [], error: null }),
    };
}

beforeEach(() => {
    inserted = [];
    supabaseClient.from.mockImplementation((table) => makeChain(table));
});

describe('POST /feedback', () => {
    it('records a thumbs-up as a feedback_up event (value +1)', async () => {
        const res = await request(app)
            .post('/feedback')
            .send({ chatId: 'c1', messageText: 'תשובה כלשהי', signal: 'up' });
        expect(res.status).toBe(200);
        expect(res.body.ok).toBe(true);
        const up = inserted.find(e => e.event_name === 'feedback_up');
        expect(up).toBeDefined();
        expect(up.event_value).toBe(1);
        expect(up.metadata.chatId).toBe('c1');
    });

    it('records a thumbs-down as feedback_down (value -1)', async () => {
        await request(app)
            .post('/feedback')
            .send({ chatId: 'c2', messageText: 'לא מדויק', signal: 'down' });
        const down = inserted.find(e => e.event_name === 'feedback_down');
        expect(down).toBeDefined();
        expect(down.event_value).toBe(-1);
    });

    it('logs a separate feedback_correction event when a correction is supplied', async () => {
        await request(app).post('/feedback').send({
            chatId: 'c3', messageText: 'תשובה', signal: 'down', correction: 'התכוונתי למשהו אחר',
        });
        expect(inserted.find(e => e.event_name === 'feedback_down')).toBeDefined();
        const corr = inserted.find(e => e.event_name === 'feedback_correction');
        expect(corr).toBeDefined();
        expect(corr.metadata.correction).toBe('התכוונתי למשהו אחר');
    });

    it('rejects an invalid signal with 400 and writes nothing', async () => {
        const res = await request(app)
            .post('/feedback')
            .send({ chatId: 'c4', messageText: 'x', signal: 'maybe' });
        expect(res.status).toBe(400);
        expect(inserted).toHaveLength(0);
    });

    it('links feedback to the intent that produced the reply (routedIntent)', async () => {
        // Simulate a prior routing decision for this chat.
        require('../../services/routeTracker').setLastRoute('routed-chat', { intent: 'weather', mode: 'fast' });
        await request(app)
            .post('/feedback')
            .send({ chatId: 'routed-chat', messageText: 'לא מה שרציתי', signal: 'down' });
        const ev = inserted.find(e => e.event_name === 'feedback_down' && e.metadata.chatId === 'routed-chat');
        expect(ev).toBeDefined();
        expect(ev.metadata.routedIntent).toBe('weather');
    });

    it('dedups rapid identical taps (second tap writes nothing new)', async () => {
        const body = { chatId: 'dedup', messageText: 'אותה הודעה', signal: 'up' };
        await request(app).post('/feedback').send(body);
        const afterFirst = inserted.length;
        const res = await request(app).post('/feedback').send(body);
        expect(res.body.deduped).toBe(true);
        expect(inserted.length).toBe(afterFirst);
    });
});

describe('/dashboard/smart-telemetry', () => {
    it('POST records a generic telemetry event', async () => {
        const res = await request(app)
            .post('/dashboard/smart-telemetry')
            .send({ event_type: 'screen_view', payload: { screen: 'home' } });
        expect(res.status).toBe(200);
        expect(res.body.ok).toBe(true);
        const ev = inserted.find(e => e.event_name === 'screen_view');
        expect(ev).toBeDefined();
        expect(ev.metadata.screen).toBe('home');
    });

    it('POST without an event name returns 400', async () => {
        const res = await request(app).post('/dashboard/smart-telemetry').send({ payload: {} });
        expect(res.status).toBe(400);
    });

    it('GET returns aggregated counts', async () => {
        const res = await request(app).get('/dashboard/smart-telemetry?user_id=default');
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('counts');
        expect(res.body).toHaveProperty('total');
    });
});
