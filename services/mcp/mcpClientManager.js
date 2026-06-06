'use strict';

// MCP Client Manager — singleton that manages connections to external MCP servers.
//
// Design principles:
// - init() is idempotent and never rejects: each server connection is isolated
//   in its own try/catch so a single failing server cannot block Jarvis boot.
// - getToolCatalog() returns [] when nothing is connected (callWithTools then
//   behaves like a plain LLM completion — graceful degradation).
// - callTool() returns a structured error string instead of throwing, so the
//   tool-calling loop can continue rather than crash.
// - guardedCallTool() gates execution through the policy engine before calling.
// - All SDK access goes through sdkLoader (CJS→ESM dynamic-import bridge).

const fs   = require('fs');
const path = require('path');
const { getSdk }   = require('./sdkLoader');
const { getPolicy } = require('./toolPolicy');

const CONFIG_PATH        = path.join(__dirname, '../../config/mcpServers.json');
const CONNECT_TIMEOUT_MS = 15000;

let _initialized  = false;
let _initializing = null; // in-flight init promise (prevents concurrent calls)
const _clients    = {};   // serverName → { client, tools: MCP tool descriptors[] }
let _catalog      = null; // cached OpenAI-schema tool list

// ─── Env-var expansion ────────────────────────────────────────────────────────

function _expandEnv(str) {
    if (typeof str !== 'string') return str;
    return str.replace(/\$\{([^}]+)\}/g, (_, name) => process.env[name] || '');
}

function _expandConfig(server) {
    const args = (server.args || []).map(_expandEnv);
    const env  = {};
    for (const [k, v] of Object.entries(server.env || {})) {
        const expanded = _expandEnv(v);
        if (expanded) env[k] = expanded; // skip empty (missing key)
    }
    return { ...server, args, env };
}

// ─── Single-server connection ─────────────────────────────────────────────────

async function _connectServer(name, config, { Client, StdioClientTransport }) {
    const expanded = _expandConfig(config);

    const transport = new StdioClientTransport({
        command: expanded.command,
        args:    expanded.args,
        env:     { ...process.env, ...expanded.env },
    });

    const client = new Client(
        { name: `jarvis-${name}`, version: '1.0.0' },
        { capabilities: {} }
    );

    await Promise.race([
        client.connect(transport),
        new Promise((_, reject) =>
            setTimeout(() => reject(new Error(`connect timeout (${CONNECT_TIMEOUT_MS}ms)`)), CONNECT_TIMEOUT_MS)
        ),
    ]);

    const { tools } = await client.listTools();
    return { client, tools };
}

// ─── init ─────────────────────────────────────────────────────────────────────

async function init() {
    if (_initialized) return;
    if (_initializing) return _initializing;

    _initializing = _doInit().finally(() => { _initializing = null; });
    return _initializing;
}

async function _doInit() {
    if (process.env.MCP_ENABLED !== 'true') {
        _initialized = true;
        return;
    }

    let config;
    try {
        config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    } catch (err) {
        console.warn('[MCP] Could not load config/mcpServers.json:', err.message);
        _initialized = true;
        return;
    }

    let sdk;
    try {
        sdk = await getSdk();
    } catch (err) {
        console.warn('[MCP] Could not load SDK:', err.message);
        _initialized = true;
        return;
    }

    const { Client, StdioClientTransport } = sdk;

    for (const [name, serverConfig] of Object.entries(config)) {
        if (!serverConfig.enabled) continue;
        try {
            const result = await _connectServer(name, serverConfig, { Client, StdioClientTransport });
            _clients[name] = result;
            console.info(`[MCP] Connected to "${name}" — ${result.tools.length} tools`);
        } catch (err) {
            console.warn(`[MCP] Failed to connect to "${name}": ${err.message} — skipping`);
        }
    }

    _catalog = null; // invalidate any pre-existing catalog
    _initialized = true;
}

// ─── Tool catalog ─────────────────────────────────────────────────────────────

// Returns OpenAI-compatible tool schemas for all connected servers.
// Tool names are namespaced as "{server}__{toolName}" to avoid collisions
// and to allow callTool to route to the right client.
function getToolCatalog() {
    if (!_initialized) return [];
    if (_catalog) return _catalog;

    const catalog = [];
    for (const [serverName, { tools }] of Object.entries(_clients)) {
        for (const tool of tools) {
            catalog.push({
                type: 'function',
                function: {
                    name:        `${serverName}__${tool.name}`,
                    description: tool.description || '',
                    parameters:  tool.inputSchema || { type: 'object', properties: {} },
                },
            });
        }
    }
    _catalog = catalog;
    return catalog;
}

// ─── Tool execution ───────────────────────────────────────────────────────────

// Raw call — no policy gate. Returns a content string, never throws.
async function callTool(namespacedName, args) {
    const sep = namespacedName.indexOf('__');
    if (sep === -1) {
        return `Error: invalid tool name "${namespacedName}" — expected "server__toolName"`;
    }
    const serverName = namespacedName.slice(0, sep);
    const toolName   = namespacedName.slice(sep + 2);

    const entry = _clients[serverName];
    if (!entry) {
        return `Error: MCP server "${serverName}" is not connected`;
    }

    try {
        const result = await entry.client.callTool({ name: toolName, arguments: args || {} });
        if (Array.isArray(result.content)) {
            return result.content.map(c => c.text || JSON.stringify(c)).join('\n');
        }
        return typeof result.content === 'string' ? result.content : JSON.stringify(result.content);
    } catch (err) {
        console.warn(`[MCP] callTool "${namespacedName}" error:`, err.message);
        return `Error calling tool ${namespacedName}: ${err.message}`;
    }
}

// Policy-gated call. Returns { ok, content } on success or { error, code, ... } on denial.
// actor: { role, plan, explicitConsent? }  — defaults to most-restricted free/member.
async function guardedCallTool(namespacedName, args, actor = { role: 'member', plan: 'free' }) {
    const policy = getPolicy(namespacedName);

    // Lazy require to avoid circular-dependency at module load time.
    const { isAllowedByRolePlan, isBlockedAction } = require('../policyEngine');

    if (isBlockedAction(policy.actionType)) {
        return { error: 'policy_blocked', code: 403, tool: namespacedName };
    }
    if (!isAllowedByRolePlan({ actionType: policy.actionType, role: actor.role, plan: actor.plan })) {
        return { error: 'policy_denied', code: 403, tool: namespacedName, reason: 'insufficient_permissions' };
    }
    if (policy.sensitive && !actor.explicitConsent) {
        return { error: 'policy_denied', code: 403, tool: namespacedName, reason: 'consent_required' };
    }

    const content = await callTool(namespacedName, args);
    return { ok: true, content };
}

// ─── Shutdown ─────────────────────────────────────────────────────────────────

async function shutdown() {
    for (const [name, { client }] of Object.entries(_clients)) {
        try { await client.close(); }
        catch (err) { console.warn(`[MCP] Error closing "${name}":`, err.message); }
    }
    _initialized = false;
    _catalog     = null;
    Object.keys(_clients).forEach(k => delete _clients[k]);
}

// Reset all state — for tests only.
function _resetForTests() {
    _initialized  = false;
    _initializing = null;
    _catalog      = null;
    Object.keys(_clients).forEach(k => delete _clients[k]);
}

module.exports = { init, getToolCatalog, callTool, guardedCallTool, shutdown, _resetForTests };
