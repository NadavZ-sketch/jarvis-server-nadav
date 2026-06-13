'use strict';
// ─── Jarvis MCP Server — exposes Jarvis agents as MCP tools ──────────────────
//
// Run as a standalone process:  node mcp-server.js
// Or via npm:                   npm run mcp:server
//
// Add to Claude Desktop config (see config/claude_desktop_config.example.json).
//
// Exposed tools:
//   jarvis_tasks      — manage tasks (create, list, complete)
//   jarvis_reminders  — manage reminders
//   jarvis_memory     — save / recall memories
//   jarvis_notes      — create and search notes
//   jarvis_shopping   — manage shopping list
//
// Each tool takes a single `message` parameter (Hebrew or English natural
// language) and returns the agent's text response.

require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

// Agents — reuse existing functions directly.
const { runTaskAgent }     = require('./agents/taskAgent');
const { runReminderAgent } = require('./agents/reminderAgent');
const { runMemoryAgent }   = require('./agents/memoryAgent');
const { runNotesAgent }    = require('./agents/notesAgent');
const { runShoppingAgent } = require('./agents/shoppingAgent');
const { getSdk }           = require('./services/mcp/sdkLoader');
const { getPolicy }        = require('./services/mcp/toolPolicy');
const { isAllowedByRolePlan, isBlockedAction } = require('./services/policyEngine');

// ─── Supabase client ──────────────────────────────────────────────────────────
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_KEY
);
const { createRepos } = require('./services/dataAccess');
const repos = createRepos(supabase);

// Settings passed to each agent (Claude Desktop operator is implicitly admin).
const DEFAULT_SETTINGS = {
    userName:        process.env.MCP_USER_NAME    || 'user',
    assistantName:   'Jarvis',
    language:        'he',
    useLocal:        process.env.MCP_USE_LOCAL    === 'true',
};

// Actor for policy checks — defaults to pro/admin so Claude Desktop has full
// access. Override via env MCP_ACTOR_ROLE / MCP_ACTOR_PLAN for tighter control.
const DEFAULT_ACTOR = {
    role: process.env.MCP_ACTOR_ROLE || 'admin',
    plan: process.env.MCP_ACTOR_PLAN || 'pro',
    explicitConsent: true,
};

// ─── Tool definitions ─────────────────────────────────────────────────────────
const TOOLS = [
    {
        name:        'jarvis_tasks',
        description: 'Manage personal tasks: create, list, complete, or delete tasks. Speak naturally in Hebrew or English.',
        inputSchema: {
            type: 'object',
            properties: {
                message: { type: 'string', description: 'Your task-related request in Hebrew or English' },
            },
            required: ['message'],
        },
        handler: (message) => runTaskAgent(message, repos, DEFAULT_SETTINGS.useLocal, DEFAULT_SETTINGS),
        actionType: 'tasks.manage',
    },
    {
        name:        'jarvis_reminders',
        description: 'Set, list, or delete reminders. Supports recurring reminders. Speak naturally.',
        inputSchema: {
            type: 'object',
            properties: {
                message: { type: 'string', description: 'Your reminder request in Hebrew or English' },
            },
            required: ['message'],
        },
        handler: (message) => runReminderAgent(message, repos),
        actionType: 'reminders.manage',
    },
    {
        name:        'jarvis_memory',
        description: 'Save, recall, or delete personal memories and facts about the user.',
        inputSchema: {
            type: 'object',
            properties: {
                message: { type: 'string', description: 'Memory-related request: save a fact, recall something, or delete a memory' },
            },
            required: ['message'],
        },
        handler: (message) => runMemoryAgent(message, repos, DEFAULT_SETTINGS.useLocal, DEFAULT_SETTINGS),
        actionType: 'memory.manage',
    },
    {
        name:        'jarvis_notes',
        description: 'Create, search, or delete quick notes.',
        inputSchema: {
            type: 'object',
            properties: {
                message: { type: 'string', description: 'Notes request in Hebrew or English' },
            },
            required: ['message'],
        },
        handler: (message) => runNotesAgent(message, supabase, DEFAULT_SETTINGS.useLocal, DEFAULT_SETTINGS),
        actionType: 'notes.manage',
    },
    {
        name:        'jarvis_shopping',
        description: 'Manage shopping list: add items, view list, mark items as bought, clear list.',
        inputSchema: {
            type: 'object',
            properties: {
                message: { type: 'string', description: 'Shopping list request in Hebrew or English' },
            },
            required: ['message'],
        },
        handler: (message) => runShoppingAgent(message, supabase, DEFAULT_SETTINGS.useLocal, DEFAULT_SETTINGS),
        actionType: 'shopping.manage',
    },
];

const TOOLS_BY_NAME = Object.fromEntries(TOOLS.map(t => [t.name, t]));

// ─── Handler factory (exported for unit tests) ────────────────────────────────

function buildHandlers(agents = TOOLS_BY_NAME) {
    async function listTools() {
        return {
            tools: Object.values(agents).map(t => ({
                name:        t.name,
                description: t.description,
                inputSchema: t.inputSchema,
            })),
        };
    }

    async function callTool(request) {
        const { name, arguments: args } = request.params;
        const tool = agents[name];

        if (!tool) {
            return {
                content: [{ type: 'text', text: `Unknown tool: ${name}` }],
                isError: true,
            };
        }

        // Policy gate
        if (isBlockedAction(tool.actionType)) {
            return { content: [{ type: 'text', text: `Action "${tool.actionType}" is blocked by policy.` }], isError: true };
        }
        if (!isAllowedByRolePlan({ actionType: tool.actionType, role: DEFAULT_ACTOR.role, plan: DEFAULT_ACTOR.plan })) {
            return { content: [{ type: 'text', text: `Insufficient permissions for "${tool.actionType}".` }], isError: true };
        }

        try {
            const message = args?.message;
            if (!message || typeof message !== 'string') {
                return { content: [{ type: 'text', text: 'Missing required parameter: message' }], isError: true };
            }

            const result = await tool.handler(message);
            return {
                content: [{ type: 'text', text: result.answer || 'Done.' }],
            };
        } catch (err) {
            console.error(`[MCP Server] tool "${name}" error:`, err.message);
            return {
                content: [{ type: 'text', text: `Error: ${err.message}` }],
                isError: true,
            };
        }
    }

    return { listTools, callTool };
}

// ─── Main entrypoint ──────────────────────────────────────────────────────────

async function main() {
    const { Server, StdioServerTransport, ListToolsRequestSchema, CallToolRequestSchema } = await getSdk();

    const server = new Server(
        { name: 'jarvis', version: '1.0.0' },
        { capabilities: { tools: {} } }
    );

    const handlers = buildHandlers();
    server.setRequestHandler(ListToolsRequestSchema, handlers.listTools);
    server.setRequestHandler(CallToolRequestSchema,  handlers.callTool);

    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error('[Jarvis MCP Server] Running on stdio');
}

if (require.main === module) {
    main().catch(err => {
        console.error('[Jarvis MCP Server] Fatal error:', err);
        process.exit(1);
    });
}

module.exports = { buildHandlers, TOOLS };
