'use strict';

// Tests for services/mcp/mcpClientManager.js
// Mocks sdkLoader so no actual MCP subprocess is spawned.

jest.mock('../../services/mcp/sdkLoader');
jest.mock('../../services/policyEngine', () => ({
    isAllowedByRolePlan: jest.fn(() => true),
    isBlockedAction:     jest.fn(() => false),
}));

const sdkLoader    = require('../../services/mcp/sdkLoader');
const policyEngine = require('../../services/policyEngine');
const manager      = require('../../services/mcp/mcpClientManager');

// Build a fake MCP client with controllable listTools / callTool responses.
function makeFakeClient(tools = [], callToolResult = { content: [{ type: 'text', text: 'ok' }] }) {
    return {
        connect:   jest.fn().mockResolvedValue(undefined),
        listTools: jest.fn().mockResolvedValue({ tools }),
        callTool:  jest.fn().mockResolvedValue(callToolResult),
        close:     jest.fn().mockResolvedValue(undefined),
    };
}

// Build a fake SDK where Client() returns sequential instances from the map.
function makeFakeSdk(clientsByServer = {}) {
    const instances = Object.values(clientsByServer);
    let idx = 0;
    return {
        Client: jest.fn().mockImplementation(() => instances[idx++] || makeFakeClient()),
        StdioClientTransport: jest.fn().mockImplementation(() => ({})),
    };
}

beforeEach(() => {
    jest.clearAllMocks();
    manager._resetForTests();
    delete process.env.MCP_ENABLED;
});

afterEach(() => {
    manager._resetForTests();
    delete process.env.MCP_ENABLED;
});

describe('init — MCP_ENABLED not set', () => {
    test('does nothing when MCP_ENABLED is absent', async () => {
        await manager.init();
        expect(manager.getToolCatalog()).toEqual([]);
        expect(sdkLoader.getSdk).not.toHaveBeenCalled();
    });

    test('is idempotent — calling init() twice is safe', async () => {
        await manager.init();
        await manager.init();
        expect(sdkLoader.getSdk).not.toHaveBeenCalled();
    });
});

describe('init — MCP_ENABLED=true', () => {
    beforeEach(() => { process.env.MCP_ENABLED = 'true'; });

    test('gracefully resolves when SDK load fails', async () => {
        sdkLoader.getSdk.mockRejectedValue(new Error('ESM load failed'));
        // Should not throw
        await manager.init();
        expect(manager.getToolCatalog()).toEqual([]);
    });

    test('gracefully skips a server that fails to connect', async () => {
        const fakeClient = makeFakeClient();
        fakeClient.connect.mockRejectedValue(new Error('spawn failed'));
        sdkLoader.getSdk.mockResolvedValue(makeFakeSdk({ filesystem: fakeClient }));

        const fs = require('fs');
        jest.spyOn(fs, 'readFileSync').mockReturnValueOnce(JSON.stringify({
            filesystem: { enabled: true, command: 'npx', args: ['-y', 'bad'], env: {} },
        }));

        await manager.init();
        expect(manager.getToolCatalog()).toEqual([]);
    });

    test('connects and builds namespaced tool catalog', async () => {
        const fakeClient = makeFakeClient([
            { name: 'read_file',  description: 'Read a file',  inputSchema: { type: 'object', properties: { path: { type: 'string' } } } },
            { name: 'write_file', description: 'Write a file', inputSchema: { type: 'object', properties: {} } },
        ]);
        sdkLoader.getSdk.mockResolvedValue(makeFakeSdk({ filesystem: fakeClient }));

        const fs = require('fs');
        jest.spyOn(fs, 'readFileSync').mockReturnValueOnce(JSON.stringify({
            filesystem: { enabled: true, command: 'npx', args: ['-y', 'server-filesystem', '/tmp'], env: {} },
        }));

        await manager.init();

        const catalog = manager.getToolCatalog();
        expect(catalog).toHaveLength(2);
        expect(catalog[0].function.name).toBe('filesystem__read_file');
        expect(catalog[1].function.name).toBe('filesystem__write_file');
        expect(catalog[0].type).toBe('function');
    });

    test('concurrent init() calls do not double-connect', async () => {
        const fs = require('fs');
        jest.spyOn(fs, 'readFileSync').mockReturnValue(JSON.stringify({}));
        sdkLoader.getSdk.mockResolvedValue({ Client: jest.fn(), StdioClientTransport: jest.fn() });

        await Promise.all([manager.init(), manager.init(), manager.init()]);
        expect(sdkLoader.getSdk).toHaveBeenCalledTimes(1);
    });
});

describe('callTool', () => {
    test('returns error string for invalid namespaced name', async () => {
        const result = await manager.callTool('badname', {});
        expect(result).toMatch(/invalid tool name/);
    });

    test('returns error string when server not connected', async () => {
        const result = await manager.callTool('missing__tool', {});
        expect(result).toMatch(/not connected/);
    });
});

describe('guardedCallTool', () => {
    test('returns policy_blocked when action is blocked', async () => {
        policyEngine.isBlockedAction.mockReturnValue(true);
        const result = await manager.guardedCallTool('mcp.unknown__anything', {}, { role: 'admin', plan: 'pro', explicitConsent: true });
        expect(result.error).toBe('policy_blocked');
        expect(result.code).toBe(403);
    });

    test('returns policy_denied (insufficient_permissions) when role lacks permission', async () => {
        policyEngine.isBlockedAction.mockReturnValue(false);
        policyEngine.isAllowedByRolePlan.mockReturnValue(false);
        const result = await manager.guardedCallTool('filesystem__read_file', {}, { role: 'member', plan: 'free', explicitConsent: true });
        expect(result.error).toBe('policy_denied');
        expect(result.reason).toBe('insufficient_permissions');
    });

    test('returns consent_required for sensitive tool without explicit consent', async () => {
        policyEngine.isBlockedAction.mockReturnValue(false);
        policyEngine.isAllowedByRolePlan.mockReturnValue(true);
        // filesystem__write_file is sensitive per toolPolicy
        const result = await manager.guardedCallTool('filesystem__write_file', {}, { role: 'admin', plan: 'pro', explicitConsent: false });
        expect(result.error).toBe('policy_denied');
        expect(result.reason).toBe('consent_required');
    });
});
