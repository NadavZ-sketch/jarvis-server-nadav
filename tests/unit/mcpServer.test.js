'use strict';

// Tests for mcp-server.js buildHandlers factory.
// The main() entrypoint is not tested here (requires a live transport);
// instead we test the handler logic in isolation.

jest.mock('../../services/policyEngine', () => ({
    isAllowedByRolePlan: jest.fn(() => true),
    isBlockedAction:     jest.fn(() => false),
}));

// Mock all agents used by the server
jest.mock('../../agents/taskAgent',     () => ({ runTaskAgent:     jest.fn() }));
jest.mock('../../agents/reminderAgent', () => ({ runReminderAgent: jest.fn() }));
jest.mock('../../agents/memoryAgent',   () => ({ runMemoryAgent:   jest.fn() }));
jest.mock('../../agents/notesAgent',    () => ({ runNotesAgent:    jest.fn() }));
jest.mock('../../agents/shoppingAgent', () => ({ runShoppingAgent: jest.fn() }));

// Mock sdkLoader so main() can be imported without triggering actual ESM load
jest.mock('../../services/mcp/sdkLoader', () => ({ getSdk: jest.fn() }));

// Mock supabase client creation
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn(() => ({})) }));

const { runTaskAgent }     = require('../../agents/taskAgent');
const { runReminderAgent } = require('../../agents/reminderAgent');
const { runMemoryAgent }   = require('../../agents/memoryAgent');
const policyEngine         = require('../../services/policyEngine');
const { buildHandlers, TOOLS } = require('../../mcp-server');

describe('buildHandlers — listTools', () => {
    test('returns all 5 Jarvis tools', async () => {
        const { listTools } = buildHandlers();
        const result = await listTools();
        expect(result.tools).toHaveLength(5);
        const names = result.tools.map(t => t.name);
        expect(names).toContain('jarvis_tasks');
        expect(names).toContain('jarvis_reminders');
        expect(names).toContain('jarvis_memory');
        expect(names).toContain('jarvis_notes');
        expect(names).toContain('jarvis_shopping');
    });

    test('each tool has name, description, and inputSchema', async () => {
        const { listTools } = buildHandlers();
        const { tools } = await listTools();
        for (const tool of tools) {
            expect(tool.name).toBeTruthy();
            expect(tool.description).toBeTruthy();
            expect(tool.inputSchema).toBeDefined();
            expect(tool.inputSchema.required).toContain('message');
        }
    });
});

describe('buildHandlers — callTool', () => {
    test('returns isError for unknown tool name', async () => {
        const { callTool } = buildHandlers();
        const result = await callTool({ params: { name: 'nonexistent', arguments: { message: 'hi' } } });
        expect(result.isError).toBe(true);
        expect(result.content[0].text).toMatch(/Unknown tool/);
    });

    test('calls runTaskAgent and returns answer', async () => {
        runTaskAgent.mockResolvedValueOnce({ answer: 'הוספתי משימה' });
        const { callTool } = buildHandlers();
        const result = await callTool({ params: { name: 'jarvis_tasks', arguments: { message: 'הוסף משימה חדשה' } } });
        expect(result.isError).toBeUndefined();
        expect(result.content[0].text).toBe('הוספתי משימה');
    });

    test('returns error content when agent throws', async () => {
        runReminderAgent.mockRejectedValueOnce(new Error('DB error'));
        const { callTool } = buildHandlers();
        const result = await callTool({ params: { name: 'jarvis_reminders', arguments: { message: 'תזכיר לי' } } });
        expect(result.isError).toBe(true);
        expect(result.content[0].text).toMatch(/DB error/);
    });

    test('returns error when message parameter is missing', async () => {
        const { callTool } = buildHandlers();
        const result = await callTool({ params: { name: 'jarvis_tasks', arguments: {} } });
        expect(result.isError).toBe(true);
        expect(result.content[0].text).toMatch(/Missing required parameter/);
    });

    test('blocks action when policy says blocked', async () => {
        policyEngine.isBlockedAction.mockReturnValueOnce(true);
        const { callTool } = buildHandlers();
        const result = await callTool({ params: { name: 'jarvis_memory', arguments: { message: 'test' } } });
        expect(result.isError).toBe(true);
        expect(result.content[0].text).toMatch(/blocked/);
    });

    test('denies when insufficient permissions', async () => {
        policyEngine.isBlockedAction.mockReturnValueOnce(false);
        policyEngine.isAllowedByRolePlan.mockReturnValueOnce(false);
        const { callTool } = buildHandlers();
        const result = await callTool({ params: { name: 'jarvis_notes', arguments: { message: 'test' } } });
        expect(result.isError).toBe(true);
        expect(result.content[0].text).toMatch(/Insufficient permissions/);
    });
});

describe('TOOLS export', () => {
    test('all tools have a handler function', () => {
        for (const tool of TOOLS) {
            expect(typeof tool.handler).toBe('function');
            expect(typeof tool.actionType).toBe('string');
        }
    });
});
