'use strict';

jest.mock('../../services/mcp/sdkLoader');
jest.mock('axios');

const fs = require('fs');
const path = require('path');
const axios = require('axios');
const sdkLoader = require('../../services/mcp/sdkLoader');
const manager = require('../../services/mcp/mcpClientManager');
const { getPolicy } = require('../../services/mcp/toolPolicy');
const { callWithTools } = require('../../agents/models');
const configPath = path.resolve(__dirname, '../../config/mcpServers.json');
const preset = JSON.parse(fs.readFileSync(configPath, 'utf8')).parallel;

const tools = ['web_search', 'web_fetch'].map(name => ({
    name, description: name, inputSchema: { type: 'object', properties: {} },
}));
let client;
let sdk;
const savedEnv = { ...process.env };

function useConfig(config) {
    const read = fs.readFileSync;
    jest.spyOn(fs, 'readFileSync').mockImplementation((file, ...args) =>
        file === configPath ? JSON.stringify(config) : read(file, ...args));
}

beforeEach(() => {
    jest.clearAllMocks();
    manager._resetForTests();
    process.env.MCP_ENABLED = 'true';
    client = {
        connect: jest.fn().mockResolvedValue(),
        listTools: jest.fn().mockResolvedValue({ tools }),
        callTool: jest.fn().mockResolvedValue({ content: [{ type: 'text', text: 'source excerpt https://nodejs.org/' }] }),
        close: jest.fn().mockResolvedValue(),
    };
    sdk = {
        Client: jest.fn(() => client),
        StdioClientTransport: jest.fn(() => ({})),
        StreamableHTTPClientTransport: jest.fn(() => ({})),
    };
    sdkLoader.getSdk.mockResolvedValue(sdk);
});

afterEach(async () => {
    await manager.shutdown();
    jest.restoreAllMocks();
    jest.useRealTimers();
    process.env = { ...savedEnv };
});

test('the shipped Parallel preset stays disabled and does not connect', async () => {
    expect(preset.enabled).toBe(false);
    useConfig({ parallel: preset });
    await manager.init();
    expect(sdk.Client).not.toHaveBeenCalled();
    expect(manager.getToolCatalog()).toEqual([]);
});

test('MCP_ENABLED still gates an explicitly enabled preset', async () => {
    delete process.env.MCP_ENABLED;
    useConfig({ parallel: { ...preset, enabled: true } });
    await manager.init();
    expect(sdkLoader.getSdk).not.toHaveBeenCalled();
});

test('opt-in preset selects HTTP with the endpoint and project header, without credentials', async () => {
    useConfig({ parallel: { ...preset, enabled: true } });
    await manager.init();
    expect(sdk.StreamableHTTPClientTransport).toHaveBeenCalledWith(
        new URL('https://search.parallel.ai/mcp'),
        { requestInit: { headers: { 'User-Agent': preset.headers['User-Agent'] } } }
    );
    expect(sdk.StdioClientTransport).not.toHaveBeenCalled();
    expect(manager.getToolCatalog().map(t => t.function.name)).toEqual([
        'parallel__web_search', 'parallel__web_fetch',
    ]);
    const args = { objective: 'Find Node.js releases', search_queries: ['Node.js releases'] };
    const result = await manager.guardedCallTool('parallel__web_search', args);
    expect(client.callTool).toHaveBeenCalledWith({ name: 'web_search', arguments: args }, undefined, undefined);
    expect(result).toEqual({ ok: true, content: 'source excerpt https://nodejs.org/' });
});

test('HTTP URL and headers expand environment values and omit empty headers', async () => {
    process.env.TEST_MCP_URL = 'https://example.org/mcp';
    process.env.TEST_MCP_TOKEN = 'fixture';
    delete process.env.TEST_MCP_MISSING;
    useConfig({ parallel: { ...preset, enabled: true, url: '${TEST_MCP_URL}', headers: {
        'User-Agent': preset.headers['User-Agent'],
        Authorization: 'Bearer ${TEST_MCP_TOKEN}', 'X-Optional': '${TEST_MCP_MISSING}',
    } } });
    await manager.init();
    expect(sdk.StreamableHTTPClientTransport).toHaveBeenCalledWith(new URL('https://example.org/mcp'), {
        requestInit: { headers: { 'User-Agent': preset.headers['User-Agent'], Authorization: 'Bearer fixture' } },
    });
});

