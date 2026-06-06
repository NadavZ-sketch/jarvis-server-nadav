'use strict';

// CJS→ESM bridge for @modelcontextprotocol/sdk.
//
// The SDK is ESM-only (has an ESM-only transitive dependency, pkce-challenge).
// Calling require('@modelcontextprotocol/sdk') directly from a CommonJS module
// throws ERR_REQUIRE_ESM. All SDK access in Jarvis goes through this file via
// dynamic import(), which Node supports from CJS since v12.
//
// The resolved module map is cached after the first call so the async overhead
// is paid only once per process lifetime.

let _cache = null;

async function getSdk() {
    if (_cache) return _cache;

    const [clientMod, clientStdioMod, serverMod, serverStdioMod, typesMod] = await Promise.all([
        import('@modelcontextprotocol/sdk/client/index.js'),
        import('@modelcontextprotocol/sdk/client/stdio.js'),
        import('@modelcontextprotocol/sdk/server/index.js'),
        import('@modelcontextprotocol/sdk/server/stdio.js'),
        import('@modelcontextprotocol/sdk/types.js').catch(() => ({})),
    ]);

    _cache = {
        Client: clientMod.Client,
        StdioClientTransport: clientStdioMod.StdioClientTransport,
        Server: serverMod.Server,
        StdioServerTransport: serverStdioMod.StdioServerTransport,
        ListToolsRequestSchema: typesMod.ListToolsRequestSchema,
        CallToolRequestSchema: typesMod.CallToolRequestSchema,
    };
    return _cache;
}

// Reset cache — for tests only.
function _resetSdkCache() { _cache = null; }

module.exports = { getSdk, _resetSdkCache };
