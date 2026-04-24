jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('@supabase/supabase-js', () => ({
    createClient: () => ({ from: () => ({ insert: jest.fn().mockResolvedValue({ error: null }) }) })
}));

const { callGemma4 } = require('../../agents/models');
const { runTranslationAgent } = require('../../agents/translationAgent');
const mockSupabase = { from: () => ({ insert: jest.fn().mockResolvedValue({ error: null }) }) };

beforeEach(() => jest.clearAllMocks());

describe('runTranslationAgent', () => {
    it('returns translation result', async () => {
        callGemma4.mockResolvedValue('Hello, how are you?');
        const result = await runTranslationAgent('תרגם לאנגלית: שלום, מה שלומך?', mockSupabase, false);
        expect(result).toHaveProperty('answer');
        expect(result.answer.length).toBeGreaterThan(0);
    });

    it('handles translation failure gracefully', async () => {
        callGemma4.mockRejectedValue(new Error('LLM error'));
        const result = await runTranslationAgent('תרגם: שלום', mockSupabase, false);
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('passes text to LLM for translation', async () => {
        callGemma4.mockResolvedValue('Good morning');
        await runTranslationAgent('תרגם לאנגלית: בוקר טוב', mockSupabase, false);
        expect(callGemma4).toHaveBeenCalledWith(
            expect.stringContaining('בוקר טוב'),
            false
        );
    });
});
