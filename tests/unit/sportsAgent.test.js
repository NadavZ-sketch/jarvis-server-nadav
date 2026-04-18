'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));

const { callGeminiWithSearch } = require('../../agents/models');
const { runSportsAgent } = require('../../agents/sportsAgent');

beforeEach(() => {
    jest.clearAllMocks();
});

describe('runSportsAgent', () => {
    test('returns answer from Gemini with search', async () => {
        callGeminiWithSearch.mockResolvedValue('ארסנל ניצחה 2-1');
        const result = await runSportsAgent('מה התוצאה של ארסנל?');
        expect(callGeminiWithSearch).toHaveBeenCalled();
        expect(result.answer).toBe('ארסנל ניצחה 2-1');
    });

    test('user question is passed in the prompt', async () => {
        callGeminiWithSearch.mockResolvedValue('answer');
        await runSportsAgent('מי מוביל את הטבלה?');
        const prompt = callGeminiWithSearch.mock.calls[0][0];
        expect(prompt).toContain('מי מוביל את הטבלה?');
    });

    test('Gemini returns empty string → fallback message', async () => {
        callGeminiWithSearch.mockResolvedValue('');
        const result = await runSportsAgent('מה התוצאה?');
        expect(result.answer).toContain('לא הצלחתי למצוא מידע');
    });

    test('callGeminiWithSearch throws → graceful error response', async () => {
        callGeminiWithSearch.mockRejectedValue(new Error('API error'));
        const result = await runSportsAgent('מה התוצאה?');
        expect(result.answer).toContain('לא הצלחתי להביא נתוני כדורגל');
    });
});
