jest.mock('../../agents/models', () => ({
    callGeminiWithSearch: jest.fn(),
    callGemma4: jest.fn(),
}));

const { callGeminiWithSearch } = require('../../agents/models');
const { runStocksAgent } = require('../../agents/stocksAgent');

beforeEach(() => jest.clearAllMocks());

describe('runStocksAgent', () => {
    it('returns stock data', async () => {
        callGeminiWithSearch.mockResolvedValue('📈 AAPL: $175.30 (+1.2%)');
        const result = await runStocksAgent('מה מחיר מניית אפל?');
        expect(result).toHaveProperty('answer');
        expect(result.answer).toContain('AAPL');
    });

    it('returns fallback on error', async () => {
        callGeminiWithSearch.mockRejectedValue(new Error('timeout'));
        const result = await runStocksAgent('מניות');
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('handles crypto queries', async () => {
        callGeminiWithSearch.mockResolvedValue('₿ Bitcoin: $65,000');
        const result = await runStocksAgent('מה מחיר ביטקוין?');
        expect(result.answer).toContain('Bitcoin');
    });
});
