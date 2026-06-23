'use strict';

jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({ createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn() }) }));
jest.mock('openai', () => ({ OpenAI: jest.fn().mockImplementation(() => ({ audio: { transcriptions: { create: jest.fn() } } })), toFile: jest.fn() }));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: '' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({ initSync: jest.fn(), fullSyncFromDb: jest.fn(), appendChatMessage: jest.fn(), syncAll: jest.fn(), dbToVault: jest.fn(), removeFromVault: jest.fn() }));
jest.mock('../../services/weatherSource', () => ({ getWeatherSummary: jest.fn().mockResolvedValue(null) }));
jest.mock('../../services/newsSource', () => ({ getNewsSummary: jest.fn().mockResolvedValue(null), getTopicHeadlines: jest.fn().mockResolvedValue(null) }));
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn(), callGemma4Stream: jest.fn(), callGeminiWithSearch: jest.fn(), callGeminiVision: jest.fn(), GEMINI_URL: '' }));
jest.mock('../../services/pineconeMemory', () => ({
    upsertMemory: jest.fn().mockResolvedValue(true),
    searchMemories: jest.fn().mockResolvedValue(null),
    findSimilarMemory: jest.fn().mockResolvedValue(null),
    deleteMemory: jest.fn().mockResolvedValue(),
    isReady: jest.fn().mockReturnValue(false),
    syncFromSupabase: jest.fn(),
    initPinecone: jest.fn(),
}));
// memoryContext owns pending state; mock it so tests can control lookup results.
jest.mock('../../services/memoryContext', () => ({
    loadForRequest: jest.fn().mockResolvedValue({ memories: [], pending: null }),
    formatAsText: jest.fn().mockReturnValue(''),
    savePendingData: jest.fn().mockResolvedValue({ saved: true, content: '[fact] test' }),
    confirmPending: jest.fn().mockResolvedValue({ saved: false }),
    getPending: jest.fn().mockReturnValue(null),
    clearPending: jest.fn(),
    setPending: jest.fn(),
    invalidateCache: jest.fn(),
}));

const request = require('supertest');
const memoryAgent = require('../../agents/memoryAgent');
const { app } = require('../../server');

describe('POST /memories/confirm', () => {
    beforeEach(() => jest.clearAllMocks());

    it('returns 400 when chatId missing', async () => {
        const res = await request(app).post('/memories/confirm').send({ action: 'save' });
        expect(res.status).toBe(400);
    });

    it('returns 404 when no pending memory for chatId', async () => {
        jest.spyOn(memoryAgent, 'getPendingMemory').mockReturnValue(null);
        const res = await request(app).post('/memories/confirm').send({ chatId: 'chat-x', action: 'save' });
        expect(res.status).toBe(404);
    });

    it('action=discard clears pending and returns ok', async () => {
        const clearSpy = jest.spyOn(memoryAgent, 'clearPendingMemory').mockImplementation(() => {});
        jest.spyOn(memoryAgent, 'getPendingMemory').mockReturnValue({ content: '[fact] test', type: 'fact' });
        const res = await request(app).post('/memories/confirm').send({ chatId: 'chat-1', action: 'discard' });
        expect(res.status).toBe(200);
        expect(res.body.ok).toBe(true);
        expect(clearSpy).toHaveBeenCalledWith('chat-1');
    });
});
