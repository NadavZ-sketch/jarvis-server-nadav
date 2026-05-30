'use strict';

// manusAgent reads env vars at module load time, so we use jest.resetModules()
// + require-inside-test pattern to isolate env changes between tests.
// This means we call jest.doMock (not jest.mock) so it isn't hoisted.

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
    jest.resetModules();
    process.env = { ...ORIGINAL_ENV };
    delete process.env.MANUS_API_KEY;
    delete process.env.MANUS_MODEL;
    delete process.env.MANUS_AUTH_HEADER;
    delete process.env.MANUS_TIMEOUT_MS;
});

afterAll(() => {
    process.env = ORIGINAL_ENV;
});

function freshMocks() {
    const axiosMock = {
        post: jest.fn(),
        get: jest.fn(),
        default: {},
    };
    jest.doMock('axios', () => axiosMock);
    const agent = require('../../agents/manusAgent');
    return { axios: axiosMock, agent };
}

// ─── isManusConfigured ─────────────────────────────────────────────────────────

describe('isManusConfigured', () => {
    test('returns false when key is missing', () => {
        const { agent } = freshMocks();
        expect(agent.isManusConfigured()).toBe(false);
    });

    test('returns true when key is present', () => {
        process.env.MANUS_API_KEY = 'test-key';
        const { agent } = freshMocks();
        expect(agent.isManusConfigured()).toBe(true);
    });
});

// ─── runManusAgent — no key ────────────────────────────────────────────────────

describe('runManusAgent', () => {
    test('returns Hebrew warning when MANUS_API_KEY not set', async () => {
        const { agent } = freshMocks();
        const result = await agent.runManusAgent('some task');
        expect(result.answer).toMatch(/MANUS_API_KEY/);
    });

    test('appends task_url link to answer', async () => {
        process.env.MANUS_API_KEY = 'key';
        const { axios, agent } = freshMocks();

        axios.post.mockResolvedValueOnce({
            data: { task_id: 'tid3', task_url: 'https://manus.ai/task/tid3' },
        });
        axios.get.mockResolvedValueOnce({
            data: { status: 'completed', output: 'Research complete.' },
        });

        // Speed up the polling delay by making setTimeout fire immediately
        jest.useFakeTimers();
        const p = agent.runManusAgent('deep research on AI');
        await jest.runAllTimersAsync();
        const result = await p;
        jest.useRealTimers();

        expect(result.answer).toContain('Research complete.');
        expect(result.answer).toContain('https://manus.ai/task/tid3');
    });

    test('surfaces Hebrew error on Manus failure', async () => {
        process.env.MANUS_API_KEY = 'key';
        const { axios, agent } = freshMocks();

        axios.post.mockResolvedValueOnce({ data: { task_id: 'err1' } });
        axios.get.mockResolvedValueOnce({ data: { status: 'failed', error: 'timeout' } });

        jest.useFakeTimers();
        const p = agent.runManusAgent('task');
        await jest.runAllTimersAsync();
        const result = await p;
        jest.useRealTimers();

        expect(result.answer).toMatch(/Manus לא הצליח/);
    });
});

// ─── runManusTask — correct API contract ──────────────────────────────────────

