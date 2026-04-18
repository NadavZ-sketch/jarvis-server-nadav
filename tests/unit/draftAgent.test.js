'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));

const { callGemma4 } = require('../../agents/models');
const { runDraftAgent } = require('../../agents/draftAgent');

beforeEach(() => {
    jest.clearAllMocks();
});

describe('runDraftAgent', () => {
    test('drafts text and returns it', async () => {
        callGemma4.mockResolvedValue('היי, מה שלומך?');
        const result = await runDraftAgent('נסח הודעה לחבר', [], '', {});
        expect(callGemma4).toHaveBeenCalled();
        expect(result.answer).toContain('היי, מה שלומך?');
    });

    test('send intent detected → appends follow-up question', async () => {
        callGemma4.mockResolvedValue('גוף ההודעה');
        const result = await runDraftAgent('נסח הודעת ווצאפ לחבר', [], '', {});
        expect(result.answer).toContain('רוצה שאשלח');
    });

    test('no send intent → no follow-up appended', async () => {
        callGemma4.mockResolvedValue('גוף ההודעה');
        const result = await runDraftAgent('נסח הודעה', [], '', {});
        expect(result.answer).not.toContain('רוצה שאשלח');
    });

    test('user chat history is included in prompt', async () => {
        callGemma4.mockResolvedValue('draft');
        const history = [
            { role: 'user', text: 'היי מה קורה' },
            { role: 'jarvis', text: 'הכל טוב' },
        ];
        await runDraftAgent('נסח', history, '', {});
        const prompt = callGemma4.mock.calls[0][0];
        expect(prompt).toContain('היי מה קורה');
    });

    test('callGemma4 throws → graceful error response', async () => {
        callGemma4.mockRejectedValue(new Error('API error'));
        const result = await runDraftAgent('נסח', [], '', {});
        expect(result.answer).toContain('לא הצלחתי לנסח');
    });
});
