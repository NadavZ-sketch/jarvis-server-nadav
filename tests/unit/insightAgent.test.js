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
const { runInsightAgent } = require('../../agents/insightAgent');

beforeEach(() => jest.clearAllMocks());

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
