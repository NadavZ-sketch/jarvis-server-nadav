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
jest.mock('../../agents/weatherAgent', () => ({
    runWeatherAgent: jest.fn().mockResolvedValue({ answer: 'שמש, 22°C' }),
}));
jest.mock('../../agents/newsAgent', () => ({
    runNewsAgent: jest.fn().mockResolvedValue({ answer: 'חדשות: ישראל בחדשות.' }),
}));
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn().mockResolvedValue('שלום! יש לך 2 משימות פתוחות ותזכורת בשעה 10:00.'),
    callGemma4Stream: jest.fn(),
}));

const request = require('supertest');
const { createClient } = require('@supabase/supabase-js');
const { app, cacheInvalidate } = require('../../server');

function makeChain(data = [], error = null) {
    const chain = {
        then(resolve) { return Promise.resolve({ data, error }).then(resolve); },
        catch(reject) { return Promise.resolve({ data, error }).catch(reject); },
        select: jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        upsert: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        lte:    jest.fn().mockReturnThis(),
        gte:    jest.fn().mockReturnThis(),
        lt:     jest.fn().mockReturnThis(),
        order:  jest.fn().mockReturnThis(),
        limit:  jest.fn().mockReturnThis(),
        single: jest.fn().mockResolvedValue({ data: null, error: null }),
    };
    return chain;
}

const supabaseClient = createClient.mock.results[0].value;

const MOCK_TASKS = [
    { id: 1, content: 'לגמור דוח', priority: 'high' },
    { id: 2, content: 'לקנות חלב', priority: 'normal' },
];

const MOCK_REMINDERS = [
    { id: 10, text: 'פגישה עם דני', scheduled_time: new Date(Date.now() + 60 * 60 * 1000).toISOString() },
];

beforeEach(() => {
    jest.clearAllMocks();
    cacheInvalidate('dashboard:weather');
    cacheInvalidate('dashboard:news');
    ['morning','late_morning','noon','afternoon','evening','night'].forEach(s =>
        cacheInvalidate(`dashboard:hero:${s}`)
    );
    cacheInvalidate('userProfile');

    supabaseClient.from.mockImplementation((table) => {
        if (table === 'tasks')        return makeChain(MOCK_TASKS);
        if (table === 'reminders')    return makeChain(MOCK_REMINDERS);
        if (table === 'memories')     return makeChain([{ content: 'אוהב קפה בבוקר' }]);
        if (table === 'user_profiles') return makeChain([{ id: 'u1', name: 'נדב' }]);
        return makeChain([]);
    });
});

describe('GET /dashboard-context', () => {
    it('returns 200 with heroCard and widgets', async () => {
        const res = await request(app).get('/dashboard-context');
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('heroCard');
        expect(res.body).toHaveProperty('widgets');
        expect(res.body).toHaveProperty('slot');
        expect(res.body).toHaveProperty('timestamp');
    });

    it('heroCard has text and confidence fields', async () => {
        const res = await request(app).get('/dashboard-context');
        expect(res.body.heroCard).toHaveProperty('text');
        expect(res.body.heroCard).toHaveProperty('confidence');
        expect(typeof res.body.heroCard.text).toBe('string');
    });

    it('includes tasks widget with correct structure', async () => {
        const res = await request(app).get('/dashboard-context');
        const tasksWidget = res.body.widgets.find(w => w.type === 'tasks');
        expect(tasksWidget).toBeDefined();
        expect(Array.isArray(tasksWidget.data)).toBe(true);
        expect(tasksWidget).toHaveProperty('badge');
    });

    it('includes reminders widget with correct structure', async () => {
        const res = await request(app).get('/dashboard-context');
        const remindersWidget = res.body.widgets.find(w => w.type === 'reminders');
        expect(remindersWidget).toBeDefined();
        expect(Array.isArray(remindersWidget.data)).toBe(true);
    });

    it('tasks widget shows max 3 items, badge counts the rest', async () => {
        const manyTasks = Array.from({ length: 5 }, (_, i) => ({
            id: i + 1, content: `משימה ${i + 1}`, priority: 'normal',
        }));
        supabaseClient.from.mockImplementation((table) => {
            if (table === 'tasks')        return makeChain(manyTasks);
            if (table === 'reminders')    return makeChain(MOCK_REMINDERS);
            if (table === 'memories')     return makeChain([]);
            if (table === 'user_profiles') return makeChain([]);
            return makeChain([]);
        });
        const res = await request(app).get('/dashboard-context');
        const tasksWidget = res.body.widgets.find(w => w.type === 'tasks');
        expect(tasksWidget.data.length).toBeLessThanOrEqual(3);
        expect(tasksWidget.badge).toBeGreaterThanOrEqual(2);
    });

    it('returns 200 even when Supabase has no data (cold start)', async () => {
        supabaseClient.from.mockImplementation(() => makeChain([]));
        const res = await request(app).get('/dashboard-context');
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('heroCard');
    });

    it('returns 200 when LLM call fails (fallback text used)', async () => {
        require('../../agents/models').callGemma4.mockRejectedValueOnce(new Error('LLM timeout'));
        supabaseClient.from.mockImplementation(() => makeChain([]));
        const res = await request(app).get('/dashboard-context');
        expect(res.status).toBe(200);
        expect(typeof res.body.heroCard.text).toBe('string');
        expect(res.body.heroCard.confidence).toBe(0);
    });
});