describe('runManusTask', () => {
    test('uses /v1/tasks with agentProfile + API_KEY header (not old v2 / x-manus-api-key)', async () => {
        process.env.MANUS_API_KEY = 'test-key-123';
        process.env.MANUS_MODEL = 'manus-1.5';
        const { axios, agent } = freshMocks();

        axios.post.mockResolvedValueOnce({
            data: { task_id: 'abc123', task_url: 'https://manus.ai/task/abc123' },
        });
        // First poll — still running
        axios.get.mockResolvedValueOnce({ data: { status: 'running' } });
        // Second poll — completed
        axios.get.mockResolvedValueOnce({
            data: { status: 'completed', output: 'Task result text here' },
        });

        jest.useFakeTimers();
        const p = agent.runManusTask('do research on X');
        await jest.runAllTimersAsync();
        const result = await p;
        jest.useRealTimers();

        // Verify create request — must use /v1/ and agentProfile
        const [createUrl, createBody, createConfig] = axios.post.mock.calls[0];
        expect(createUrl).toMatch(/\/v1\/tasks$/);
        expect(createBody).toMatchObject({ prompt: 'do research on X', agentProfile: 'manus-1.5' });
        expect(createBody).not.toHaveProperty('model'); // old broken contract
        expect(createConfig.headers).toHaveProperty('API_KEY', 'test-key-123');
        expect(createConfig.headers).not.toHaveProperty('x-manus-api-key'); // old broken header

        // Verify poll request uses correct path
        const [pollUrl] = axios.get.mock.calls[1];
        expect(pollUrl).toMatch(/\/v1\/tasks\/abc123$/);

        expect(result.answer).toBe('Task result text here');
        expect(result.taskUrl).toBe('https://manus.ai/task/abc123');
    });

    test('custom MANUS_AUTH_HEADER is used when set', async () => {
        process.env.MANUS_API_KEY = 'key-xyz';
        process.env.MANUS_AUTH_HEADER = 'Authorization';
        const { axios, agent } = freshMocks();

        axios.post.mockResolvedValueOnce({ data: { task_id: 'tid1' } });
        axios.get.mockResolvedValueOnce({ data: { status: 'completed', output: 'done' } });

        jest.useFakeTimers();
        const p = agent.runManusTask('task');
        await jest.runAllTimersAsync();
        await p;
        jest.useRealTimers();

        const createConfig = axios.post.mock.calls[0][2];
        expect(createConfig.headers).toHaveProperty('Authorization', 'key-xyz');
        expect(createConfig.headers).not.toHaveProperty('API_KEY');
    });

    test('handles output as array of message objects', async () => {
        process.env.MANUS_API_KEY = 'key';
        const { axios, agent } = freshMocks();

        axios.post.mockResolvedValueOnce({ data: { task_id: 'tid2' } });
        axios.get.mockResolvedValueOnce({
            data: {
                status: 'completed',
                output: [
                    { role: 'user', content: 'do this' },
                    { role: 'assistant', content: 'Done! Here is the result.' },
                ],
            },
        });

        jest.useFakeTimers();
        const p = agent.runManusTask('task');
        await jest.runAllTimersAsync();
        const result = await p;
        jest.useRealTimers();

        expect(result.answer).toBe('Done! Here is the result.');
    });

    test('handles output as messages array', async () => {
        process.env.MANUS_API_KEY = 'key';
        const { axios, agent } = freshMocks();

        axios.post.mockResolvedValueOnce({ data: { task_id: 'tid4' } });
        axios.get.mockResolvedValueOnce({
            data: {
                status: 'completed',
                messages: [
                    { role: 'user', content: 'question' },
                    { role: 'assistant', content: 'Answer from messages array.' },
                ],
            },
        });

        jest.useFakeTimers();
        const p = agent.runManusTask('task');
        await jest.runAllTimersAsync();
        const result = await p;
        jest.useRealTimers();

        expect(result.answer).toBe('Answer from messages array.');
    });

    test('throws when status is failed', async () => {
        process.env.MANUS_API_KEY = 'key';
        const { axios, agent } = freshMocks();

        axios.post.mockResolvedValueOnce({ data: { task_id: 'fail1' } });
        axios.get.mockResolvedValueOnce({
            data: { status: 'failed', error: 'Out of credits' },
        });

        jest.useFakeTimers();
        const p = agent.runManusTask('task');
        // Attach the rejection handler BEFORE advancing timers to avoid unhandled-rejection
        const assertion = expect(p).rejects.toThrow('Out of credits');
        await jest.runAllTimersAsync();
        jest.useRealTimers();
        await assertion;
    });

    test('throws when no API key', async () => {
        const { agent } = freshMocks();
        await expect(agent.runManusTask('task')).rejects.toThrow('MANUS_API_KEY');
    });
});
