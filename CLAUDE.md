# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm install          # install dependencies
node server.js       # start the server (port 3000 by default)
npm test             # run all unit tests (Jest)
npm run test:coverage # run tests with coverage report
npm run e2e          # run end-to-end self-tests against a live server
npm run e2e:local    # same but against localhost
```

Run a single test file:
```bash
npx jest tests/unit/router.test.js
```

Required `.env` variables: `GROQ_API_KEY`, `DEEPSEEK_API_KEY`, `GOOGLE_API_KEY`, `SUPABASE_URL`, `SUPABASE_KEY`, `GMAIL_USER`, `GMAIL_APP_PASSWORD`. Optional: `PINECONE_API_KEY`, `PINECONE_INDEX`, `OLLAMA_URL`, `OBSIDIAN_VAULT_PATH`.

## Architecture

### Request flow

Every user message enters through `POST /ask-jarvis` in `server.js`:

1. **Router** (`agents/router.js`) — classifies intent via Hebrew keyword regex. Falls back to an LLM call (Groq `llama-3.3-70b-versatile`) for messages >12 chars that don't match keywords. Returns one of ~20 intent strings (`task`, `reminder`, `memory`, `chat`, `weather`, `news`, `shopping`, `notes`, `stocks`, `translate`, `music`, `sports`, `messaging`, `draft`, `insight`, `security`, `code_error`, `e2e`, `factory`, `past_conv`).
2. **Follow-up override** — if a short message looks like a continuation (detected in `chatAgent.detectFollowUp`), the intent is overridden to `chat` regardless of routing.
3. **Context loading** — chat history (last 20 msgs, TTL-cached 30s) and long-term memories are loaded from Supabase. When Pinecone is ready, memories are retrieved via semantic search instead of keyword filtering.
4. **Agent dispatch** — `server.js` calls the matching `run*Agent()` function. `code_error` and `e2e` are dispatched via `setImmediate` (background, non-blocking) and return a placeholder answer immediately.
5. **Response** — answer + TTS audio (Google TTS, Hebrew `iw`) + optional `action` object returned as JSON. History saved to Supabase; `autoExtractMemory` runs fire-and-forget to passively save personal facts.

### LLM stack (`agents/models.js`)

`callGemma4()` tries providers in order: **Ollama (local)** → **Groq** → **DeepSeek** → **Gemini**. All cloud providers are OpenAI-compatible except Gemini.  
`callGemma4Stream()` is the SSE streaming version used by `/stream-jarvis`.  
`callGeminiWithSearch()` enables Google Search grounding (used by news/weather agents).  
`callGeminiVision()` handles image+text (used when `imageBase64` is present).

### Agents (`agents/`)

Each agent exports a single `run*Agent(userMessage, ...)` function and returns `{ answer: string, action?: object }`. Agents are stateless — all persistence goes through Supabase or Pinecone passed as parameters.

- **`router.js`** — intent classification only; no LLM calls unless keyword match fails.
- **`chatAgent.js`** — main conversational agent. Builds a rich Hebrew system prompt including personality, gender, memories, history, and datetime. Supports `voiceMode` (shorter, markdown-free answers).
- **`memoryAgent.js`** — save/recall/delete personal facts. Also exports `autoExtractMemory` (passive extraction called after every chat turn).
- **`agentFactoryAgent.js`** — dynamically creates new custom agents at runtime. Writes JS files to `agents/custom/` and registers them in `agents/custom/registry.json`. Custom agents are hot-loaded via `tryCustomAgent()` in `server.js`.
- **`e2eAgent.js`** / **`securityAgent.js`** / **`codeErrorAgent.js`** — quality & security tools that scan source files and persist findings to `e2e_reports` in Supabase.

### Memory & storage

| Store | Used for |
|-------|----------|
| Supabase | chat_history, tasks, reminders, notes, memories, contacts, shopping_items, e2e_reports, user_surveys |
| Pinecone | Semantic vector search over memories (optional — falls back to keyword search when not ready) |
| In-process TTL cache | memories (5 min), chat_history per chatId (30 s) |
| Local filesystem | `backlog.json`, `features.json`, `notes.json`, `agents/custom/registry.json` |
| Obsidian vault | Mirror of memories + chat messages via `services/obsidianSync.js` |

### Cron jobs (server.js)

- Every minute: fire due reminders (marks `fired=true`; reschedules recurring ones).
- 07:00 Jerusalem: morning briefing notification.
- 21:00 Jerusalem: evening nudge if open tasks exist.
- Every 5 min: Obsidian vault sync.

### Adding a new agent

1. Create `agents/myAgent.js` exporting `runMyAgent(userMessage, supabase, useLocal, settings)`.
2. Add a keyword pattern to `KEYWORDS` in `agents/router.js` and the intent name to `VALID_INTENTS` and `LLM_CLASSIFY_PROMPT`.
3. Add a dispatch branch in the `if/else` chain inside `POST /ask-jarvis` in `server.js`.
4. Mirror the same addition in `/stream-jarvis` if streaming support is needed.

### Flutter mobile app

Located in `jarvis_mobile/`. Communicates with the server via HTTP. Main endpoints it uses: `POST /ask-jarvis`, `GET /chat-history`, `POST /stream-jarvis`, `GET /check-reminders` (polled), `GET /tasks`, `GET /notes`, `GET /reminders`, `GET /shopping`, `GET /contacts`, `GET /calendar-events`, `GET /stats`.

The `settings` object sent with each request controls: `useLocalModel`, `ttsEnabled`, `userName`, `assistantName`, `gender`, `personality`, `voiceMode`.
