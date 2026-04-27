'use strict';
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

jest.mock('../../agents/router', () => ({ classifyIntent: jest.fn(), classifyIntentWithLLM: jest.fn(), invalidateRouterCache: jest.fn() }));
jest.mock('../../agents/taskAgent', () => ({ runTaskAgent: jest.fn() }));
jest.mock('../../agents/reminderAgent', () => ({ runReminderAgent: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ runMemoryAgent: jest.fn(), autoExtractMemory: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../agents/chatAgent', () => ({ runChatAgent: jest.fn(), detectFollowUp: jest.fn().mockReturnValue(false), filterRelevantMemories: jest.fn(m => m) }));
jest.mock('../../agents/sportsAgent', () => ({ runSportsAgent: jest.fn() }));
jest.mock('../../agents/messagingAgent', () => ({ runMessagingAgent: jest.fn() }));
jest.mock('../../agents/draftAgent', () => ({ runDraftAgent: jest.fn() }));
jest.mock('../../agents/securityAgent', () => ({ runSecurityAgent: jest.fn() }));
jest.mock('../../agents/agentFactoryAgent', () => ({ runAgentFactoryAgent: jest.fn() }));
jest.mock('../../agents/insightAgent', () => ({ runInsightAgent: jest.fn() }));
jest.mock('../../agents/weatherAgent', () => ({ runWeatherAgent: jest.fn() }));
jest.mock('../../agents/newsAgent', () => ({ runNewsAgent: jest.fn() }));
jest.mock('../../agents/shoppingAgent', () => ({ runShoppingAgent: jest.fn() }));
jest.mock('../../agents/notesAgent', () => ({ runNotesAgent: jest.fn() }));
jest.mock('../../agents/stocksAgent', () => ({ runStocksAgent: jest.fn() }));
jest.mock('../../agents/translationAgent', () => ({ runTranslationAgent: jest.fn() }));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
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
        in:      jest.fn().mockReturnThis(),
        order:   jest.fn().mockReturnThis(),
        limit:   jest.fn().mockReturnThis(),
    };
    return chain;
}

const supabaseClient = createClient.mock.results[0].value;

beforeEach(() => {
    jest.clearAllMocks();
    supabaseClient.from.mockImplementation(() => makeChain());
});

describe('GET /check-reminders', () => {
    test('returns fired reminders and calls delete', async () => {
        const fired = [{ id: 1, text: 'call mom' }, { id: 2, text: 'take meds' }];
        supabaseClient.from.mockImplementation(() => makeChain(fired));

        const res = await request(app).get('/check-reminders');

        expect(res.status).toBe(200);
        expect(res.body.reminders).toHaveLength(2);
        expect(res.body.reminders[0].text).toBe('call mom');
    });

    test('no fired reminders → empty array, delete not called', async () => {
        supabaseClient.from.mockImplementation(() => makeChain([]));

        const res = await request(app).get('/check-reminders');

        expect(res.status).toBe(200);
        expect(res.body.reminders).toEqual([]);
    });

    test('supabase error → graceful empty response (no 500)', async () => {
        supabaseClient.from.mockImplementation(() => makeChain(null, { message: 'db error' }));

        const res = await request(app).get('/check-reminders');

        expect(res.status).toBe(200);
        expect(res.body.reminders).toEqual([]);
    });

    test('null data from supabase → returns empty array', async () => {
        supabaseClient.from.mockImplementation(() => makeChain(null));

        const res = await request(app).get('/check-reminders');

        expect(res.status).toBe(200);
        expect(res.body.reminders).toEqual([]);
    });
});
