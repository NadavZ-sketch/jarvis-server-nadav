'use strict';
jest.mock('axios');

const axios = require('axios');
const { callGemma4, callGeminiWithSearch, callGeminiVision, detectMimeType } = require('../../agents/models');

const GROQ_RESPONSE = {
    data: { choices: [{ message: { content: '  groq answer  ' } }] }
};
const DEEPSEEK_RESPONSE = {
    data: { choices: [{ message: { content: 'deepseek answer' } }] }
};
const GEMINI_RESPONSE = {
    data: { candidates: [{ content: { parts: [{ text: 'gemini answer' } ] } }] }
};

beforeEach(() => {
    jest.clearAllMocks();
    // Default: all calls succeed via Groq
    axios.post.mockResolvedValue(GROQ_RESPONSE);
});

describe('detectMimeType', () => {
    test('/9j/ prefix → image/jpeg', () => {
        expect(detectMimeType('/9j/abc')).toBe('image/jpeg');
    });

    test('iVBOR prefix → image/png', () => {
        expect(detectMimeType('iVBORabc')).toBe('image/png');
    });

    test('UklGR prefix → image/webp', () => {
        expect(detectMimeType('UklGRabc')).toBe('image/webp');
    });

    test('unknown prefix → defaults to image/jpeg', () => {
        expect(detectMimeType('xxxxxxxx')).toBe('image/jpeg');
    });
});

describe('callGemma4', () => {
    test('string input is wrapped into user message array', async () => {
        await callGemma4('hello', false);
        const body = axios.post.mock.calls[0][1];
        expect(body.messages).toEqual([{ role: 'user', content: 'hello' }]);
    });

    test('array input is passed directly', async () => {
        const msgs = [{ role: 'user', content: 'hi' }];
        await callGemma4(msgs, false);
        const body = axios.post.mock.calls[0][1];
        expect(body.messages).toEqual(msgs);
    });

    test('Groq success → returns trimmed content', async () => {
        axios.post.mockResolvedValueOnce(GROQ_RESPONSE);
        const result = await callGemma4('test', false);
        expect(result).toBe('groq answer');
    });

    test('Groq fails → falls back to DeepSeek', async () => {
        axios.post
            .mockRejectedValueOnce(new Error('Groq error'))   // Groq fails
            .mockResolvedValueOnce(DEEPSEEK_RESPONSE);        // DeepSeek succeeds
        const result = await callGemma4('test', false);
        expect(result).toBe('deepseek answer');
        expect(axios.post).toHaveBeenCalledTimes(2);
    });

    test('Groq + DeepSeek fail → falls back to Gemini', async () => {
        axios.post
            .mockRejectedValueOnce(new Error('Groq error'))
            .mockRejectedValueOnce(new Error('DeepSeek error'))
            .mockResolvedValueOnce(GEMINI_RESPONSE);
        const result = await callGemma4('test', false);
        expect(result).toBe('gemini answer');
        expect(axios.post).toHaveBeenCalledTimes(3);
    });

    test('all providers fail → throws from Gemini', async () => {
        axios.post
            .mockRejectedValueOnce(new Error('Groq error'))
            .mockRejectedValueOnce(new Error('DeepSeek error'))
            .mockRejectedValueOnce(new Error('Gemini error'));
        await expect(callGemma4('test', false)).rejects.toThrow('Gemini error');
    });

    test('Groq returns error-as-content → falls back to DeepSeek', async () => {
        const groqErrorContent = {
            data: { choices: [{ message: { content: 'API Error: Stream idle timeout - partial response received' } }] }
        };
        axios.post
            .mockResolvedValueOnce(groqErrorContent)
            .mockResolvedValueOnce(DEEPSEEK_RESPONSE);
        const result = await callGemma4('test', false);
        expect(result).toBe('deepseek answer');
        expect(axios.post).toHaveBeenCalledTimes(2);
    });

    test('Groq returns "Stream idle timeout" content → falls back to DeepSeek', async () => {
        const groqIdleContent = {
            data: { choices: [{ message: { content: 'Stream idle timeout — partial response received' } }] }
        };
        axios.post
            .mockResolvedValueOnce(groqIdleContent)
            .mockResolvedValueOnce(DEEPSEEK_RESPONSE);
        const result = await callGemma4('test', false);
        expect(result).toBe('deepseek answer');
    });

    test('all providers receive the same temperature/top_p (consistency)', async () => {
        axios.post
            .mockRejectedValueOnce(new Error('Groq fail'))
            .mockRejectedValueOnce(new Error('DeepSeek fail'))
            .mockResolvedValueOnce(GEMINI_RESPONSE);

        await callGemma4('hi', false);

        // Three calls: Groq → DeepSeek → Gemini.
        const groqBody     = axios.post.mock.calls[0][1];
        const deepseekBody = axios.post.mock.calls[1][1];
        const geminiBody   = axios.post.mock.calls[2][1];

        expect(groqBody.temperature).toBe(0.5);
        expect(groqBody.top_p).toBe(0.9);
        expect(deepseekBody.temperature).toBe(0.5);
        expect(deepseekBody.top_p).toBe(0.9);
        expect(geminiBody.generationConfig.temperature).toBe(0.5);
        expect(geminiBody.generationConfig.topP).toBe(0.9);
    });

    test('Gemini fallback preserves role boundaries via systemInstruction', async () => {
        axios.post
            .mockRejectedValueOnce(new Error('Groq fail'))
            .mockRejectedValueOnce(new Error('DeepSeek fail'))
            .mockResolvedValueOnce(GEMINI_RESPONSE);

        const msgs = [
            { role: 'system', content: 'You are Jarvis.' },
            { role: 'user', content: 'hi' },
            { role: 'assistant', content: 'hello' },
            { role: 'user', content: 'what is your name?' },
        ];
        await callGemma4(msgs, false);

        const geminiBody = axios.post.mock.calls[2][1];
        // System instruction is hoisted out of the user-side conversation.
        expect(geminiBody.systemInstruction.parts[0].text).toBe('You are Jarvis.');
        // Conversation preserves alternating roles (assistant→model).
        expect(geminiBody.contents).toEqual([
            { role: 'user',  parts: [{ text: 'hi' }] },
            { role: 'model', parts: [{ text: 'hello' }] },
            { role: 'user',  parts: [{ text: 'what is your name?' }] },
        ]);
    });
});

describe('callGeminiWithSearch', () => {
    test('sends google_search tool in body and returns text', async () => {
        axios.post.mockResolvedValueOnce(GEMINI_RESPONSE);
        const result = await callGeminiWithSearch('who won?');
        expect(result).toBe('gemini answer');
        const body = axios.post.mock.calls[0][1];
        expect(body.tools).toEqual([{ google_search: {} }]);
    });
});

describe('callGeminiVision', () => {
    test('throws when image base64 exceeds 10 MB', async () => {
        // 10 MB decoded → ~13.6 MB base64; use a string just over that limit
        const oversized = 'A'.repeat(Math.ceil(10 * 1024 * 1024 * 4 / 3) + 1);
        await expect(callGeminiVision('describe this', oversized))
            .rejects.toThrow('Image too large');
        expect(axios.post).not.toHaveBeenCalled();
    });

    test('accepts image within size limit and returns description', async () => {
        axios.post.mockResolvedValueOnce(GEMINI_RESPONSE);
        const smallImage = 'iVBORsmall';
        const result = await callGeminiVision('describe this', smallImage);
        expect(result).toBe('gemini answer');
    });
});
