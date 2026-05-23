# CLAUDE.md

Comprehensive guidance for Claude Code (claude.ai/code) working in this Jarvis server repository—an intelligent Hebrew-language personal assistant backend with ~5400 lines of JS, 24 agents, multiple integrations, and full test coverage.

## Quick Start

### Installation & Setup

```bash
npm install                    # install dependencies
node server.js                 # start the server (port 3000 by default)
```

### Testing

```bash
npm test                       # run all unit + integration tests (Jest)
npm run test:coverage          # run with coverage report
npm run e2e                    # run end-to-end self-tests against production
npm run e2e:local              # run e2e tests against localhost
npx jest tests/unit/router.test.js  # run a single test file
```

### Linting & Code Quality

```bash
npm run lint                   # syntax validation via scripts/lint-syntax.js
```

### Required & Optional Environment Variables

**Required:**
- `GROQ_API_KEY` — Groq API for LLM inference (fallback provider)
- `DEEPSEEK_API_KEY` — DeepSeek API (fallback provider)
- `GOOGLE_API_KEY` — Google Search + Gemini API (news, weather, vision)
- `SUPABASE_URL` — Supabase database endpoint
- `SUPABASE_KEY` — Supabase anon/service key
- `GMAIL_USER` — Gmail account for sending notifications
- `GMAIL_APP_PASSWORD` — Gmail app-specific password

**Optional:**
- `PINECONE_API_KEY`, `PINECONE_INDEX` — Semantic memory search (falls back to keyword if absent)
- `OLLAMA_URL` — Local LLM inference endpoint (e.g., `http://localhost:11434`)
- `OBSIDIAN_VAULT_PATH` — Local Obsidian vault path for syncing memories

## Architecture Overview

### Request Flow

Every user message enters through `POST /ask-jarvis` (and `POST /stream-jarvis` for SSE streaming):

1. **Intent Classification** (`agents/router.js::classifyIntent`)
   - Fast path: Hebrew keyword regex matching against 20 intent types
   - Fallback path: LLM classification (Groq `llama-3.3-70b-versatile`) for >12 char messages that don't match keywords
   - Returns intent string: `task`, `reminder`, `memory`, `chat`, `weather`, `news`, `shopping`, `notes`, `stocks`, `translate`, `music`, `sports`, `messaging`, `draft`, `insight`, `security`, `code_error`, `e2e`, `factory`, `past_conv`

2. **Follow-up Detection** (`chatAgent.detectFollowUp`)
   - Short messages that look like continuations override intent to `chat` regardless of routing

3. **Context Loading**
   - Chat history (last 20 messages, TTL-cached 30s) from Supabase
   - Long-term memories: Pinecone semantic search if available, else keyword filtering
   - User profile (personality, gender, name, preferences)

4. **Agent Dispatch** (`server.js` → `run*Agent()`)
   - Calls the matching agent function with `(userMessage, supabase, useLocal, settings)`
   - `code_error` and `e2e` agents run in background (`setImmediate`), return placeholder immediately
   - Custom agents loaded dynamically from `agents/custom/registry.json`

5. **Response Assembly**
   - Answer text from agent
   - TTS audio (Google TTS, Hebrew `iw-IL` voice)
   - Optional `action` object (e.g., `{ type: 'reminder_set', data: {...} }`)
   - Chat history persisted to Supabase
   - Memory extraction via `autoExtractMemory` (fire-and-forget)

### LLM Stack (`agents/models.js`)

All LLM calls go through a provider failover chain:

- **`callGemma4()`** — Main inference endpoint
  - Tries: Ollama (local) → Groq → DeepSeek → Gemini (cloud)
  - OpenAI-compatible except Gemini
  
- **`callGemma4Stream()`** — Streaming version used by `/stream-jarvis` for real-time responses
  
- **`callGeminiWithSearch()`** — Google Search grounding (used by `newsAgent`, `weatherAgent`)
  
- **`callGeminiVision()`** — Multimodal image+text inference (when `imageBase64` in request)

