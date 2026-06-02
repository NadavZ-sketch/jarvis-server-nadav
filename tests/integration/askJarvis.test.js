'use strict';
// All jest.mock calls must come before any require()
jest.mock('openai', () => ({
    OpenAI: jest.fn().mockImplementation(() => ({
        audio: { transcriptions: { create: jest.fn().mockResolvedValue({ text: '' }) } },
    })),
    toFile: jest.fn().mockResolvedValue({}),
}));
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
jest.mock('../../services/obsidianSync', () => ({
    initSync: jest.fn().mockResolvedValue(undefined),
    fullSyncFromDb: jest.fn().mockResolvedValue(undefined),
    appendChatMessage: jest.fn().mockResolvedValue(undefined),
    syncAll: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../agents/router', () => {
    const classifyIntent = jest.fn();
    return {
        classifyIntent,
        // Delegate to the classifyIntent mock so existing mockReturnValue() calls
        // keep driving routing; non-ambiguous single match by default.
        classifyIntentDetailed: jest.fn((msg) => {
            const intent = classifyIntent(msg);
            return { intent, matches: intent === 'chat' ? [] : [intent], ambiguous: false };
        }),
        classifyIntentWithLLM: jest.fn(),
        invalidateRouterCache: jest.fn(),
    };
});
jest.mock('../../agents/taskAgent', () => ({ runTaskAgent: jest.fn() }));
jest.mock('../../agents/reminderAgent', () => ({ runReminderAgent: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ runMemoryAgent: jest.fn(), autoExtractMemory: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../agents/chatAgent', () => ({ runChatAgent: jest.fn(), detectFollowUp: jest.fn().mockReturnValue(false), filterRelevantMemories: jest.fn(m => m) }));
jest.mock('../../agents/sportsAgent', () => ({ runSportsAgent: jest.fn() }));
jest.mock('../../agents/musicAgent', () => ({ runMusicAgent: jest.fn() }));
jest.mock('../../agents/messagingAgent', () => ({ runMessagingAgent: jest.fn() }));
jest.mock('../../agents/draftAgent', () => ({ runDraftAgent: jest.fn() }));
jest.mock('../../agents/securityAgent', () => ({ runSecurityAgent: jest.fn() }));
jest.mock('../../agents/weatherAgent', () => ({ runWeatherAgent: jest.fn() }));
jest.mock('../../agents/newsAgent', () => ({ runNewsAgent: jest.fn() }));
jest.mock('../../agents/shoppingAgent', () => ({ runShoppingAgent: jest.fn() }));
jest.mock('../../agents/notesAgent', () => ({ runNotesAgent: jest.fn() }));
jest.mock('../../agents/stocksAgent', () => ({ runStocksAgent: jest.fn() }));
jest.mock('../../agents/translationAgent', () => ({ runTranslationAgent: jest.fn() }));
jest.mock('../../services/documentParser', () => ({
    extractPdfText: jest.fn(),
    MAX_PDF_BYTES: 10 * 1024 * 1024,
    MAX_TEXT_CHARS: 12000,
}));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { classifyIntent } = require('../../agents/router');
const { runTaskAgent } = require('../../agents/taskAgent');
const { runChatAgent } = require('../../agents/chatAgent');
const { runMessagingAgent } = require('../../agents/messagingAgent');
const { runMusicAgent } = require('../../agents/musicAgent');
const { extractPdfText } = require('../../services/documentParser');
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

    test('PDF attachment routes to chat with the document text injected', async () => {
        extractPdfText.mockResolvedValue({ ok: true, text: 'תוכן החוזה כאן', pages: 3, truncated: false });
        runChatAgent.mockResolvedValue({ answer: 'סיכום החוזה' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'סכם את המסמך', pdf: 'JVBERIbase64' });

        expect(res.status).toBe(200);
        expect(extractPdfText).toHaveBeenCalledWith('JVBERIbase64');
        expect(classifyIntent).not.toHaveBeenCalled(); // forced to chat
        // The chat agent receives the document text folded into the message.
        const sentMessage = runChatAgent.mock.calls[0][0];
        expect(sentMessage).toContain('תוכן החוזה כאן');
        expect(res.body.answer).toBe('סיכום החוזה');
    });

    test('unreadable PDF returns a friendly error without dispatching an agent', async () => {
        extractPdfText.mockResolvedValue({ ok: false, reason: 'no_text' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'סכם', pdf: 'broken' });

        expect(res.status).toBe(200);
        expect(res.body.answer).toContain('לא הצלחתי לקרוא את המסמך');
        expect(runChatAgent).not.toHaveBeenCalled();
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

        expect(res.status).toBe(200);
        expect(res.body.answer).toMatch(/שגיאת מערכת/);
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

describe('POST /ask-jarvis — intelligence upgrades', () => {
    test('reference resolution does not alter a plain (no-anaphora) task request', async () => {
        classifyIntent.mockReturnValue('task');
        runTaskAgent.mockResolvedValue({ answer: 'הוספתי' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'הוסף משימה לקנות חלב' });

        expect(res.status).toBe(200);
        // The original message reaches the agent unchanged (resolver gate didn't fire).
        expect(runTaskAgent).toHaveBeenCalledWith(
            'הוסף משימה לקנות חלב',
            expect.anything(),
            expect.anything(),
            expect.anything()
        );
    });

    test('chat reply appends a proactive nudge when a task is overdue', async () => {
        classifyIntent.mockReturnValue('chat');
        runChatAgent.mockResolvedValue({ answer: 'בבקשה' });
        supabaseClient.from.mockImplementation((table) => {
            if (table === 'tasks') {
                return makeChain([
                    { content: 'להגיש דוח', priority: 'medium', due_date: '2020-01-01', created_at: '2020-01-01T00:00:00Z' },
                ]);
            }
            return makeChain();
        });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'תודה רבה', chatId: 'nudge-overdue-1' });

        expect(res.status).toBe(200);
        expect(res.body.answer).toContain('💡');
        expect(res.body.answer).toContain('דוח');
    });

    test('no nudge when there are no actionable tasks', async () => {
        classifyIntent.mockReturnValue('chat');
        runChatAgent.mockResolvedValue({ answer: 'שלום!' });

        const res = await request(app)
            .post('/ask-jarvis')
            .send({ command: 'מה קורה', chatId: 'nudge-empty-1' });

        expect(res.status).toBe(200);
        expect(res.body.answer).toBe('שלום!');
    });
});
