jest.mock('../../agents/models', () => ({
    callGeminiWithSearch: jest.fn(),
    callGemma4: jest.fn(),
}));

const { callGeminiWithSearch } = require('../../agents/models');
const { runWeatherAgent } = require('../../agents/weatherAgent');

beforeEach(() => jest.clearAllMocks());

describe('runWeatherAgent', () => {
    it('returns weather answer from Gemini', async () => {
        callGeminiWithSearch.mockResolvedValue('⛅ תל אביב: 28°C, חלקית מעונן');
        const result = await runWeatherAgent('מה מזג האוויר בתל אביב?');
        expect(result).toHaveProperty('answer');
        expect(result.answer).toContain('תל אביב');
    });

    it('returns fallback on API failure', async () => {
        callGeminiWithSearch.mockRejectedValue(new Error('API error'));
        const result = await runWeatherAgent('תחזית מזג אוויר');
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
        expect(result.answer.length).toBeGreaterThan(0);
    });

    it('passes the full user message to Gemini', async () => {
        callGeminiWithSearch.mockResolvedValue('גשום');
        await runWeatherAgent('האם יגשם מחר בחיפה?');
        expect(callGeminiWithSearch).toHaveBeenCalledWith(
            expect.stringContaining('חיפה')
        );
    });
});