### Agents Directory Structure

Each agent exports a single `run*Agent(userMessage, supabase, useLocal, settings)` → `{ answer: string, action?: object }`. Agents are stateless; all persistence goes through Supabase or Pinecone.

#### Core Agents

| File | Exported | Purpose |
|------|----------|---------|
| `router.js` | `classifyIntent`, `classifyIntentWithLLM` | Intent classification only |
| `chatAgent.js` | `runChatAgent` | Main conversational AI; builds rich Hebrew system prompt with memories, history, personality |
| `memoryAgent.js` | `runMemoryAgent`, `autoExtractMemory` | Save/recall/delete personal facts; passive extraction after every turn |
| `taskAgent.js` | `runTaskAgent` | Manage task creation, completion, listing |
| `reminderAgent.js` | `runReminderAgent` | Set/recall/snooze/delete reminders with recurring support |
| `shoppingAgent.js` | `runShoppingAgent` | Shopping list CRUD |
| `notesAgent.js` | `runNotesAgent` | Quick notes/memo storage and search |

#### Domain-Specific Agents

| File | Exported | Purpose |
|------|----------|---------|
| `weatherAgent.js` | `runWeatherAgent` | Current weather, forecasts via Gemini Search |
| `newsAgent.js` | `runNewsAgent` | Latest news headlines via Gemini Search |
| `stocksAgent.js` | `runStocksAgent` | Stock quotes, market data |
| `sportsAgent.js` | `runSportsAgent` | Sports scores, team standings |
| `messagingAgent.js` | `runMessagingAgent` | Draft + send emails, WhatsApp templates |
| `translationAgent.js` | `runTranslationAgent` | Hebrew ↔ English/other languages |
| `musicAgent.js` | `runMusicAgent` | Spotify playlist, music recommendations |

#### Quality & Extensibility Agents

| File | Exported | Purpose |
|------|----------|---------|
| `agentFactoryAgent.js` | `runAgentFactoryAgent` | Create custom agents at runtime; writes to `agents/custom/` |
| `e2eAgent.js` | `runE2EAgent`, utility exports | End-to-end test runner; scans codebase, persists findings to Supabase |
| `securityAgent.js` | `runSecurityAgent` | Security audit, code scanning |
| `codeErrorAgent.js` | `runCodeErrorAgent` | Static error detection in source files |
| `insightAgent.js` | `runInsightAgent` | Usage analytics, habit analysis, personalized tips |
| `draftAgent.js` | `runDraftAgent` | Help compose messages, emails, documents |
| `surveyAgent.js` | `runSurveyAgent`, survey utilities | User surveys and feedback collection |

#### Supporting Utilities

| File | Purpose |
|------|---------|
| `utils.js` | Shared agent utilities |
| `models.js` | LLM provider abstraction layer |

### Services Layer (`services/`)

| File | Purpose |
|------|---------|
| `agentRegistryService.js` | Manages custom agent registration, loading, validation |
| `pineconeMemory.js` | Semantic vector search over memories via Pinecone SDK |
| `obsidianSync.js` | Bidirectional sync of memories + chat history to local Obsidian vault |
| `conversationSummary.js` | Summarize long chat histories for context-aware responses |
| `policyEngine.js` | Role-based access control (RBAC); `isAllowedByRolePlan()`, `isBlockedAction()` |

### Controllers & Routes

| File | Routes | Purpose |
|------|--------|---------|
| `controllers/chatController.js` | Chat endpoints | Chat history CRUD |
| `controllers/tasksController.js` | Task endpoints | Task CRUD |
| `controllers/remindersController.js` | Reminder endpoints | Reminder CRUD + firing logic |
| `routes/chat.js` | `/chat-history` | Create chat router |
| `routes/tasks.js` | `/tasks`, `/tasks/:id` | Create tasks router |
| `routes/reminders.js` | `/reminders`, `/reminders/:id` | Create reminders router |
| `routes/agentCenter.js` | `/agent-center` | Serve agent dashboard HTML |
| `routes/wsJarvis.js` | `ws://` | WebSocket support for real-time streaming |

