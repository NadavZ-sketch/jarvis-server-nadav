# Optional Parallel Search MCP

Jarvis can connect to [Parallel Search MCP](https://docs.parallel.ai/integrations/mcp/search-mcp)
for web search and page fetching without an account or API key. Anonymous search
uses Fast mode and is rate limited, so this setup is suited to exploration and
light use.

## Enable the connection

1. Install the server dependencies with `npm ci` (Node.js 20 or later).
2. In `config/mcpServers.json`, set only the `parallel` entry's `enabled` field to
   `true`. Keep its `streamable-http` transport, URL and project `User-Agent`
   header. There is no extra package or subprocess to install for this connection.
3. Set `MCP_ENABLED=true` in the server environment and restart Jarvis. Look for
   `[MCP] Connected to "parallel"` in the startup log.

Parallel is disabled by default. Enabling it adds tools to the existing catalog;
it does not replace Tavily, the fetch server or any LLM provider. Each other
enabled MCP server still connects according to its own configuration and
credentials. Set any servers you do not need to `enabled: false` separately.

The catalog exposes `parallel__web_search` and `parallel__web_fetch`. Both use
the existing `web.search` / `web.fetch` read permissions, including for a
`free` / `member` actor. Unknown tools keep the fail-closed policy.

## Try the client API

After enabling the preset, run this from the repository root. It searches for
Node.js release information and prints source URLs and excerpts:

```bash
MCP_ENABLED=true node <<'NODE'
const mcp = require('./services/mcp/mcpClientManager');

(async () => {
    try {
        await mcp.init();
        const tools = mcp.getToolCatalog();
        if (!tools.some(t => t.function.name === 'parallel__web_search')) {
            throw new Error('Parallel is not connected; check the preset and startup log');
        }
        const result = await mcp.guardedCallTool('parallel__web_search', {
            objective: 'Find the official Node.js release schedule with source links.',
            search_queries: ['Node.js official release schedule'],
        });
        console.log(result);
    } finally {
        await mcp.shutdown();
    }
})().catch(err => { console.error(err); process.exitCode = 1; });
NODE
```

To read a selected page, call `guardedCallTool('parallel__web_fetch',
{ urls: ['https://nodejs.org/en/about/previous-releases'] })`. Use the tool
schemas returned by `getToolCatalog()` for the current argument definitions.
Only send queries and URLs that you intend to share with the external service.

These are programmatic MCP client calls. The current `/ask-jarvis` and
`/stream-jarvis` chat handlers do not automatically use this catalog. An agent
can supply it to `agents/models.js`'s `callWithTools` and route tool calls through
`guardedCallTool` with that request's actor.

## Timeouts and errors

Connection and tool discovery share a 35-second timeout; a failed connection is
closed and skipped so other servers remain available. Tool calls use the SDK's
request timeout by default. Callers can pass SDK request options as the fourth
argument to `guardedCallTool`, for example:

```javascript
const controller = new AbortController();
const result = await mcp.guardedCallTool(
    'parallel__web_fetch',
    { urls: ['https://nodejs.org/en/about/previous-releases'] },
    { role: 'member', plan: 'free' },
    { timeout: 15000, signal: controller.signal }
);
```

Calling `controller.abort()` cancels an in-flight request. As with existing MCP
tools, transport failures, timeouts and cancellation become an error string in
`content`; `{ ok: true }` means the policy gate allowed execution, not that the
remote operation succeeded. Permission failures return `policy_denied` or
`policy_blocked`. A remote tool error or rate-limit message is returned as content;
inspect it before using the result and respect any retry instructions.
