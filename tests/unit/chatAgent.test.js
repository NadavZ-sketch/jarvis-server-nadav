'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiVision: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));

const { callGemma4, callGeminiVision } = require('../../agents/models');
const { runChatAgent } = require('../../agents/chatAgent');

beforeEach(() => {
    jest.clearAllMocks();
});

describe('runChatAgent', () => {
    test('text message → calls callGemma4 and returns answer', async () => {
        callGemma4.mockResolvedValue('שלום! מה שלומך?');
        const result = await runChatAgent('שלום', null, [], '', {});
        expect(callGemma4).toHaveBeenCalled();
        expect(callGeminiVision).not.toHaveBeenCalled();
        expect(result.answer).toBe('שלום! מה שלומך?');
    });

    test('image message → calls callGeminiVision instead of callGemma4', async () => {
        callGeminiVision.mockResolvedValue('I see a cat in the image.');
        const result = await runChatAgent('מה יש בתמונה?', 'iVBORbase64...', [], '', {});
        expect(callGeminiVision).toHaveBeenCalled();
        expect(callGemma4).not.toHaveBeenCalled();
        expect(result.answer).toBe('I see a cat in the image.');
    });

    test('chat history is included in prompt', async () => {
        callGemma4.mockResolvedValue('תשובה');
        const history = [
            { role: 'user', text: 'שאלה ראשונה' },
            { role: 'jarvis', text: 'תשובה ראשונה' },
        ];
        await runChatAgent('שאלה שנייה', null, history, '', {});
        const prompt = callGemma4.mock.calls[0][0][0].content;
        expect(prompt).toContain('שאלה ראשונה');
        expect(prompt).toContain('תשובה ראשונה');
    });

    test('long-term memories included in system prompt', async () => {
        callGemma4.mockResolvedValue('תשובה');
        await runChatAgent('שלום', null, [], '- [hobby] אני אוהב ריצה', {});
        const prompt = callGemma4.mock.calls[0][0][0].content;
        expect(prompt).toContain('[hobby] אני אוהב ריצה');
    });

    test('LLM returns empty string → fallback answer', async () => {
        callGemma4.mockResolvedValue('');
        const result = await runChatAgent('שלום', null, [], '', {});
        expect(result.answer).toBe('לא הצלחתי לגבש תשובה.');
    });

    test('callGemma4 throws → graceful error response', async () => {
        callGemma4.mockRejectedValue(new Error('API error'));
        const result = await runChatAgent('שלום', null, [], '', {});
        expect(result.answer).toContain('נתקלתי בבעיה');
    });

    test('custom assistant name appears in system prompt', async () => {
        callGemma4.mockResolvedValue('תשובה');
        await runChatAgent('שלום', null, [], '', { assistantName: 'ג\'רביס' });
        const prompt = callGemma4.mock.calls[0][0][0].content;
        expect(prompt).toContain("ג'רביס");
    });
});
