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
jest.mock('../../agents/router', () => {
    const classifyIntent = jest.fn();
    return {
        classifyIntent,
        classifyIntentDetailed: jest.fn((msg) => {
            const intent = classifyIntent(msg);
            return { intent, matches: intent === 'chat' ? [] : [intent], ambiguous: false };
        }),
        classifyIntentWithLLM: jest.fn(),
        invalidateRouterCache: jest.fn(),
        loadCustomRegistry: jest.fn().mockReturnValue([]),
        loadRouterOverrides: jest.fn().mockReturnValue([]),
        invalidateOverridesCache: jest.fn(),
    };
});
jest.mock('../../agents/models', () => ({
    callGemma4Stream: jest.fn(async (_msgs, _useLocal, onChunk) => { onChunk('שלום '); onChunk('עולם?'); }),
    callGemma4: jest.fn().mockResolvedValue(''),
    providerContext: { run: (_ctx, fn) => fn() },
    getCurrentProvider: jest.fn(() => 'groq'),
    LocalModelError: class LocalModelError extends Error {},
}));
jest.mock('../../agents/chatAgent', () => ({
    runChatAgent: jest.fn().mockResolvedValue({ answer: 'fallback' }),
    detectFollowUp: jest.fn().mockReturnValue(false),
    filterRelevantMemories: jest.fn(m => m),
    filterRelevantMemoriesAsync: jest.fn(async m => m),
    rankMemories: jest.fn().mockResolvedValue([]),
    buildSystemPrompt: jest.fn().mockReturnValue('SYSTEM'),
}));
jest.mock('../../services/memoryContext', () => ({ loadForRequest: jest.fn().mockResolvedValue({ memories: [], pending: null }), formatAsText: jest.fn().mockReturnValue(''), savePendingData: jest.fn().mockResolvedValue({ saved: true, content: '' }), confirmPending: jest.fn().mockResolvedValue({ saved: false }), getPending: jest.fn().mockReturnValue(null), clearPending: jest.fn(), setPending: jest.fn(), invalidateCache: jest.fn() }));
jest.mock('../../agents/weatherAgent', () => ({ runWeatherAgent: jest.fn().mockResolvedValue({ answer: 'שמשי היום ☀️' }) }));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { classifyIntent } = require('../../agents/router');
const { callGemma4Stream } = require('../../agents/models');
const { app } = require('../../server');

function makeChain(data = [], error = null) {
    const chain = {
        then(res) { return Promise.resolve({ data, error }).then(res); },
        catch(rej) { return Promise.resolve({ data, error }).catch(rej); },
        select: jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        eq: jest.fn().mockReturnThis(),
        in: jest.fn().mockReturnThis(),
        order: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
    };
    return chain;
}

const supabaseClient = createClient.mock.results[0].value;

beforeEach(() => {
    jest.clearAllMocks();
    supabaseClient.from.mockImplementation(() => makeChain());
});

// Parse an SSE body into the array of JSON `data:` payloads.
function parseSse(text) {
    return text.split('\n\n')
        .map(b => b.replace(/^data: /, '').trim())
        .filter(Boolean)
        .map(j => { try { return JSON.parse(j); } catch { return null; } })
        .filter(Boolean);
}

describe('POST /stream-jarvis', () => {
    test('streams chat token chunks via callGemma4Stream as SSE frames', async () => {
        classifyIntent.mockReturnValue('chat');

        const res = await request(app)
            .post('/stream-jarvis')
            .send({ command: 'ספר לי בדיחה', chatId: 'sse-1' });

        expect(res.status).toBe(200);
        expect(res.headers['content-type']).toMatch(/text\/event-stream/);
        expect(callGemma4Stream).toHaveBeenCalled();

        const frames = parseSse(res.text);
        const chunks = frames.filter(f => f.chunk).map(f => f.chunk).join('');
        expect(chunks).toContain('שלום');
        expect(chunks).toContain('עולם');
        expect(frames.some(f => f.done === true)).toBe(true);
    });

    test('rejects an over-long message with an error frame', async () => {
        classifyIntent.mockReturnValue('chat');
        const res = await request(app)
            .post('/stream-jarvis')
            .send({ command: 'x'.repeat(5001), chatId: 'sse-2' });

        expect(res.status).toBe(200);
        const frames = parseSse(res.text);
        expect(frames.some(f => f.error)).toBe(true);
        expect(callGemma4Stream).not.toHaveBeenCalled();
    });

    test('non-chat agent runs to completion and is sent as a single done chunk', async () => {
        classifyIntent.mockReturnValue('weather');
        const res = await request(app)
            .post('/stream-jarvis')
            .send({ command: 'מה מזג האוויר?', chatId: 'sse-3' });

        expect(res.status).toBe(200);
        const frames = parseSse(res.text);
        const done = frames.find(f => f.done === true);
        expect(done.chunk).toContain('שמשי');
        expect(callGemma4Stream).not.toHaveBeenCalled();
    });
});