### Memory & Storage

| Store | Used for |
|-------|----------|
| **Supabase** | `chat_history`, `tasks`, `reminders`, `notes`, `memories`, `contacts`, `shopping_items`, `e2e_reports`, `user_surveys` |
| **Pinecone** | Semantic vector search over memories (optional; falls back to keyword matching if unavailable) |
| **In-process TTL cache** | Memories (5 min), chat history per `chatId` (30 s) |
| **Local filesystem** | `backlog.json`, `features.json`, `notes.json`, `agents/custom/registry.json` |
| **Obsidian vault** | Mirror of memories + chat via `services/obsidianSync.js` (one-way or bidirectional per config) |

### Cron Jobs (scheduled via `node-cron`)

All times in Jerusalem timezone (`Asia/Jerusalem`):

- **Every minute** — Fire due reminders (mark `fired=true`; reschedule recurring ones via `remindersController.fire()`)
- **07:00 daily** — Morning briefing notification
- **21:00 daily** — Evening nudge if open tasks exist
- **Every 5 minutes** — Obsidian vault sync via `obsidianSync.sync()`

### Policy & Consent System

Implemented via `server.js` policy engine and `policyEngine.js`:

- **Role-based access control (RBAC)** — `member`, `admin`, `free`, `pro` tiers with different permissions
- **Sensitive action gating** — Certain actions (contact management, messaging, security scans) require explicit consent
- **Policy audit trail** — All policy decisions logged (500-entry circular buffer)
- **Consent ledger** — Per-user consent tracking by domain (contacts, messaging, etc.)
- **Middleware** — `requirePolicy(actionType, { sensitive?, irreversible? })` guards endpoints

Example gated endpoints:
- `POST /send-email` — requires `messaging.send` permission (sensitive, irreversible)
- `POST /contacts` — requires `contacts.create` permission (sensitive)
- `DELETE /contacts/:id` — requires `contacts.delete` permission (sensitive, irreversible)

### API Endpoints Summary

| Method | Path | Handler | Notes |
|--------|------|---------|-------|
| `POST` | `/ask-jarvis` | Main agent dispatch | Core endpoint; returns `{ answer, audio?, action? }` |
| `POST` | `/stream-jarvis` | Streaming agent dispatch | SSE response with `data: {json}` chunks |
| `POST` | `/transcribe` | Groq Whisper | Audio → text transcription |
| `GET` | `/health` | Server status | Health check |
| `GET` | `/check-reminders` | Fire due reminders | Polled by mobile app |
| `POST` | `/send-email` | Nodemailer | Requires policy |
| `GET` | `/chat-history` | Retrieve chat | Optional `chatId` query param |
| `DELETE` | `/chat-history/:chatId` | Delete chat session | Irreversible |
| `GET/POST` | `/tasks`, `/tasks/:id` | Task CRUD | Returns `{ tasks: [] }`; create body: `{ content, priority }` |
| `GET/POST` | `/reminders`, `/reminders/:id` | Reminder CRUD | Returns `{ reminders: [] }`; create body: `{ text, scheduled_time (ISO), recurrence? }` |
| `GET/POST/PUT/DELETE` | `/notes`, `/notes/:id` | Notes CRUD | — |
| `GET/POST/DELETE` | `/shopping`, `/shopping/:id` | Shopping CRUD | — |
| `GET/POST/PUT/DELETE` | `/contacts`, `/contacts/:id` | Contacts CRUD | Requires policy |
| `GET` | `/user-profile` | User settings | Reads `userName`, `gender`, `personality`, etc. |
| `POST` | `/user-profile` | Update settings | Persists to Supabase |
| `DELETE` | `/user-profile` | Hard delete profile | Irreversible |
| `GET` | `/survey-check` | Pending surveys | Returns survey queue |
| `POST` | `/survey-submit` | Submit survey responses | Saves to Supabase |
| `GET` | `/stats` | Usage analytics | Message count, agent usage breakdown, etc. |
| `GET` | `/today-message` | Daily motivational | Cached 24h |
| `GET` | `/e2e-reports` | List test runs | All or filtered by status |
| `GET` | `/e2e-reports/:runId` | Single test report | Full details + remediation suggestions |
| `POST` | `/e2e-reports/:runId/prompt` | Re-analyze report | Re-run e2e analysis with new context |
| `POST` | `/e2e-reports/:runId/mark-done` | Mark issue resolved | Clears report |
| `GET` | `/scan/errors` | Scan codebase for errors | Rate-limited (5/min) |
| `POST` | `/sync/obsidian` | Trigger manual Obsidian vault sync | Requires `OBSIDIAN_VAULT_PATH` env var |
| `POST` | `/sync/obsidian/auto` | Enable/disable auto-sync | Body: `{"enabled": true\|false}`; persists to Supabase |
| `POST` | `/dashboard/smart-telemetry` | Record a telemetry event | Body: `{event_type, payload?, user_id?}` |
| `GET` | `/dashboard/smart-telemetry` | Fetch telemetry events | Optional `?user_id=` filter |
| `DELETE` | `/dashboard/smart-telemetry/history` | Delete all telemetry events for a user | Body/query: `{userId}` |
| `POST` | `/dashboard/smart-telemetry/reset` | Reset telemetry (from settings screen) | Body: `{"scope":"user"}`; deletes all events |
| `GET` | `/agent-center` | Dashboard HTML | 7-tab control center: overview, agents, memory, tasks, reminders, settings, performance |
| `ws` | `/ws-jarvis` | WebSocket stream | Real-time bidirectional agent chat |

