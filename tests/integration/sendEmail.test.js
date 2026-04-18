'use strict';
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('@supabase/supabase-js', () => ({
    createClient: jest.fn().mockReturnValue({ from: jest.fn() }),
}));
jest.mock('google-tts-api', () => ({
    getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: 'bW9jaw==' }]),
}));

const mockSendMail = jest.fn().mockResolvedValue({ messageId: 'mock-id' });
jest.mock('nodemailer', () => ({
    createTransport: jest.fn().mockReturnValue({ sendMail: mockSendMail }),
}));

// Stub all agents so server.js loads without issues
jest.mock('../../agents/router', () => ({ classifyIntent: jest.fn() }));
jest.mock('../../agents/taskAgent', () => ({ runTaskAgent: jest.fn() }));
jest.mock('../../agents/reminderAgent', () => ({ runReminderAgent: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ runMemoryAgent: jest.fn() }));
jest.mock('../../agents/chatAgent', () => ({ runChatAgent: jest.fn() }));
jest.mock('../../agents/sportsAgent', () => ({ runSportsAgent: jest.fn() }));
jest.mock('../../agents/messagingAgent', () => ({ runMessagingAgent: jest.fn() }));
jest.mock('../../agents/draftAgent', () => ({ runDraftAgent: jest.fn() }));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { app } = require('../../server');

function makeChain(data = [], error = null) {
    const chain = {
        then(res) { return Promise.resolve({ data, error }).then(res); },
        catch(rej) { return Promise.resolve({ data, error }).catch(rej); },
        select: jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        limit:  jest.fn().mockReturnThis(),
    };
    return chain;
}

const supabaseClient = createClient.mock.results[0].value;

beforeEach(() => {
    jest.clearAllMocks();
    supabaseClient.from.mockImplementation(() => makeChain());
});

describe('POST /send-email', () => {
    test('missing to field → 400', async () => {
        const res = await request(app)
            .post('/send-email')
            .send({ message: 'hello' });
        expect(res.status).toBe(400);
        expect(res.body.ok).toBe(false);
    });

    test('missing message field → 400', async () => {
        const res = await request(app)
            .post('/send-email')
            .send({ to: 'test@example.com' });
        expect(res.status).toBe(400);
        expect(res.body.ok).toBe(false);
    });

    test('empty body → 400', async () => {
        const res = await request(app)
            .post('/send-email')
            .send({});
        expect(res.status).toBe(400);
        expect(res.body.ok).toBe(false);
    });

    test('valid request → 200 and sends email', async () => {
        const res = await request(app)
            .post('/send-email')
            .send({ to: 'mom@example.com', message: 'שלום אמא' });
        expect(res.status).toBe(200);
        expect(res.body.ok).toBe(true);
        expect(mockSendMail).toHaveBeenCalledWith(
            expect.objectContaining({ to: 'mom@example.com', text: 'שלום אמא' })
        );
    });

    test('sendMail throws → 500', async () => {
        mockSendMail.mockRejectedValueOnce(new Error('SMTP error'));
        const res = await request(app)
            .post('/send-email')
            .send({ to: 'x@y.com', message: 'hi' });
        expect(res.status).toBe(500);
        expect(res.body.ok).toBe(false);
    });
});
