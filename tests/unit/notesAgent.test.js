const mockSupabase = {
    from: jest.fn().mockReturnThis(),
    insert: jest.fn().mockResolvedValue({ error: null }),
    select: jest.fn().mockReturnThis(),
    or: jest.fn().mockReturnThis(),
    ilike: jest.fn().mockReturnThis(),
    eq: jest.fn().mockReturnThis(),
    delete: jest.fn().mockReturnThis(),
    order: jest.fn().mockReturnThis(),
    limit: jest.fn().mockResolvedValue({ data: [], error: null }),
};
mockSupabase.from.mockReturnValue(mockSupabase);

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runNotesAgent } = require('../../agents/notesAgent');

beforeEach(() => jest.clearAllMocks());

describe('runNotesAgent', () => {
    it('saves a note', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'add', title: 'רעיון', content: 'לפתח פיצ\'ר חדש' }));
        const result = await runNotesAgent('שמור הערה: לפתח פיצ\'ר חדש', mockSupabase, false);
        expect(result).toHaveProperty('answer');
    });

    it('searches notes', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'search', content: 'פיצ\'ר' }));
        mockSupabase.limit.mockResolvedValue({ data: [{ title: 'רעיון', content: 'לפתח פיצ\'ר חדש' }], error: null });
        const result = await runNotesAgent('חפש הערות על פיצ\'ר', mockSupabase, false);
        expect(result).toHaveProperty('answer');
    });

    it('handles invalid JSON from LLM', async () => {
        callGemma4.mockResolvedValue('not json');
        const result = await runNotesAgent('רשום הערה', mockSupabase, false);
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });
});