test.each([undefined, 'stdio'])('existing %s stdio transport keeps command, arguments and environment', async transport => {
    process.env.TEST_MCP_ROOT = '/tmp/jarvis';
    useConfig({ filesystem: { enabled: true, transport, command: 'npx', args: ['server', '${TEST_MCP_ROOT}'], env: { EXTRA: 'value' } } });
    await manager.init();
    expect(sdk.StdioClientTransport).toHaveBeenCalledWith({
        command: 'npx', args: ['server', '/tmp/jarvis'], env: { ...process.env, EXTRA: 'value' },
    });
    expect(sdk.StreamableHTTPClientTransport).not.toHaveBeenCalled();
});

test.each([
    { transport: 'sse', url: preset.url },
    { transport: 'streamable-http', url: 'file:///tmp/mcp' },
    { transport: 'streamable-http', url: 'invalid' },
])('bad transport configuration is isolated from other servers: %j', async bad => {
    useConfig({ bad: { enabled: true, ...bad }, parallel: { ...preset, enabled: true } });
    await manager.init();
    expect(manager.getToolCatalog()).toHaveLength(2);
    expect(sdk.StdioClientTransport).not.toHaveBeenCalled();
});

test.each(['connect', 'listTools'])('failed %s closes the partial connection and clears its deadline', async stage => {
    jest.useFakeTimers();
    client[stage].mockRejectedValue(new Error('offline'));
    useConfig({ parallel: { ...preset, enabled: true } });
    await manager.init();
    expect(client.close).toHaveBeenCalledTimes(1);
    expect(manager.getToolCatalog()).toEqual([]);
    expect(jest.getTimerCount()).toBe(0);
});

test.each(['connect', 'listTools'])('hanging %s times out, closes the connection and leaves no catalog', async stage => {
    jest.useFakeTimers();
    client[stage].mockImplementation(() => new Promise(() => {}));
    useConfig({ parallel: { ...preset, enabled: true } });
    const pending = manager.init();
    await jest.advanceTimersByTimeAsync(35000);
    await pending;
    expect(client.close).toHaveBeenCalledTimes(1);
    expect(manager.getToolCatalog()).toEqual([]);
    expect(jest.getTimerCount()).toBe(0);
});

test('only known read tools gain free/member permissions; unknown tools still require consent', async () => {
    expect(getPolicy('parallel__web_search').actionType).toBe('web.search');
    expect(getPolicy('parallel__web_fetch').actionType).toBe('web.fetch');
    useConfig({ parallel: { ...preset, enabled: true } });
    await manager.init();
    expect(await manager.guardedCallTool('parallel__web_fetch', { urls: ['https://example.org'] }))
        .toEqual({ ok: true, content: 'source excerpt https://nodejs.org/' });
    expect(await manager.guardedCallTool('parallel__new_tool', {}))
        .toMatchObject({ error: 'policy_denied', reason: 'insufficient_permissions' });
    expect(await manager.guardedCallTool('parallel__new_tool', {}, { role: 'admin', plan: 'pro' }))
        .toMatchObject({ error: 'policy_denied', reason: 'consent_required' });
    expect(client.callTool).toHaveBeenCalledTimes(1);
});

test.each(['remote failure', 'Request timed out', 'This operation was aborted'])('request error is returned as content: %s', async message => {
    useConfig({ parallel: { ...preset, enabled: true } });
    await manager.init();
    client.callTool.mockRejectedValue(new Error(message));
    const controller = new AbortController();
    const options = { timeout: 50, signal: controller.signal };
    const result = await manager.guardedCallTool('parallel__web_fetch', { urls: ['https://example.org'] }, undefined, options);
    expect(client.callTool).toHaveBeenLastCalledWith(
        { name: 'web_fetch', arguments: { urls: ['https://example.org'] } }, undefined, options
    );
    expect(result).toEqual({ ok: true, content: `Error calling tool parallel__web_fetch: ${message}` });
});

test('model tool loop consumes content dispatched through the real manager and policy', async () => {
    useConfig({ parallel: { ...preset, enabled: true } });
    await manager.init();
    axios.post.mockResolvedValueOnce({ data: { choices: [{ message: { tool_calls: [{
        id: 'search1', type: 'function', function: {
            name: 'parallel__web_search', arguments: JSON.stringify({ objective: 'Node.js releases' }),
        },
    }] } }] } }).mockResolvedValueOnce({ data: { choices: [{ message: { content: 'See https://nodejs.org/' } }] } });
    const result = await callWithTools('Find Node.js releases', {
        tools: manager.getToolCatalog(),
        callTool: async (name, args) => (await manager.guardedCallTool(name, args)).content,
    });
    expect(result).toBe('See https://nodejs.org/');
    expect(axios.post.mock.calls[1][1].messages).toContainEqual({
        role: 'tool', tool_call_id: 'search1', content: 'source excerpt https://nodejs.org/',
    });
});