## Development Workflows

### Adding a New Agent

1. Create `agents/myAgent.js`:
   ```javascript
   function runMyAgent(userMessage, supabase, useLocal, settings) {
     return { answer: "...", action?: {...} };
   }
   module.exports = { runMyAgent };
   ```

2. Register in `agents/router.js`:
   - Add keyword pattern to `KEYWORDS` object
   - Ensure keyword catches all natural Hebrew queries for your intent

3. Add intent to `router.js`:
   - Add to `VALID_INTENTS` array
   - Add case to `LLM_CLASSIFY_PROMPT` for fallback classification

4. Dispatch in `server.js`:
   - Import: `const { runMyAgent } = require('./agents/myAgent');`
   - Add case in `POST /ask-jarvis` if/else chain:
     ```javascript
     case 'myintent':
       return await runMyAgent(userMessage, supabase, useLocal, settings);
     ```
   - Mirror in `POST /stream-jarvis` if streaming is needed

5. Test:
   - Unit test: `tests/unit/myAgent.test.js`
   - Integration test: `tests/integration/` if it touches Supabase
   - Verify keyword regex catches Hebrew variants

### Creating Custom Agents at Runtime

Users can request the `factory` agent to dynamically create custom agents:

```
צור אייג'נט לשם "תזכיר קניות" שמנהל רשימת קניות בדרך חלקלקה
Create agent named "shopping reminder" that manages a shopping list smoothly
```

The `agentFactoryAgent.js` will:
1. Generate JS code for the new agent
2. Write to `agents/custom/{agentName}.js`
3. Register in `agents/custom/registry.json`
4. Hot-load via `tryCustomAgent()` in main flow

Lifetime: custom agents persist until explicitly deleted.

### Modifying Intent Routing

When changing intent classification logic:
- Update `KEYWORDS` regex patterns in `router.js` (affects fast path)
- Update `LLM_CLASSIFY_PROMPT` in `router.js` (affects LLM fallback)
- Test with `npx jest tests/unit/router.test.js`
- Check for cross-intent keyword collisions (e.g., `תזכיר` = reminder *and* memory)

### Adding Supabase Tables

1. Design schema (DDL)
2. Apply migration via Supabase web UI or SDK
3. Update code to use new table
4. Add tests that mock or provision the table
5. Update `.env` if new API keys needed

