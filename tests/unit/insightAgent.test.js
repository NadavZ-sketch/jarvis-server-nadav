const mockSupabase = {
    from: jest.fn().mockReturnThis(),
    select: jest.fn().mockReturnThis(),
    eq: jest.fn().mockReturnThis(),
    order: jest.fn().mockReturnThis(),
    limit: jest.fn().mockResolvedValue({ data: [], error: null }),
};
mockSupabase.from.mockReturnValue(mockSupabase);

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runInsightAgent, analyzePatterns } = require('../../agents/insightAgent');

beforeEach(() => jest.clearAllMocks());

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
        const result = await runInsightAgent('תן לי תובנות', mockSupabase, false, {});
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('handles DB error gracefully', async () => {
        mockSupabase.limit.mockResolvedValue({ data: null, error: new Error('DB error') });
        callGemma4.mockResolvedValue('לא ניתן לטעון נתונים.');
        const result = await runInsightAgent('דוח שימוש', mockSupabase, false, {});
        expect(result).toHaveProperty('answer');
    });

    it('handles LLM failure', async () => {
        callGemma4.mockRejectedValue(new Error('LLM unavailable'));
        const result = await runInsightAgent('תובנות', mockSupabase, false, {});
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });
});
