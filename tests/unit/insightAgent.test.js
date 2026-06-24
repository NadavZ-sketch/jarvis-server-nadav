jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const {
    runInsightAgent, analyzePatterns,
    detectReportPeriod, buildPeriodStats, generatePeriodReport,
} = require('../../agents/insightAgent');

beforeEach(() => jest.clearAllMocks());

function daysAgoISO(n) {
    return new Date(Date.now() - n * 86400000).toISOString();
}

// Minimal repos mock for runInsightAgent (main path).
function makeRepos(overrides = {}) {
    return {
        chat:      { recentForSearch: jest.fn().mockResolvedValue([]) },
        tasks:     { allBasic: jest.fn().mockResolvedValue([]), allForReport: jest.fn().mockResolvedValue([]) },
        memories:  { allForInsight: jest.fn().mockResolvedValue([]) },
        reminders: { listForInsight: jest.fn().mockResolvedValue([]) },
        contacts:  { listByName: jest.fn().mockResolvedValue([]) },
        habits:    { listActive: jest.fn().mockResolvedValue([]), doneDates: jest.fn().mockResolvedValue([]) },
        ...overrides,
    };
}

describe('analyzePatterns', () => {
    const emptyData = { chats: [], tasks: [], memories: [], reminders: [], contacts: [] };

    test('does not crash when a chat row has null text (regression)', () => {
        const data = {
            ...emptyData,
            chats: [
                { role: 'user', text: null, created_at: '2026-05-21T09:00:00Z' },
                { role: 'user', text: 'תוסיף משימה', created_at: '2026-05-21T09:01:00Z' },
            ],
        };
        expect(() => analyzePatterns(data)).not.toThrow();
        const out = analyzePatterns(data);
        expect(out.totalMessages).toBe(2);
        expect(out.recentSample).toEqual(['', 'תוסיף משימה']);
    });

    test('counts feature usage and pending tasks/memories', () => {
        const data = {
            ...emptyData,
            chats: [
                { role: 'user', text: 'תזכיר לי לקנות חלב', created_at: '2026-05-21T08:00:00Z' },
                { role: 'user', text: 'מה קורה בכדורגל', created_at: '2026-05-21T20:00:00Z' },
                { role: 'jarvis', text: 'בבקשה', created_at: '2026-05-21T08:00:05Z' },
            ],
            tasks: [{ content: 'a' }, { content: 'b' }],
            memories: [{ content: 'm' }],
            reminders: [{ fired: true }, { fired: false }],
            contacts: [{ name: 'דנה' }],
        };
        const out = analyzePatterns(data);
        expect(out.totalMessages).toBe(2); // jarvis rows excluded
        expect(out.pendingTasks).toBe(2);
        expect(out.memoriesCount).toBe(1);
        expect(out.contactsCount).toBe(1);
        expect(out.firedReminders).toBe(1);
        expect(out.activeReminders).toBe(1);
        expect(out.featureUsage['תזכורות']).toBe(1);
        expect(out.featureUsage['כדורגל / ספורט']).toBe(1);
    });

    test('rows without created_at are ignored for time buckets', () => {
        const data = { ...emptyData, chats: [{ role: 'user', text: 'שלום' }] };
        const out = analyzePatterns(data);
        const totalBucketed = Object.values(out.buckets).reduce((a, b) => a + b, 0);
        expect(totalBucketed).toBe(0);
        expect(out.totalMessages).toBe(1);
    });
});

describe('runInsightAgent', () => {
    it('returns insights with empty data', async () => {
        callGemma4.mockResolvedValue('אין מספיק נתונים לניתוח עדיין.');
        const result = await runInsightAgent('תן לי תובנות', makeRepos(), false, {});
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('handles repo errors gracefully', async () => {
        const repos = makeRepos({
            chat: { recentForSearch: jest.fn().mockRejectedValue(new Error('DB error')) },
        });
        callGemma4.mockResolvedValue('לא ניתן לטעון נתונים.');
        const result = await runInsightAgent('דוח שימוש', repos, false, {});
        expect(result).toHaveProperty('answer');
    });

    it('handles LLM failure', async () => {
        callGemma4.mockRejectedValue(new Error('LLM unavailable'));
        const repos = makeRepos({
            chat: { recentForSearch: jest.fn().mockResolvedValue([
                { role: 'user', text: 'שלום', created_at: '2026-05-21T09:00:00Z' },
                { role: 'user', text: 'מה קורה', created_at: '2026-05-21T10:00:00Z' },
                { role: 'user', text: 'ספר לי', created_at: '2026-05-21T11:00:00Z' },
            ]) },
        });
        const result = await runInsightAgent('תובנות', repos, false, {});
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });
});

describe('detectReportPeriod', () => {
    test('detects weekly and monthly, null otherwise', () => {
        expect(detectReportPeriod('תן לי סיכום שבועי')).toBe('week');
        expect(detectReportPeriod('דוח חודשי בבקשה')).toBe('month');
        expect(detectReportPeriod('תן לי תובנות')).toBeNull();
    });
});

describe('buildPeriodStats', () => {
    test('computes completion rate, period messages and habit streaks', () => {
        const data = {
            chats: [
                { role: 'user', text: 'היי', created_at: daysAgoISO(1) },
                { role: 'user', text: 'מה קורה', created_at: daysAgoISO(2) },
                { role: 'user', text: 'ישן', created_at: daysAgoISO(40) }, // outside week window
            ],
            tasks: [
                { content: 'a', done: true,  created_at: daysAgoISO(1) },
                { content: 'b', done: false, created_at: daysAgoISO(2) },
                { content: 'c', done: true,  created_at: daysAgoISO(50) },
            ],
            reminders: [{ fired: true, scheduled_time: daysAgoISO(1) }],
            habits: [{ name: 'ריצה', logDates: [
                new Date().toISOString().slice(0, 10),
            ] }],
        };
        const stats = buildPeriodStats(data, 'week');
        expect(stats.messagesInPeriod).toBe(2);          // 40-day-old msg excluded
        expect(stats.tasksDone).toBe(2);
        expect(stats.tasksOpen).toBe(1);
        expect(stats.completionRate).toBe(67);           // 2/3 ≈ 67%
        expect(stats.tasksCreated).toBe(2);              // within 7 days
        expect(stats.remindersFired).toBe(1);
        expect(stats.habits[0]).toEqual({ name: 'ריצה', streak: 1 });
    });
});

describe('generatePeriodReport', () => {
    function makeReposForReport(tableData) {
        return {
            chat: {
                recentForSearch: jest.fn().mockResolvedValue(tableData.chat_history || []),
            },
            tasks: {
                allForReport: jest.fn().mockResolvedValue(tableData.tasks || []),
            },
            reminders: {
                listForInsight: jest.fn().mockResolvedValue(tableData.reminders || []),
            },
            habits: {
                listActive: jest.fn().mockResolvedValue([]),
                doneDates: jest.fn().mockResolvedValue([]),
            },
        };
    }

    test('assembles a weekly report with facts and narrative', async () => {
        callGemma4.mockResolvedValue('שבוע מצוין, המשך כך!');
        const repos = makeReposForReport({
            chat_history: [{ role: 'user', text: 'היי', created_at: daysAgoISO(1) }],
            tasks: [{ content: 'a', done: true, created_at: daysAgoISO(1) }],
            reminders: [],
        });
        const result = await generatePeriodReport(repos, 'week', { userName: 'נדב' });
        expect(result.answer).toContain('הסיכום השבועי');
        expect(result.answer).toContain('שבוע מצוין');
    });
});