### WebSocket Support

The server exposes a WebSocket endpoint at `/ws-jarvis` via `routes/wsJarvis.js`:
- Allows real-time streaming of agent responses
- Mobile clients can upgrade to ws:// for low-latency chat
- Maintains per-connection message queue and context

### Running Tests

```bash
# All tests
npm test

# With coverage report
npm run test:coverage

# Specific test file
npx jest tests/unit/chatAgent.test.js --verbose

# Watch mode (re-run on file changes)
npx jest --watch

# E2E against local server (requires running node server.js separately)
npm run e2e:local
```

Test structure:
- `tests/unit/` — Agent unit tests, isolated mocks, fast (~50ms each)
- `tests/integration/` — End-to-end flows touching Supabase, slower (~1-5s each)
- `tests/e2e/` — Full server tests via HTTP, slowest (~5-30s each)

## File Organization

```
jarvis-server-nadav/
├── server.js                    # Main Express app, request routing, cron setup
├── package.json                 # Dependencies, Jest config
├── .env.example                 # Example environment variables
├── README.md                     # Project overview
├── CLAUDE.md                     # This file
├── AUDIT.md                      # Security + architecture audit
│
├── agents/                       # Core agent implementations
│   ├── router.js                # Intent classification
│   ├── chatAgent.js             # Main conversational AI
│   ├── memoryAgent.js           # Memory CRUD + extraction
│   ├── taskAgent.js             # Task management
│   ├── reminderAgent.js         # Reminders + scheduling
│   ├── [weather|news|stocks|...].js
│   ├── models.js                # LLM provider abstraction
│   ├── utils.js                 # Shared utilities
│   ├── custom/                  # User-created custom agents
│   │   ├── registry.json        # Index of custom agents
│   │   └── [userAgentName].js   # Generated at runtime
│   └── e2e/                     # E2E testing utilities
│       └── apiProbe.js
│
├── services/                     # Business logic layer
│   ├── agentRegistryService.js  # Custom agent lifecycle
│   ├── pineconeMemory.js        # Semantic search
│   ├── obsidianSync.js          # Vault syncing
│   ├── conversationSummary.js   # History compression
│   └── policyEngine.js          # Access control
│
├── controllers/                  # HTTP request handlers
│   ├── chatController.js
│   ├── tasksController.js
│   └── remindersController.js
│
├── routes/                       # Express route definitions
│   ├── chat.js
│   ├── tasks.js
│   ├── reminders.js
│   ├── agentCenter.js           # Dashboard
│   └── wsJarvis.js              # WebSocket
│
├── tests/                        # Test suites
│   ├── unit/                     # Agent unit tests
│   ├── integration/              # Full flow tests
│   └── e2e/                      # HTTP-level tests
│
├── config/                       # Configuration files
├── docs/                         # Documentation
│   ├── endpoint_permissions.md
│   └── mobile_telemetry_data_policy.md
│
├── backlog.json                  # Feature backlog
├── features.json                 # Completed features tracker
├── agent-center.html             # Agent dashboard UI
└── jarvis_mobile/                # Flutter mobile app (separate project)
    ├── lib/
    ├── pubspec.yaml
    └── ...
```

## Known API Gotchas

- **No `GET /memories` endpoint** — a rate-limiter is registered at `/memories` but there is no route handler. Memory reads happen inside agents via Supabase directly; saving via UI should go through `POST /ask-jarvis` with a save-memory intent.
- **Tasks field name is `content`**, not `title`. The `tasks` table has `content`, `priority`, `done`, `created_at`. No `due_date` column in the controller.
- **Reminders field names**: `text` (not `title`), `scheduled_time` (ISO string, not `remind_at`), `fired` (boolean). `GET /reminders` only returns unfired reminders.
- **Response wrappers**: `/tasks` → `{ tasks: [] }`, `/reminders` → `{ reminders: [] }`, `/chat-history` → `{ history: [] }`. Don't assume a bare array.
- **Policy middleware on reminders**: all four CRUD routes require policy. The `free/member` allowlist in `config/policyRules.json` covers all `reminders.*` actions, so unauthenticated requests pass as `free/member`.

