jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runTranslationAgent } = require('../../agents/translationAgent');

beforeEach(() => jest.clearAllMocks());

describe('runTranslationAgent', () => {
    it('returns translation result', async () => {
        callGemma4.mockResolvedValue('Hello, how are you?');
        const result = await runTranslationAgent('תרגם לאנגלית: שלום, מה שלומך?', false);
        expect(result).toHaveProperty('answer');
        expect(result.answer.length).toBeGreaterThan(0);
    });

    it('handles translation failure gracefully', async () => {
        callGemma4.mockRejectedValue(new Error('LLM error'));
        const result = await runTranslationAgent('תרגם: שלום', false);
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('passes text to LLM for translation', async () => {
        callGemma4.mockResolvedValue('Good morning');
        await runTranslationAgent('תרגם לאנגלית: בוקר טוב', false);
        expect(callGemma4).toHaveBeenCalledWith(
            expect.stringContaining('בוקר טוב'),
            false
        );
    });
});
