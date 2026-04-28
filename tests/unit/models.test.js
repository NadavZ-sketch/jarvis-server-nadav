'use strict';
jest.mock('axios');

const axios = require('axios');
const { callGemma4, callGeminiWithSearch, detectMimeType } = require('../../agents/models');

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
