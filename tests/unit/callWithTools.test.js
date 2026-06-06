'use strict';

// Tests for the callWithTools function in agents/models.js

jest.mock('axios');
const axios = require('axios');
const { callWithTools } = require('../../agents/models');

// Helper responses
const textResponse = (text) => ({
    data: { choices: [{ message: { content: text, tool_calls: null } }] },
});

const toolCallResponse = (toolCalls) => ({
    data: { choices: [{ message: { content: null, tool_calls: toolCalls } }] },
});

const TOOL_CALL = [{
    id: 'call_abc123',
    type: 'function',
    function: { name: 'filesystem__read_file', arguments: JSON.stringify({ path: '/tmp/test.txt' }) },
}];

const TOOLS = [{
    type: 'function',
    function: {
        name: 'filesystem__read_file',
        description: 'Read a file',
        parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] },
    },
}];

beforeEach(() => {
    jest.clearAllMocks();
    process.env.GROQ_API_KEY = 'test-groq-key';
});

describe('callWithTools — basic flow', () => {
    test('returns text directly when no tool calls', async () => {
        axios.post.mockResolvedValueOnce(textResponse('תשובה סופית'));
        const result = await callWithTools('שאלה', { tools: TOOLS, callTool: jest.fn(), useLocal: false });
        expect(result).toBe('תשובה סופית');
    });

    test('executes tool_calls and returns final text after loop', async () => {
        const mockCallTool = jest.fn().mockResolvedValue('תוכן הקובץ');

        axios.post
            .mockResolvedValueOnce(toolCallResponse(TOOL_CALL))  // 1st: tool call
            .mockResolvedValueOnce(textResponse('קראתי את הקובץ: תוכן הקובץ')); // 2nd: final

        const result = await callWithTools('תקרא קובץ', { tools: TOOLS, callTool: mockCallTool, useLocal: false });

        expect(mockCallTool).toHaveBeenCalledWith('filesystem__read_file', { path: '/tmp/test.txt' });
        expect(result).toBe('קראתי את הקובץ: תוכן הקובץ');
        expect(axios.post).toHaveBeenCalledTimes(2);
    });

    test('appends tool result to messages with correct role', async () => {
        const mockCallTool = jest.fn().mockResolvedValue('file content');

        axios.post
            .mockResolvedValueOnce(toolCallResponse(TOOL_CALL))
            .mockResolvedValueOnce(textResponse('done'));

        await callWithTools('read file', { tools: TOOLS, callTool: mockCallTool, useLocal: false });

        const secondCallBody = axios.post.mock.calls[1][1];
        const toolResultMsg = secondCallBody.messages.find(m => m.role === 'tool');
        expect(toolResultMsg).toBeDefined();
        expect(toolResultMsg.tool_call_id).toBe('call_abc123');
        expect(toolResultMsg.content).toBe('file content');
    });

    test('includes tools and tool_choice:auto in request body', async () => {
        axios.post.mockResolvedValueOnce(textResponse('answer'));
        await callWithTools('test', { tools: TOOLS, callTool: jest.fn(), useLocal: false });

        const body = axios.post.mock.calls[0][1];
        expect(body.tools).toEqual(TOOLS);
        expect(body.tool_choice).toBe('auto');
    });

    test('does not include tools/tool_choice when tools array is empty', async () => {
        axios.post.mockResolvedValueOnce(textResponse('answer'));
        await callWithTools('test', { tools: [], callTool: jest.fn(), useLocal: false });

        const body = axios.post.mock.calls[0][1];
        expect(body.tools).toBeUndefined();
        expect(body.tool_choice).toBeUndefined();
    });
});

describe('callWithTools — maxIterations guard', () => {
    test('stops after maxIterations and returns empty string', async () => {
        const mockCallTool = jest.fn().mockResolvedValue('result');

        // Always return tool_calls (infinite loop scenario)
        axios.post.mockResolvedValue(toolCallResponse(TOOL_CALL));

        const result = await callWithTools('loop', {
            tools: TOOLS, callTool: mockCallTool, useLocal: false, maxIterations: 3,
        });

        expect(axios.post).toHaveBeenCalledTimes(3);
        expect(result).toBe(''); // last assistant msg has no content
    });
});

describe('callWithTools — provider fallback', () => {
    test('falls back to DeepSeek when Groq fails', async () => {
        axios.post
            .mockRejectedValueOnce(new Error('Groq down'))
            .mockResolvedValueOnce(textResponse('from deepseek'));

        const result = await callWithTools('test', { tools: [], callTool: jest.fn(), useLocal: false });
        expect(result).toBe('from deepseek');
        expect(axios.post).toHaveBeenCalledTimes(2);
    });

    test('throws when all OpenAI-compatible providers fail', async () => {
        axios.post.mockRejectedValue(new Error('all down'));
        await expect(
            callWithTools('test', { tools: [], callTool: jest.fn(), useLocal: false })
        ).rejects.toThrow('All OpenAI-compatible providers failed');
    });
});

describe('callWithTools — tool error handling', () => {
    test('captures tool execution error and continues', async () => {
        const mockCallTool = jest.fn().mockRejectedValueOnce(new Error('tool failed'));

        axios.post
            .mockResolvedValueOnce(toolCallResponse(TOOL_CALL))
            .mockResolvedValueOnce(textResponse('handled error'));

        const result = await callWithTools('test', { tools: TOOLS, callTool: mockCallTool, useLocal: false });

        // Loop should continue even when callTool throws
        expect(result).toBe('handled error');
        const secondCallBody = axios.post.mock.calls[1][1];
        const toolResultMsg = secondCallBody.messages.find(m => m.role === 'tool');
        expect(toolResultMsg.content).toMatch(/Error in tool/);
    });

    test('handles missing callTool by returning "not available"', async () => {
        axios.post
            .mockResolvedValueOnce(toolCallResponse(TOOL_CALL))
            .mockResolvedValueOnce(textResponse('ok'));

        // No callTool provided
        await callWithTools('test', { tools: TOOLS, useLocal: false });

        const secondCallBody = axios.post.mock.calls[1][1];
        const toolMsg = secondCallBody.messages.find(m => m.role === 'tool');
        expect(toolMsg.content).toMatch(/not available/);
    });
});
