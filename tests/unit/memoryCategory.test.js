'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { classifyCategory, CATEGORIES } = require('../../services/memoryCategory');

beforeEach(() => jest.clearAllMocks());

describe('classifyCategory', () => {
    test('returns the LLM-classified category when it is a known bucket', async () => {
        callGemma4.mockResolvedValue('{"category":"בריאות"}');
        const result = await classifyCategory('יש לי פגישה עם הרופא ביום שלישי');
        expect(result).toBe('בריאות');
    });

    test('defaults to כללי when the LLM returns an unknown category', async () => {
        callGemma4.mockResolvedValue('{"category":"ספורט"}');
        const result = await classifyCategory('תוכן כלשהו');
        expect(result).toBe('כללי');
    });

    test('defaults to כללי when the LLM returns invalid JSON', async () => {
        callGemma4.mockResolvedValue('not json');
        const result = await classifyCategory('תוכן כלשהו');
        expect(result).toBe('כללי');
    });

    test('defaults to כללי when callGemma4 throws', async () => {
        callGemma4.mockRejectedValue(new Error('provider down'));
        const result = await classifyCategory('תוכן כלשהו');
        expect(result).toBe('כללי');
    });

    test('returns כללי for empty content without calling the LLM', async () => {
        const result = await classifyCategory('   ');
        expect(result).toBe('כללי');
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('CATEGORIES exposes the 5-bucket taxonomy', () => {
        expect(CATEGORIES).toEqual(['עבודה', 'משפחה', 'בריאות', 'תחביב', 'כללי']);
    });
});
