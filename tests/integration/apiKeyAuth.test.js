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
    createClient: jest.fn().mockReturnValue({
        from: jest.fn().mockReturnValue({
            select: jest.fn().mockReturnThis(),
            eq: jest.fn().mockReturnThis(),
            maybeSingle: jest.fn().mockResolvedValue({ data: null }),
            then(fn) { return Promise.resolve({ data: [], error: null }).then(fn); },
        }),
    }),
}));
jest.mock('../../services/obsidianSync', () => ({
    initSync: jest.fn().mockResolvedValue(undefined),
    fullSyncFromDb: jest.fn().mockResolvedValue(undefined),
    appendChatMessage: jest.fn().mockResolvedValue(undefined),
    syncAll: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../services/pushService', () => ({
    init: jest.fn(),
    sendPush: jest.fn().mockResolvedValue(undefined),
    registerToken: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../services/systemLog', () => ({
    init: jest.fn(),
    logEvent: jest.fn().mockResolvedValue(undefined),
    logError: jest.fn().mockResolvedValue(undefined),
    logCritical: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../agents/router', () => ({
    classifyIntent: jest.fn(), classifyIntentWithLLM: jest.fn(),
    classifyIntentDetailed: jest.fn(), invalidateRouterCache: jest.fn(),
    loadCustomRegistry: jest.fn(),
}));
jest.mock('../../agents/taskAgent', () => ({ runTaskAgent: jest.fn() }));
jest.mock('../../agents/reminderAgent', () => ({ runReminderAgent: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({
    runMemoryAgent: jest.fn(), autoExtractMemory: jest.fn().mockResolvedValue(undefined),
    setMemoryCacheInvalidator: jest.fn(),
}));
jest.mock('../../agents/chatAgent', () => ({
    runChatAgent: jest.fn(), detectFollowUp: jest.fn().mockReturnValue(false),
    filterRelevantMemories: jest.fn(m => m), filterRelevantMemoriesAsync: jest.fn(async m => m),
    buildSystemPrompt: jest.fn(),
}));
jest.mock('../../agents/sportsAgent', () => ({ runSportsAgent: jest.fn() }));
jest.mock('../../agents/messagingAgent', () => ({ runMessagingAgent: jest.fn() }));
jest.mock('../../agents/draftAgent', () => ({ runDraftAgent: jest.fn() }));
jest.mock('../../agents/securityAgent', () => ({ runSecurityAgent: jest.fn() }));
jest.mock('../../agents/codeErrorAgent', () => ({ runCodeErrorAgent: jest.fn() }));
jest.mock('../../agents/e2eAgent', () => ({
    runE2EAgent: jest.fn(), buildClaudePrompt: jest.fn(), countsBySeverity: jest.fn(),
    computeScore: jest.fn(), persistFindings: jest.fn(),
}));
jest.mock('../../agents/weatherAgent', () => ({ runWeatherAgent: jest.fn() }));
jest.mock('../../agents/newsAgent', () => ({ runNewsAgent: jest.fn() }));
jest.mock('../../agents/shoppingAgent', () => ({ runShoppingAgent: jest.fn() }));
jest.mock('../../agents/notesAgent', () => ({ runNotesAgent: jest.fn() }));
jest.mock('../../agents/stocksAgent', () => ({ runStocksAgent: jest.fn() }));
jest.mock('../../agents/translationAgent', () => ({ runTranslationAgent: jest.fn() }));
jest.mock('../../agents/musicAgent', () => ({ runMusicAgent: jest.fn() }));
jest.mock('../../agents/calendarAgent', () => ({
    runCalendarAgent: jest.fn(), buildAuthUrl: jest.fn(), getAccessToken: jest.fn(),
}));
jest.mock('../../agents/promptAgent', () => ({ runPromptAgent: jest.fn() }));
jest.mock('../../agents/settingsAgent', () => ({ runSettingsAgent: jest.fn() }));
jest.mock('../../agents/projectAgent', () => ({
    runProjectAgent: jest.fn(), buildProjectsBriefing: jest.fn(),
}));
jest.mock('../../agents/habitAgent', () => ({ runHabitAgent: jest.fn(), computeStreak: jest.fn() }));
jest.mock('../../agents/insightAgent', () => ({
    analyzePatterns: jest.fn(), optimizeDayPlan: jest.fn(), runInsightAgent: jest.fn(),
}));
jest.mock('../../agents/manusAgent', () => ({
    runManusAgent: jest.fn(), isManusConfigured: jest.fn().mockReturnValue(false),
}));
jest.mock('../../agents/surveyAgent', () => ({
    SURVEY_QUESTIONS: [], selectSurveyQuestions: jest.fn().mockReturnValue([]),
    buildSurveyJson: jest.fn(), buildSurveySummary: jest.fn(),
    aggregateSurveys: jest.fn(), insightsFromAggregation: jest.fn(),
}));
jest.mock('../../agents/devTaskAgent', () => ({
    detectCapabilityGap: jest.fn(), savePendingGap: jest.fn(),
    handleConfirmation: jest.fn().mockResolvedValue(null),
}));
jest.mock('../../agents/orchestratorAgent', () => ({ runOrchestratorAgent: jest.fn() }));

const request = require('supertest');

describe('API key auth middleware', () => {
    const TEST_KEY = 'test-secret-key-123';

    beforeAll(() => {
        process.env.JARVIS_API_KEY = TEST_KEY;
    });

    afterAll(() => {
        delete process.env.JARVIS_API_KEY;
    });

    test('GET /health is exempt — always accessible', async () => {
        const { app } = require('../../server');
        const res = await request(app).get('/health');
        expect(res.status).toBe(200);
        expect(res.body.ok).toBe(true);
    });

    test('request without x-jarvis-key header returns 401', async () => {
        const { app } = require('../../server');
        const res = await request(app).get('/stats');
        expect(res.status).toBe(401);
        expect(res.body.ok).toBe(false);
    });

    test('request with correct x-jarvis-key header is allowed', async () => {
        const { app } = require('../../server');
        const res = await request(app)
            .get('/health')
            .set('x-jarvis-key', TEST_KEY);
        expect(res.status).toBe(200);
    });
});
