jest.mock('../../agents/models', () => ({
    callGeminiWithSearch: jest.fn(),
    callGemma4: jest.fn(),
}));

const { callGeminiWithSearch } = require('../../agents/models');
const { runNewsAgent } = require('../../agents/newsAgent');

beforeEach(() => jest.clearAllMocks());

describe('runNewsAgent', () => {
    it('returns news answer', async () => {
        callGeminiWithSearch.mockResolvedValue('📰 כותרות היום: שוק ההון עלה ב-2%...');
        const result = await runNewsAgent('מה החדשות היום?');
        expect(result).toHaveProperty('answer');
        expect(result.answer.length).toBeGreaterThan(0);
    });

    it('returns fallback on failure', async () => {
        callGeminiWithSearch.mockRejectedValue(new Error('network error'));
        const result = await runNewsAgent('חדשות');
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('passes user message to Gemini search', async () => {
        callGeminiWithSearch.mockResolvedValue('חדשות כלכלה...');
        await runNewsAgent('חדשות כלכלה');
        expect(callGeminiWithSearch).toHaveBeenCalledWith(
            expect.stringContaining('כלכלה')
        );
    });
});
