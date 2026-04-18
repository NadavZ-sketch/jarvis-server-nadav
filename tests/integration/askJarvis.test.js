'use strict';
// All jest.mock calls must come before any require()
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({
    createTransport: jest.fn().mockReturnValue({
        sendMail: jest.fn().mockResolvedValue({ messageId: 'mock-id' }),
    }),
}));
jest.mock('google-tts-api', () => ({
    getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: 'bW9jaw==' }]),
}));
jest.mock('@supabase/supabase-js', () => ({
    createClient: jest.fn().mockReturnValue({ from: jest.fn() }),
}));
jest.mock('../../agents/router', () => ({ classifyIntent: jest.fn() }));
jest.mock('../../agents/taskAgent', () => ({ runTaskAgent: jest.fn() }));
jest.mock('../../agents/reminderAgent', () => ({ runReminderAgent: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ runMemoryAgent: jest.fn() }));
jest.mock('../../agents/chatAgent', () => ({ runChatAgent: jest.fn() }));
jest.mock('../../agents/sportsAgent', () => ({ runSportsAgent: jest.fn() }));
jest.mock('../../agents/musicAgent', () => ({ runMusicAgent: jest.fn() }));
jest.mock('../../agents/messagingAgent', () => ({ runMessagingAgent: jest.fn() }));
jest.mock('../../agents/draftAgent', () => ({ runDraftAgent: jest.fn() }));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { classifyIntent } = require('../../agents/router');
const { runTaskAgent } = require('../../agents/taskAgent');
const { runChatAgent } = require('../../agents/chatAgent');
const { runMessagingAgent } = require('../../agents/messagingAgent');
const { runMusicAgent } = require('../../agents/musicAgent');
const { app } = require('../../server');

function makeChain(data = [], error = null) {
    const chain = {
        then(res) { return Promise.resolve({ data, error }).then(res); },
        catch(rej) { return Promise.resolve({ data, error }).catch(rej); },
        select:  jest.fn().mockReturnThis(),
        insert:  jest.fn().mockReturnThis(),
        update:  jest.fn().mockReturnThis(),
        delete:  jest.fn().mockReturnThis(),
        eq:      jest.fn().mockReturnThis(),
        order:   jest.fn().mockReturnThis(),
        limit:   jest.fn().mockReturnThis(),
        in:      jest.fn().mockReturnThis(),
        lte:     jest.fn().mockReturnThis(),
    };
    return chain;
}

const supabaseClient = createClient.mock.results[0].value;

beforeEach(() => {
    jest.clearAllMocks();
    supabaseClient.from.mockImplementation(() => makeChain());
});

describe('POST /ask-jarvis', () => {
    test('routes to task agent and returns answer', async () => {
        classifyIntent.mockReturnValue('task');
        runTaskAgent.mockResolvedValue({ answer: 'הוספתי את המשימה' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'הוסף משימה לקנות חלב' });

        expect(res.status).toBe(200);
        expect(res.body.answer).toBe('הוספתי את המשימה');
        expect(runTaskAgent).toHaveBeenCalledWith(
            'הוסף משימה לקנות חלב',
            expect.anything(),
            expect.anything()
        );
    });

    test('routes to chat agent by default', async () => {
        classifyIntent.mockReturnValue('chat');
        runChatAgent.mockResolvedValue({ answer: 'שלום!' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'שלום' });

        expect(res.status).toBe(200);
        expect(res.body.answer).toBe('שלום!');
    });

    test('image bypasses classifyIntent and goes to chat agent', async () => {
        runChatAgent.mockResolvedValue({ answer: 'רואה חתול' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'מה יש בתמונה?', image: 'iVBORbase64data' });

        expect(res.status).toBe(200);
        expect(classifyIntent).not.toHaveBeenCalled();
        expect(runChatAgent).toHaveBeenCalled();
    });

    test('response includes audio field', async () => {
        classifyIntent.mockReturnValue('chat');
        runChatAgent.mockResolvedValue({ answer: 'שלום!' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'שלום' });

        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('audio');
    });

    test('response includes action field when agent returns one', async () => {
        classifyIntent.mockReturnValue('messaging');
        runMessagingAgent.mockResolvedValue({
            answer: 'ניסחתי הודעה',
            action: { type: 'whatsapp', phone: '972501234567', message: 'שלום!' },
        });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'שלח ווצאפ לרון' });

        expect(res.status).toBe(200);
        expect(res.body.action.type).toBe('whatsapp');
    });

    test('agent throws → returns 500 with Hebrew error', async () => {
        classifyIntent.mockReturnValue('chat');
        runChatAgent.mockRejectedValue(new Error('boom'));

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'שלום' });

        expect(res.status).toBe(500);
        expect(res.body.answer).toBe('שגיאת מערכת פנימית.');
    });

    test('routes to music agent and returns action with youtube url', async () => {
        classifyIntent.mockReturnValue('music');
        runMusicAgent.mockResolvedValue({
            answer: 'הנה מוזיקת ג\'אז מרגיעה',
            action: { type: 'music', url: 'https://music.youtube.com/search?q=jazz' },
        });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'מוזיקה רגועה לעבודה' });

        expect(res.status).toBe(200);
        expect(res.body.action.type).toBe('music');
        expect(res.body.action.url).toContain('music.youtube.com');
        expect(runMusicAgent).toHaveBeenCalled();
    });

    test('empty command is handled without crashing', async () => {
        classifyIntent.mockReturnValue('chat');
        runChatAgent.mockResolvedValue({ answer: 'מה?' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: '' });

        expect(res.status).toBe(200);
    });
});