## Key Conventions & Patterns

### Agent Function Signature

```javascript
async function run*Agent(userMessage, supabase, useLocal, settings) {
  // userMessage: string (user's input in Hebrew or English)
  // supabase: Supabase client instance
  // useLocal: boolean (use local Ollama if true, cloud providers if false)
  // settings: { userName, assistantName, gender, personality, voiceMode, ... }
  
  return {
    answer: "string response",
    action: {
      type: "action_type",
      data: { /* ... */ }
    }  // optional
  };
}
```

### Error Handling

- Catch and log errors; avoid throwing (user gets generic fallback)
- LLM provider failover is transparent (handled in `models.js`)
- Database errors: fall back to in-memory cache if Supabase is down
- Missing env vars: log warning, continue with degraded service

### Hebrew Localization

- All prompts, keywords, and system messages in modern Hebrew
- Use gender-neutral or configurable pronouns based on user settings
- Date/time in Jerusalem timezone (`Asia/Jerusalem`)
- Currency references default to NIS (₪)

### Testing Best Practices

- Mock Supabase with jest.mock() in unit tests
- Use fixtures in `tests/fixtures/` for complex test data
- E2E tests should be idempotent (create fresh test records)
- Clear test data after each suite to avoid cross-test pollution

### Security Notes

- **Policy enforcement**: All sensitive actions gated by `requirePolicy()` middleware
- **Input validation**: Sanitize user input before LLM calls
- **Rate limiting**: Express rate-limit middleware on transcription, error scanning
- **Secrets**: Never commit `.env` file; use `.env.example` as template
- **Audit trail**: Policy engine logs all permission checks; review via `/audit` endpoint if added

## Troubleshooting

### Server won't start
- Check `.env` variables are set correctly
- Verify Supabase connectivity: `curl https://{SUPABASE_URL}/rest/v1/`
- Check for port 3000 conflicts: `lsof -i :3000`

### Tests failing
- Ensure `.env` has test Supabase credentials
- Clear Jest cache: `npx jest --clearCache`
- Check for async timeouts: increase `jest.setTimeout(10000)`

### LLM responses slow or failing
- Check provider failover: inspect console logs for `[models]` prefix
- Verify API keys are valid and have quota
- Try forcing local Ollama: `useLocal: true` in settings

### Memory/Pinecone search not working
- If `PINECONE_API_KEY` not set, falls back to keyword search (expected)
- Verify Pinecone project is active and index initialized
- Check vector dimensions match (default 1536 for embeddings)

## Flutter Mobile App

Located in `jarvis_mobile/`. Communicates with server via HTTP (and WebSocket for streaming):

**Main endpoints used:**
- `POST /ask-jarvis` — Send message + get answer
- `POST /stream-jarvis` — Stream response (SSE)
- `GET /chat-history` — Fetch past conversations
- `GET /check-reminders` — Poll for due reminders
- `GET /tasks`, `GET /notes`, `GET /reminders`, `GET /shopping` — Fetch lists
- `GET /contacts` — Fetch saved contacts
- `GET /calendar-events` — Calendar integration
- `GET /stats` — Usage analytics

**Settings object** sent with requests controls server behavior:
- `useLocalModel` — Prefer local Ollama if available
- `ttsEnabled` — Generate audio response
- `userName`, `assistantName` — Names for personalization
- `gender` — Pronoun preferences
- `personality` — Tone/style (professional, casual, funny, etc.)
- `voiceMode` — Shorter, markdown-free responses for TTS

## Further Reading

- **AUDIT.md** — Security review, architecture risks, compliance notes
- **docs/endpoint_permissions.md** — Detailed permission matrix
- **docs/mobile_telemetry_data_policy.md** — Data handling for mobile clients
