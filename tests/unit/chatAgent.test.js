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
        // History is now passed as structured messages (system + user/assistant turns),
        // not as a single string in message[0]. Check across the full messages array.
        const messages = callGemma4.mock.calls[0][0];
        const allContent = messages.map(m => m.content).join('\n');
        expect(allContent).toContain('שאלה ראשונה');
        expect(allContent).toContain('תשובה ראשונה');
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

// ─── Token-budget guardrails ──────────────────────────────────────────────────

const { buildSystemPrompt } = require('../../agents/chatAgent');

describe('buildSystemPrompt — token-budget guardrails', () => {
    test('memory block is capped at 2000 chars', () => {
        const bigMemory = 'זיכרון '.repeat(500); // ~3500 chars
        const prompt = buildSystemPrompt([], bigMemory, {});
        // The raw memory does NOT appear in full — only the cap-truncated version.
        expect(prompt).not.toContain(bigMemory);
        // The capped prefix is present.
        expect(prompt).toContain('זיכרון '.repeat(10).slice(0, 50));
        // Truncation marker is present.
        expect(prompt).toContain('(ועוד…)');
    });

    test('memory block within limit passes through unchanged', () => {
        const smallMemory = '- [hobby] אני אוהב ריצה\n- [name] נדב';
        const prompt = buildSystemPrompt([], smallMemory, {});
        expect(prompt).toContain('[hobby] אני אוהב ריצה');
        expect(prompt).not.toContain('(ועוד…)');
    });

    test('chat summary within settings is included', () => {
        const prompt = buildSystemPrompt([], '', { chatSummary: 'סיכום קצר' });
        expect(prompt).toContain('סיכום קצר');
    });

    test('suggestions skipped when user message is short (≤60 chars)', async () => {
        callGemma4.mockResolvedValue('בסדר, שמרתי.');
        await runChatAgent('תודה', null, [], '', {});
        // With a 5-char message the suggestions call should not fire.
        // callGemma4 is called exactly once (for the answer, not suggestions).
        expect(callGemma4).toHaveBeenCalledTimes(1);
    });
});
