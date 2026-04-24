const mockSupabase = {
    from: jest.fn().mockReturnThis(),
    insert: jest.fn().mockResolvedValue({ error: null }),
    select: jest.fn().mockReturnThis(),
    ilike: jest.fn().mockReturnThis(),
    delete: jest.fn().mockReturnThis(),
    order: jest.fn().mockReturnThis(),
    limit: jest.fn().mockResolvedValue({ data: [], error: null }),
};
mockSupabase.from.mockReturnValue(mockSupabase);

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runShoppingAgent } = require('../../agents/shoppingAgent');

beforeEach(() => jest.clearAllMocks());

describe('runShoppingAgent', () => {
    it('adds item to shopping list', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'add', item: 'חלב' }));
        mockSupabase.insert.mockResolvedValue({ error: null });
        const result = await runShoppingAgent('הוסף חלב לרשימת הקניות', mockSupabase, false);
        expect(result).toHaveProperty('answer');
    });

    it('shows shopping list', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list' }));
        mockSupabase.limit.mockResolvedValue({ data: [{ item: 'חלב' }, { item: 'לחם' }], error: null });
        const result = await runShoppingAgent('מה ברשימת הקניות?', mockSupabase, false);
        expect(result).toHaveProperty('answer');
    });

    it('handles LLM parse failure gracefully', async () => {
        callGemma4.mockResolvedValue('not valid json');
        const result = await runShoppingAgent('הוסף ביצים', mockSupabase, false);
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });
});
