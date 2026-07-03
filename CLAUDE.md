# CLAUDE.md

Comprehensive guidance for Claude Code (claude.ai/code) working in this Jarvis server repository—an intelligent Hebrew-language personal assistant backend with a huge `server.js` (~290KB), ~30 agents, a dedicated data-access layer, MCP integration, and a large control-center/dashboard surface.

## Quick Start

### Installation & Setup

```bash
npm install                    # install dependencies
node server.js                 # start the server (port 3000 by default)
```

### Testing

```bash
npm test                       # run all unit + integration tests (Jest)
npm run test:coverage          # run with coverage report (thresholds: 58% stmts/46% branches/54% funcs/61% lines)
npm run e2e                    # run end-to-end self-tests against production
npm run e2e:local              # run e2e tests against localhost
npx jest tests/unit/router.test.js  # run a single test file
```

### Linting & Code Quality

```bash
npm run lint                   # syntax validation via scripts/lint-syntax.js
npm run review                 # runs review-coverage.js + review-security.js + review-logic.js in sequence
npm run review:coverage        # coverage-gap review only
npm run review:security        # security review only
npm run review:logic           # logic/business-rule review only
```

### MCP Server

```bash
npm run mcp:server             # node mcp-server.js — standalone MCP server exposing Jarvis agents as tools
```

`mcp-server.js` is a separate process (for Claude Desktop / MCP clients, not the HTTP server) that exposes `jarvis_tasks`, `jarvis_reminders`, `jarvis_memory`, `jarvis_notes`, `jarvis_shopping` tools. Each takes a single Hebrew/English `message` string and calls the corresponding `run*Agent` directly via `services/dataAccess` + `services/policyEngine`. Actor defaults to `admin`/`pro`, overridable via `MCP_ACTOR_ROLE`/`MCP_ACTOR_PLAN`. Separately, `server.js` can act as an MCP *client* (connecting out to external MCP servers configured in `config/mcpServers.json`) when `MCP_ENABLED=true` — see `services/mcp/`.

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
- `OBSIDIAN_VAULT_PATH` — Local Obsidian vault path for syncing memories (sync now runs once at startup only, see Cron Jobs)
- `OPENROUTER_API_KEY` — OpenRouter, part of the cloud LLM failover chain (`agents/providerConfig.js`)
- `MANUS_API_KEY`, `MANUS_BASE`, `MANUS_MODEL`, `MANUS_AUTH_HEADER`, `MANUS_TIMEOUT_MS`, `MANUS_POLL_MAX_MS` — Manus.im integration for heavy autonomous tasks (`manusAgent.js`)
- `PUSH_DRIVER` — Push notification transport (`fcm`, `ntfy`, or unset = no-op); see `services/pushService.js`
- `JARVIS_API_KEY` — API key checked against the `X-API-Key`/`X-Jarvis-Key` header for server auth. A valid `?key=` query param on a dashboard page load upgrades to an HttpOnly `jarvis_key` cookie, which authenticates the page's subsequent same-origin `fetch()` calls
- `AGENT_FACTORY_ENABLED` — `true` to allow the `factory` intent to *create* new custom agents (writes LLM-generated code to disk and hot-loads it). Off by default; listing/deleting existing custom agents works regardless
- `MCP_ENABLED` — `true` to have the server connect out to external MCP servers as a client (`services/mcp/`)
- `MCP_ACTOR_ROLE`, `MCP_ACTOR_PLAN` — Actor identity used by the standalone `mcp-server.js` process when calling agents

## Architecture Overview

### Request Flow

Every user message enters through `POST /ask-jarvis` (and `POST /stream-jarvis` for SSE streaming):

1. **Intent Classification** (`agents/router.js::classifyIntent`)
   - Fast path: Hebrew keyword regex matching against the `KEYWORDS` object
   - Fallback path: LLM classification (`classifyIntentWithLLM`) for messages that don't match keywords
   - Returns one of the 26 `VALID_INTENTS`: `task`, `reminder`, `memory`, `weather`, `news`, `shopping`, `notes`, `music`, `stocks`, `translate`, `sports`, `messaging`, `draft`, `security`, `code_error`, `e2e`, `manus`, `past_conv`, `calendar`, `prompt`, `settings`, `habit`, `insight`, `chat`, `project`, `factory` (`factory` — create/list/delete custom agents — and `project` are newer additions not covered by early docs)
   - `classifyIntentDetailed()` detects keyword collisions (e.g. `תזכיר` → reminder vs memory) and escalates ambiguous cases to the LLM, trusting it only when it picks one of the matched candidates
   - `detectComplexTask()` / `orchestratorAgent.js` pre-filters and handles **multi-intent** messages (e.g. "add a task and also remind me") by splitting into sub-tasks and running them via `Promise.allSettled`
   - `loadRouterOverrides()` reads `config/router-overrides.json` (currently empty; a manual-override escape hatch for misrouted phrases)

2. **Follow-up / Reference Resolution**
   - `chatAgent.detectFollowUp` — short messages that look like continuations override intent to `chat` regardless of routing
   - `services/contextResolver.js` — rewrites short anaphoric messages ("תזכיר לי על זה") into self-contained ones using recent history + summary, so downstream agents don't need conversational context

3. **Context Loading**
   - Chat history (last 20 messages, TTL-cached 30s) from Supabase; `services/contextWindow.js` can instead select a token-budget-based slice
   - Long-term memories: Pinecone semantic search if available, else keyword filtering (`services/memoryContext.js` centralizes this + the "pending memory confirmation" flow)
   - Rolling conversation summary via `services/conversationSummary.js` for context beyond the 20-message window
   - User profile (personality, gender, name, preferences) — partially auto-learned nightly by `services/profileLearner.js` / `services/styleLearner.js`

4. **Agent Dispatch**
   - `agents/dispatcher.js` centralizes the intent→agent mapping used by both `/ask-jarvis` and `/stream-jarvis` (a `REGISTRY` object keyed by intent, each entry declaring `mode: 'sync'|'background'`, an `invoke(ctx, agents)` adapter, and optional placeholder text) — this exists because most migrated agents no longer share one call signature (see Known Gotchas)
   - `code_error` and `e2e` agents run in background (`setImmediate`/background mode), return placeholder immediately
   - `security` runs sync in `/ask-jarvis` but background in `/stream-jarvis` (handled via `getEntryForMode`)
   - The orchestrator, custom agents, and plain chat fallback stay in `server.js` directly since they need extra logic (capability-gap detection via `devTaskAgent.js`, image handling, custom-agent hot-loading from `agents/custom/registry.json`)

5. **Response Assembly**
   - Answer text from agent
   - TTS audio (Google TTS, Hebrew `iw-IL` voice)
   - Optional `action` object (e.g., `{ type: 'reminder_set', data: {...} }`)
   - Chat history persisted to Supabase
   - Memory extraction via `autoExtractMemory` (fire-and-forget)
   - Decision trace + execution log + agent metrics recorded fire-and-forget (`decision_trace`, `execution_log`, `agent_metrics` tables via `services/agentMetrics.js`)

### LLM Stack (`agents/models.js` + `agents/providerConfig.js`)

`agents/providerConfig.js` is the pure-data source of truth for the failover chain (no network calls): `PROVIDERS` (ollama, groq, deepseek, openrouter, gemini), each with lazy `url()`/`model()`/`enabled()`/`keyEnv`/`timeout` resolvers. `CLOUD_DEFAULT_ORDER = ['groq', 'deepseek', 'gemini']`. `resolveChain({useLocal, cloudProvider})` builds the ordered chain — strict `['ollama']` if `useLocal`, else the cloud order with a preferred provider moved first. **OpenRouter is intentionally excluded from the automatic fallback order** — it's itself a broker fanning requests out to dozens of underlying providers, so silently routing through it on every Groq+DeepSeek failure trades real privacy exposure for a marginal reliability gain. It stays fully usable as an *explicit* choice: `resolveChain({cloudProvider: 'openrouter'})` still prepends it (mobile Settings → cloud provider dropdown).

`agents/models.js` consumes that config for all LLM calls:

- **`callGemma4()`** — Main inference endpoint; walks the resolved chain (Ollama local-first, then Groq → DeepSeek → Gemini by default, or a user-chosen provider first), OpenAI-compatible except Gemini
- **`callGemma4Stream()`** — Streaming version used by `/stream-jarvis` for real-time responses
- **`callGeminiWithSearch()`** — Google Search grounding (used by `sportsAgent`/`weatherAgent`/`newsAgent` fallback paths; note plain weather/news now prefer the keyless `weatherSource.js`/`newsSource.js` — see Services)
- **`callGeminiVision()`** — Multimodal image+text inference (when `imageBase64` in request)
- **`callWithTools()`** — Tool-calling variant used for MCP-backed flows
- `getCurrentProvider()` / `getLastKnownProvider()` — expose which provider actually served the last call, backing `GET /health/providers`

### Agents Directory Structure

**The single shared `run*Agent(userMessage, supabase, useLocal, settings)` signature is largely historical.** Most agents were migrated to take a `repos` object (the `services/dataAccess` seam) instead of a raw `supabase` client, and several drop `useLocal` and/or `settings` entirely, or take unrelated extra params. `agents/dispatcher.js`'s `REGISTRY.invoke()` adapters exist specifically to normalize these differing call shapes in one place — **check the actual function signature in the source file before wiring a new call site**, don't assume the documented pattern.

#### Core Agents

| File | Exported | Signature (actual) | Purpose |
|------|----------|---------------------|---------|
| `router.js` | `classifyIntent`, `classifyIntentDetailed`, `classifyIntentWithLLM`, `detectComplexTask`, `loadRouterOverrides`, `VALID_INTENTS` | n/a (not a `run*Agent`) | Intent classification |
| `dispatcher.js` | `REGISTRY`, `getEntry`, `getEntryForMode`, `dispatch` | n/a | Central intent→agent dispatch registry, normalizes inconsistent agent signatures |
| `orchestratorAgent.js` | `runOrchestratorAgent` | `(userMessage, supabase, useLocal, settings, chatHistory, longTermMemories)` | Splits multi-intent Hebrew messages into sub-tasks, runs them in parallel, joins answers |
| `chatAgent.js` | `runChatAgent`, `buildSystemPrompt`, `detectFollowUp`, `filterRelevantMemories(+Async)`, `rankMemories`, `analyzeUserStyle` | `(userMessage, imageBase64, chatHistory, longTermMemories, settings)` | Main conversational AI; builds rich Hebrew system prompt with memories, history, personality |
| `memoryAgent.js` | `runMemoryAgent`, `autoExtractMemory`, `checkDuplicate`, `findConflict`, `deleteMemory`, `updateMemory` | `(userMessage, repos, useLocal=true, settings={})` | Save/recall/delete personal facts; passive extraction after every turn. Passively-extracted `context` memories save as `status='pending'` and are **withheld from Pinecone/recall until approved** via `POST /memories/:id/approve`. Explicit saves and confirmed facts stay `approved`. |
| `taskAgent.js` | `runTaskAgent`, `classifyCategory`, `CATEGORY_META` | `(userMessage, repos, useLocal=true, settings={})` | Task creation, completion, listing, auto-categorization, recurring tasks |
| `reminderAgent.js` | `runReminderAgent`, `parseTime`, `parseRecurrence`, `toISO`, `nowJerusalem` | `(userMessage, repos)` | Set/recall/snooze/delete reminders with recurring support |
| `shoppingAgent.js` | `runShoppingAgent` | `(userMessage, repos, useLocal=true)` | Shopping list CRUD |
| `notesAgent.js` | `runNotesAgent` | `(userMessage, repos, useLocal=true)` | Quick notes/memo storage and search |
| `habitAgent.js` | `runHabitAgent`, `computeStreak` | `(userMessage, repos, useLocal=true, settings={})` | Track recurring habits + daily streaks (add/log/status/list/delete) |
| `projectAgent.js` | `runProjectAgent`, `buildProjectsBriefing` | `(userMessage, repos, useLocal=true, settings={})` | Projects, milestones, sprints, conflict detection |
| `calendarAgent.js` | `runCalendarAgent`, `buildAuthUrl`, `getAccessToken` | `(userMessage, repos, settings={})` | Google Calendar (OAuth) events — list/create |
| `promptAgent.js` | `runPromptAgent`, `detectIntent` | `(userMessage, repos, useLocal, settings={})` | Prompt engineering: create/refine/save prompts |
| `settingsAgent.js` | `runSettingsAgent` | `(userMessage, useLocal, settings)` | Parses NL settings-change requests (personality, TTS, name, etc.), returns `settings_update` action |
| `devTaskAgent.js` | *(no `run*Agent` export)* `detectCapabilityGap`, `handleConfirmation`, `generateClaudePrompt`, `saveDevTask` | n/a — helper module | Detects "capability gaps" (user asked for something Jarvis structurally can't do), on confirmation generates a ready-to-paste Claude Code prompt and files it as a dev task in `backlog.json` |
| `manusAgent.js` | `runManusAgent`, `runManusTask`, `isManusConfigured` | `(userMessage, settings={})` | Wraps the external Manus.im API (or MCP tool-calling path) for heavy autonomous/agentic tasks (browsing, coding, deep research) |

Recurring tasks: `taskAgent` reuses `parseRecurrence` from `reminderAgent`; on completing a recurring task it spawns the next occurrence with an advanced `due_date`. `insightAgent.runInsightAgent` handles both freeform insights and weekly/monthly period reports (`generatePeriodReport`).

#### Domain-Specific Agents

| File | Exported | Signature (actual) | Purpose |
|------|----------|---------------------|---------|
| `weatherAgent.js` | `runWeatherAgent` | `(userMessage, settings={})` | Current weather, forecasts — primarily via `services/weatherSource.js` (keyless Open-Meteo), Gemini Search as fallback |
| `newsAgent.js` | `runNewsAgent` | `(userMessage, settings={})` | Latest news headlines — primarily via `services/newsSource.js` (keyless Google News RSS), Gemini Search as fallback |
| `stocksAgent.js` | `runStocksAgent` | `(userMessage)` | Stock/crypto quotes, market data |
| `sportsAgent.js` | `runSportsAgent` | `(userMessage, settings={})` | Sports scores, team standings via Gemini Search |
| `messagingAgent.js` | `runMessagingAgent` | `(userMessage, repos, useLocal=true, settings={})` | Draft + send emails, WhatsApp templates, contacts |
| `translationAgent.js` | `runTranslationAgent` | `(userMessage, useLocal=true)` | Hebrew ↔ English/other languages |
| `musicAgent.js` | `runMusicAgent` | `(userMessage, repos, useLocal=false, settings={})` | Spotify playlist, music recommendations |

#### Quality & Extensibility Agents

| File | Exported | Signature (actual) | Purpose |
|------|----------|---------------------|---------|
| `agentFactoryAgent.js` | `runAgentFactoryAgent`, `sanitizeAgentName`, `isCodeSafe`, `readRegistry` | `(userMessage, repos, useLocal, settings)` | Create custom agents at runtime; writes to `agents/custom/` |
| `e2eAgent.js` | `runE2EAgent`, `buildClaudePrompt`, `computeScore`, `persistFindings` | matches `(userMessage, supabase, useLocal, settings)` via dispatcher | End-to-end test runner; scans codebase, persists findings to Supabase; learns from past runs via `agents/e2e/learning.js` |
| `securityAgent.js` | `runSecurityAgent` | `(userMessage, useLocal, sendEmailFn)` | Security audit, code scanning |
| `codeErrorAgent.js` | `runCodeErrorAgent` | `(userMessage='', _useLocal, sendEmailFn)` | Chat-triggered wrapper around `agents/e2e/codeErrorScanner.js` |
| `insightAgent.js` | `runInsightAgent`, `analyzePatterns`, `optimizeDayPlan`, `generatePeriodReport` | `(userMessage, repos, useLocal, settings={})` | Usage analytics, habit analysis, personalized tips, period reports |
| `draftAgent.js` | `runDraftAgent` | `(userMessage, chatHistory, longTermMemories, settings={})` | Help compose messages, emails, documents |
| `surveyAgent.js` | `SURVEY_QUESTIONS`, `buildSurveyJson`, `aggregateSurveys`, `generateSmartSurvey` | n/a — utility module, no `run*Agent` | User surveys and feedback collection |

#### Supporting Utilities

| File | Purpose |
|------|---------|
| `utils.js` | Shared agent utilities: `sanitizeLike`, `nowJerusalem`, `todayISODate`, `toISO`, `extractJSON` (reuse these instead of re-implementing date/JSON helpers per agent) |
| `models.js` | LLM provider abstraction layer (see LLM Stack) |
| `providerConfig.js` | Pure-data LLM provider chain config consumed by `models.js` |

`agents/custom/registry.json` is currently an empty array (`[]`) — populated at runtime by `agentFactoryAgent.js`, not checked in with content.

`agents/e2e/` (test-runner internals):

| File | Purpose |
|------|---------|
| `apiProbe.js` | Hits the running server with sample Hebrew queries + GETs, returns findings/samples for grading |
| `codeErrorScanner.js` | Regex-based bug/anti-pattern detection (Phase 1) + LLM deepening (Phase 2); produces a Claude/Codex-ready prompt |
| `flutterScan.js` | Scans `.dart` files via LLM for RTL violations, theme drift, a11y gaps, hard-coded English |
| `learning.js` | E2E self-improvement loop: classifies findings as new/regression/flaky/known, distills learned probes |
| `staticScan.js` | Static code scan extending securityAgent's prompt with performance/UX-backend categories |
| `uxScan.js` | Grades `apiProbe` samples on relevance/fluency/grounding (0-10) via LLM |

### Services Layer (`services/`)

| File | Purpose |
|------|---------|
| `agentRegistryService.js` | Custom + static agent catalog for the dashboard: enable/disable, risk level, per-agent customizations (atomic JSON file; core agents like `router`/`chatAgent` are protected from being disabled) |
| `agentMetrics.js` | Records per-agent latency + routing-mode metrics, batches flushes to `agent_metrics` |
| `contextResolver.js` | Rewrites anaphoric follow-up messages into self-contained ones via LLM, using recent history + summary |
| `contextWindow.js` | Selects the most recent chat-history slice that fits a token budget (Hebrew-aware estimate), instead of a fixed message count |
| `conversationSummary.js` | Rolling LLM-generated Hebrew summary of long conversations, 60s TTL cache |
| `dashboardLearner.js` | Derives most-used-first control-center tab ordering from `dashboard_tab_view` telemetry (deterministic, no LLM) |
| `documentParser.js` | Extracts/caps plain text from base64 PDFs (`pdf-parse`) for "ask about this document" |
| `feedbackStore.js` | Writer/reader for `smart_telemetry_events`; records 👍/👎/corrections, aggregates counts for learners |
| `memoryCleanup.js` | Prunes expired `session` (24h TTL) / `recent` (7d TTL) scoped memories + their Pinecone vectors + Obsidian entries |
| `memoryContext.js` | Loads memories for a request (Pinecone → keyword fallback) and manages the short-lived "pending memory" confirmation flow per chat |
| `memoryCategory.js` | LLM classification of a memory's content into the 5-bucket category taxonomy (עבודה/משפחה/בריאות/תחביב/כללי), used at write time and by the health scan |
| `memoryHealthCheck.js` | Batch health scan over existing memories — duplicates, conflicts, category mismatches, stale/thin content, Supabase↔Pinecone sync gaps. Nightly cron + manual trigger |
| `memoryHealthActions.js` | Applies a chosen action (delete/merge/move/archive) for a memory-health finding, reusing the same primitives as the manual `/memories` CRUD endpoints |
| `newsSource.js` | Keyless Hebrew headlines via Google News RSS (regex XML parse), 1h TTL cache — replaces the old Gemini-Search-only news widget |
| `obsidianSync.js` | Bidirectional sync between Supabase (notes, memories, tasks, reminders, chat, projects) and a local Obsidian vault, with file-watching, git pull/push. **Runs once at server startup only** — the recurring cron and manual-trigger endpoint were removed (see Cron Jobs / Known Gotchas) |
| `pineconeMemory.js` | Semantic vector search over memories via the Pinecone SDK; no-op when `PINECONE_API_KEY` is absent |
| `policyEngine.js` | Loads `config/policyRules.json`; `isAllowedByRolePlan()`, `isBlockedAction()` for RBAC |
| `priorityEngine.js` | Deterministic "Smart Day" engine (no DB/LLM): scores tasks/reminders by urgency+importance, Eisenhower quadrants, daily workload/overload, conflict detection |
| `proactiveEngine.js` | Surfaces at most one proactive nudge (overdue/stale high-priority task) inline in chat or via push; 6h cooldown per chat |
| `profileLearner.js` | Daily-cron learner deriving `preferred_hours`/`interests`/`recurring_tasks` into `user_profiles`, never overwriting user-set fields |
| `pushService.js` | Transport-swappable push notifications (FCM / ntfy / no-op via `PUSH_DRIVER`); device token registration/pruning |
| `routeTracker.js` | Short-TTL (10 min) map of the last routing decision per chat, so explicit feedback can be linked back to the intent that produced it |
| `styleLearner.js` | Derives response-style preferences (length, tone, language, satisfaction trend) from repeated feedback, injected into the chat prompt as `auto_learned.style_prefs` |
| `systemLog.js` | Persistent system event logger (console + `system_events` table); critical events push-notify, rate-limited per fingerprint |
| `weatherSource.js` | Keyless current weather + forecast via Open-Meteo, Hebrew summary + dressing advice; two-tier TTL cache (30d geocode, 1h forecast) |

#### `services/dataAccess/` — the agent data-access seam

Each file exports one `create*Repo(supabase)` factory; `index.js`'s `createRepos()` bundles them all plus a generic `table()` helper. Agents that were migrated to this pattern take a `repos` object (not a raw `supabase` client) as their second argument.

`chatRepo`, `contactRepo`, `cronRepo`, `decisionTraceRepo`, `deviceRepo`, `e2eRepo`, `executionLogRepo`, `habitRepo`, `memoryHealthRepo`, `memoryRepo`, `metricsRepo`, `noteRepo`, `playlistRepo`, `profileRepo`, `projectRepo`, `promptLibraryRepo`, `reminderRepo`, `shoppingRepo`, `sprintRepo`, `statsRepo`, `subtaskRepo`, `summaryRepo`, `surveyRepo`, `tableRepo` (generic shallow CRUD), `taskRepo`, `telemetryRepo`, `testCasesRepo`, `userPromptRepo` — each wraps one Supabase table (see table names in Memory & Storage below).

#### `services/mcp/` — MCP client integration (server acting as an MCP *client*)

| File | Purpose |
|------|---------|
| `mcpClientManager.js` | Singleton manager for external MCP server connections (`init`, `getToolCatalog`, `callTool`, `guardedCallTool`); isolates each server's failures so one bad connection can't block boot |
| `sdkLoader.js` | CJS→ESM bridge for the ESM-only `@modelcontextprotocol/sdk` via dynamic `import()` |
| `toolPolicy.js` | Maps MCP tool names to Jarvis policy action types/sensitivity, **fail-closed by default** — unmapped tools require explicit consent + pro/admin |

### Controllers & Routes

| File | Routes | Purpose |
|------|--------|---------|
| `controllers/chatController.js` | Chat endpoints | Chat history CRUD |
| `controllers/tasksController.js` | Task endpoints | Task CRUD + `/tasks/today`, subtasks, AI suggestions |
| `controllers/remindersController.js` | Reminder endpoints | Reminder CRUD + firing logic (`fire()`) |
| `controllers/notesController.js` | Note endpoints | Note CRUD |
| `controllers/shoppingController.js` | Shopping endpoints | Shopping-item CRUD |
| `controllers/contactsController.js` | Contact endpoints | Contact CRUD (policy-gated in the router) |
| `controllers/routerTrainerController.js` | Router-trainer endpoints | Training-events/misroutes read models + keyword-override CRUD; owns `config/router-overrides.json` I/O |
| `controllers/dashboardFeaturesController.js` | Feature-tracker endpoints | Three-bucket (done/building/planned) board CRUD + AI description generation; owns `features.json` I/O |
| `routes/chat.js` | `/chat-history` | Create chat router |
| `routes/tasks.js` | `/tasks`, `/tasks/:id`, `/tasks/today`, `/tasks/:id/subtasks`, `/tasks/:id/suggest` | Create tasks router |
| `routes/reminders.js` | `/reminders`, `/reminders/:id`, `/reminders/check` | Create reminders router |
| `routes/notes.js` | `/notes`, `/notes/:id` | Create notes router |
| `routes/shopping.js` | `/shopping`, `/shopping/:id` | Create shopping router |
| `routes/contacts.js` | `/contacts`, `/contacts/:id` | Create contacts router (requires `requirePolicy` injected from `server.js`) |
| `routes/routerTrainer.js` | `/router/training-events`, `/router/misroutes`, `/router/keywords` | Create router-trainer router |
| `routes/dashboardFeatures.js` | `/dashboard/features`, `/dashboard/features/suggest-description`, `/dashboard/features/generate-descriptions` | Create dashboard-features router |
| `routes/agentCenter.js` | Mounted at `/progress-map` | Serves the dashboard + all agent-center/progress-map sub-routes (`/agents`, `/metrics`, `/command`, `/brain`, etc.) |
| `routes/wsJarvis.js` | `ws://` | WebSocket support for real-time streaming |

### Memory & Storage

| Store | Used for |
|-------|----------|
| **Supabase** | `chat_history`, `chat_summaries`, `tasks`, `subtasks`, `reminders`, `notes`, `memories` (has `status`: `pending`\|`approved`, and `category`: עבודה/משפחה/בריאות/תחביב/כללי), `memory_health_findings`, `contacts`, `shopping_items`, `habits`, `habit_logs`, `projects`, `project_milestones`, `project_sprints`, `e2e_reports`, `user_surveys`, `execution_log`, `decision_trace`, `prompt_library`, `test_cases`, `user_prompts`, `agent_metrics`, `cron_runs`, `device_tokens`, `system_events`, `smart_telemetry_events`, `daily_briefings`, `user_profiles` |
| **Pinecone** | Semantic vector search over memories (optional; falls back to keyword matching if unavailable) |
| **In-process TTL cache** | Memories (5 min), chat history per `chatId` (30 s), conversation summary (60 s), routeTracker (10 min) |
| **Local filesystem** | `backlog.json`, `features.json`, `notes.json`, `agents/custom/registry.json`, `capability_gap_pending.json` |
| **Obsidian vault** | Mirror of memories + chat via `services/obsidianSync.js`, synced once at startup (not on a recurring schedule) |

Migrations live in **two places**: `supabase/migrations/` (the canonical, applied history — 28+ SQL files) and `docs/superpowers/migrations/` (a curated subset covering `decision_trace`, `memory_status`, `execution_log`, `prompt_library`, `test_cases` — check whether a given migration has also been mirrored into `supabase/migrations/` before assuming it's applied).

### Cron Jobs (scheduled via `node-cron`, wrapped by `scheduledJob()` which logs to `cron_runs`)

All times in Jerusalem timezone (`Asia/Jerusalem`) unless noted:

- **`* * * * *` (every minute)** — `fire_reminders`: fire due reminders (mark `fired=true`; reschedule recurring ones via `remindersController.fire()`)
- **`0 7 * * *` (07:00)** — `morning_briefing`: morning briefing notification (also has a boot-time catch-up run if 07:00 was missed, mitigating free-tier host sleep)
- **`0 9 * * *` (09:00)** — `inactive_agent_check`: flags agents inactive 7+ days
- **`0 13 * * *` (13:00)** — `proactive_push`: midday proactive push for overdue/stale high-priority tasks (once/day)
- **`0 21 * * *` (21:00)** — `evening_nudge`: evening nudge if open tasks exist
- **`0 3 * * *` (03:00)** — `context_memory_expiry`: expires `[context]`-tagged memories older than 7 days
- **`30 3 * * *` (03:30)** — `memory_cleanup_nightly`: full nightly memory cleanup (Pinecone + Obsidian pass)
- **`35 3 * * *` (03:35)** — `memory_health_scan`: batch memory-health scan (duplicates, conflicts, category mismatches, stale/thin/orphaned) — see `services/memoryHealthCheck.js`; Supabase↔Pinecone sync gaps are self-healed inline, everything else becomes a pending finding reviewed in the "ידע" tab
- **`45 3 * * *` (03:45)** — `profile_learning`: learns user profile/style preferences from behavior/feedback
- **`17 * * * *` (hourly at :17)** — `memory_cleanup_hourly`: prunes expired session/recent-scoped memories
- **`10 4 * * 0` (Sunday 04:10)** — `weekly_e2e`: weekly E2E self-test run (same path as `POST /e2e/trigger`; persists a report and feeds the e2e learning loop)
- **`17 2 * * *` (02:17, server-local tz)** — unnamed raw cron: daily backlog proposal rescoring in `backlog.json`

**Removed**: the previously-documented "every 5 minutes Obsidian sync" cron and its manual-trigger endpoints (`POST /sync/obsidian`, `POST /sync/obsidian/auto`) no longer exist. Obsidian sync is now startup-only (`obsidianSync.initSync()` + `fullSyncFromDb()` called once during boot).

### Policy & Consent System

Implemented via `server.js` policy engine and `services/policyEngine.js`:

- **Role-based access control (RBAC)** — `member`, `admin`, `free`, `pro` tiers with different permissions, defined in `config/policyRules.json` (`blocklist` + per-plan/role `allowlist`; `pro.member`/`pro.admin` get `*`)
- **Sensitive action gating** — Certain actions (contact management, messaging, security scans, filesystem-writing MCP tools) require explicit consent
- **Policy audit trail** — All policy decisions logged (500-entry circular buffer)
- **Consent ledger** — Per-user consent tracking by domain (contacts, messaging, etc.)
- **Middleware** — `requirePolicy(actionType, { sensitive?, irreversible? })` guards endpoints
- **MCP tool gating** — `services/mcp/toolPolicy.js` maps external MCP tool names to policy action types, fail-closed for anything unmapped

Example gated endpoints:
- `POST /send-email` — requires `messaging.send` permission (sensitive, irreversible)
- `POST /contacts` — requires `contacts.create` permission (sensitive)
- `DELETE /contacts/:id` — requires `contacts.delete` permission (sensitive, irreversible)
- `DELETE /memories/:id` — requires `memory.delete` permission (sensitive, irreversible)
- `DELETE /chat-history/:chatId` — requires `chat.delete` permission (sensitive, irreversible)
- `DELETE /user-profile` — requires `profile.delete` permission (sensitive, irreversible)

Irreversible endpoints expect `X-Confirm-Action: yes` (and sensitive ones `X-User-Consent: true`) — the mobile client and the dashboard `api()` helpers send these after their own confirm dialogs.

### API Endpoints Summary

Core endpoints (stable, unchanged):

| Method | Path | Handler | Notes |
|--------|------|---------|-------|
| `POST` | `/ask-jarvis` | Main agent dispatch | Core endpoint; returns `{ answer, audio?, action? }` |
| `POST` | `/stream-jarvis` | Streaming agent dispatch | SSE response with `data: {json}` chunks |
| `POST` | `/transcribe` | Groq Whisper | Audio → text transcription |
| `GET` | `/health` | Server status | Health check |
| `GET` | `/check-reminders` | Fire due reminders | Polled by mobile app (also `GET /reminders/check`) |
| `POST` | `/send-email` | Nodemailer | Requires policy |
| `GET` | `/chat-history` | Retrieve chat | Optional `chatId` query param |
| `DELETE` | `/chat-history/:chatId` | Delete chat session | Irreversible |
| `GET/POST` | `/tasks`, `/tasks/:id` | Task CRUD | Returns `{ tasks: [] }`; create body: `{ content, priority }` |
| `GET` | `/tasks/today` | Today's task view | Priority-engine-ranked |
| `POST` | `/tasks/:id/suggest` | AI subtask suggestions | — |
| `GET/POST/PUT/DELETE` | `/tasks/:id/subtasks`, `/tasks/:id/subtasks/:subId` | Subtask CRUD | — |
| `GET/POST` | `/reminders`, `/reminders/:id` | Reminder CRUD | Returns `{ reminders: [] }`; create body: `{ text, scheduled_time (ISO), recurrence? }` |
| `GET/POST/PUT/DELETE` | `/notes`, `/notes/:id` | Notes CRUD | — |
| `GET/POST/DELETE` | `/shopping`, `/shopping/:id` | Shopping CRUD | — |
| `GET/POST/PUT/DELETE` | `/contacts`, `/contacts/:id` | Contacts CRUD | Requires policy |
| `GET` | `/user-profile` | User settings | Reads `userName`, `gender`, `personality`, etc. |
| `POST` | `/user-profile` | Update settings | Persists to Supabase |
| `DELETE` | `/user-profile` | Hard delete profile | Irreversible |
| `GET` | `/survey-check` | Pending surveys | Returns survey queue |
| `POST` | `/survey-submit` | Submit survey responses | Saves to Supabase |
| `GET` | `/survey-history`, `/survey-insights`, `/survey-smart-check`, `/survey-impact` | Survey analytics | — |
| `GET` | `/surveys/export` | Export survey data | — |
| `POST` | `/surveys/analyze-sentiment` | Sentiment analysis on survey text | — |
| `GET` | `/stats` | Usage analytics | Message count, agent usage breakdown, etc. |
| `GET` | `/today-message` | Daily motivational | Cached 24h |
| `GET` | `/e2e-reports` | List test runs | All or filtered by status |
| `GET` | `/e2e-reports/:runId` | Single test report | Full details + remediation suggestions |
| `POST` | `/e2e-reports/:runId/prompt` | Re-analyze report | Re-run e2e analysis with new context |
| `POST` | `/e2e-reports/:runId/mark-done` | Mark issue resolved | Clears report |
| `DELETE` | `/e2e-reports/:runId` | Delete a report | — |
| `GET/PUT` | `/e2e-schedule` | E2E schedule config | — |
| `POST` | `/scan/errors`, `/scan/errors/run` | Scan codebase for errors | Rate-limited (5/min) |
| `POST` | `/e2e/trigger` | Manually trigger an E2E run | — |
| `GET` | `/dashboard/error-report/export` | Export error scan report | — |
| `POST` | `/dashboard/smart-telemetry` | Record a telemetry event | Body: `{event_type, payload?, user_id?}` |
| `GET` | `/dashboard/smart-telemetry` | Fetch telemetry events | Optional `?user_id=` filter |
| `DELETE` | `/dashboard/smart-telemetry/history` | Delete all telemetry events for a user | Body/query: `{userId}` |
| `POST` | `/dashboard/smart-telemetry/reset` | Reset telemetry (from settings screen) | Body: `{"scope":"user"}`; deletes all events |
| `POST` | `/feedback` | Explicit 👍/👎/correction signal | Feeds `feedbackStore.js` / `styleLearner.js` |
| `GET/POST/PUT/DELETE` | `/memories`, `/memories/:id` | Memory CRUD | Pinecone search + keyword fallback. `DELETE /memories/:id` = "forget" |
| `GET` | `/memories/pending` | Pending memories awaiting approval | Returns `{ memories: [] }` |
| `GET` | `/memories/health/findings` | Pending memory-health findings | Optional `?type=`, `?status=` (default `pending`) |
| `POST` | `/memories/health/run` | Trigger a memory health scan now | Rate-limited (5/min); same scan as the nightly `memory_health_scan` cron. Responds immediately (`{ok:true, started:true}`) and runs in the background (`setImmediate`) — scanning every memory can take minutes on a real dataset, so the response never waits for it |
| `POST` | `/memories/health/findings/:id/resolve` | Apply a finding's suggested (or edited) action | Body `{action, payload?}`; requires policy + `X-Confirm-Action`/`X-User-Consent` |
| `POST` | `/memories/health/findings/:id/dismiss` | Dismiss a finding without acting | Resurfaces only if the memory's content later changes |
| `POST` | `/memories/:id/approve` | Approve a pending memory | Sets `status='approved'`, upserts to Pinecone |
| `POST` | `/memories/confirm` | Confirm a pending extracted memory (chat-flow variant) | — |
| `POST` | `/memories/rebuild-from-chat` | Rebuild memories from chat history | — |
| `POST` | `/memories/recover-from-pinecone` | Recover memories lost from Supabase, from Pinecone | — |
| `POST` | `/parse-document` | Parse an uploaded document (PDF) | `services/documentParser.js` |
| `GET` | `/decision-trace` | Recent routing decisions | Returns `{ trace: [] }` — `candidates` is a JSON string, must be parsed. **No numeric confidence** — honesty over a fake % |
| `GET` | `/execution-log` | Recent `/ask-jarvis` executions | Returns `{ log: [] }` — `cmd`, `agent`, `model`, `duration_ms`, `status` |
| `GET` | `/health/providers` | Per-provider availability | Probes each LLM provider live (slow, ~20s) |
| `GET` | `/stats/weekly-score` | Weekly feedback score | `{ score, ups, downs, total }`; `?weeks=N` → `{ history: [] }` |
| `GET` | `/day-plan` | Priority-engine day plan | `services/priorityEngine.js` |
| `GET` | `/morning-briefing`, `/dashboard-context`, `/smart-suggestions` | Proactive/briefing data | — |
| `POST` | `/push/register-token` | Register a device push token | — |
| `POST` | `/push/test` | Send a test push | — |
| `GET/POST/PUT/DELETE` | `/prompt-library`, `/prompt-library/:id` | Prompt library CRUD | — |
| `GET/POST` | `/test-cases` | Recorded regression test cases | — |
| `POST` | `/test-cases/start-recording`, `/test-cases/stop-recording`, `/test-cases/:id/run` | Test case recording/replay | — |
| `GET` | `/changelog/generate` | Auto-generate a changelog | — |
| `GET` | `/router/training-events` | Router misroute/training signal history | — |
| `GET` | `/router/misroutes` | Detected repeated-misroute override proposals from 👎 feedback | Read-only; see Router Feedback Loop below |
| `GET/POST/DELETE` | `/router/keywords` | Inspect/edit router keyword patterns | — |
| `GET` | `/dashboard/analytics`, `/dashboard/conversation-insights` | Dashboard analytics views | — |
| `POST` | `/dashboard/analytics/insights` | Generate analytics insights | — |
| `POST` | `/dashboard/smart-proposals/generate`, `/dashboard/smart-proposals/clarify`, `/dashboard/smart-proposals/refine-prompt` | Feature-proposal generation flow | — |
| `GET/POST/DELETE` | `/dashboard/features` | Feature tracker CRUD | — |
| `POST` | `/dashboard/features/suggest-description`, `/dashboard/features/generate-descriptions` | LLM-assisted feature descriptions | — |
| `GET` | `/dashboard/backlog`, `/dashboard/backlog/config`, `/dashboard/backlog/schema` | Backlog data + config | — |
| `POST` | `/dashboard/backlog/generate`, `/dashboard/backlog/analyze` | Backlog generation/analysis | — |
| `POST` | `/dashboard/backlog/proposals/:id/draft-plan` | Draft an implementation plan for a proposal | — |
| `DELETE` | `/dashboard/backlog/proposals/:id`, `/dashboard/backlog/:id` | Delete backlog items/proposals | — |
| `GET/POST` | `/proposals` | Proposal queue | — |
| `POST` | `/api/proposals/:id/action` | Act on a proposal (approve/reject/etc.) | — |
| `POST` | `/dashboard/generate-prompt` | Generate a Claude-Code-ready prompt for a task | — |
| `POST` | `/dashboard/graph/action` | Constellation/knowledge graph node action | — |
| `GET/POST` | `/workshop/:id/chat` | Dev workshop chat flow | — |
| `POST` | `/save-spec` | Save a design spec from the workshop | — |
| `GET/POST/PUT/DELETE` | `/projects`, `/projects/:id` | Project CRUD | — |
| `GET` | `/projects/briefing` | Cross-project briefing | `buildProjectsBriefing()` |
| `GET/POST/PUT/DELETE` | `/projects/:id/milestones`, `/projects/:id/milestones/:mId` | Milestone CRUD | — |
| `GET/POST/PUT/DELETE` | `/projects/:id/sprints`, `/projects/:id/sprints/:sId` | Sprint CRUD | — |
| `POST` | `/projects/:id/sprints/:sId/start`, `/projects/:id/sprints/:sId/complete` | Sprint lifecycle | — |
| `POST` | `/projects/recommend-methodology`, `/projects/:id/ai-insights` | LLM project assistance | — |
| `GET` | `/auth/google/start`, `/auth/google/callback` | Google Calendar OAuth flow | — |
| `GET` | `/calendar-events`, `/upcoming-items` | Calendar + combined upcoming-items view | — |
| `GET` | `/agent-center` | Dashboard HTML | Redirects to `/progress-map` (also `/control-center`, `/memory-explorer`, `/brain` redirect aliases) |
| `POST` | `/progress-map/command` | NL control bar | Hebrew text → action. Deterministic-first, LLM fallback for free-form metrics questions |
| `GET` | `/progress-map/agents`, `/progress-map/metrics` | Agent catalog + dashboard metrics | — |
| `POST` | `/progress-map/agents/:id/toggle`, `/progress-map/agents/:id/risk` | Enable/disable + risk-level per agent | — |
| `POST` | `/progress-map/agents/:id/chat` | Chat with/about a specific agent (dashboard) | — |
| `GET` | `/progress-map/agents/:id/customizations` | Per-agent dashboard customizations | — |
| `POST` | `/progress-map/analyze`, `/progress-map/build-prompt` | Analysis + prompt-building helpers | — |
| `POST` | `/progress-map/metrics/query` | Ad-hoc metrics query (NL → metric) | — |
| `GET` | `/control-center/layout` | Learned tab order | `dashboardLearner` derives most-used-first ordering |
| `GET` | `/control-center/events` | Live alerts + per-tab badges | Cheap (no LLM); includes `memory_pending` alerts |
| `ws` | `/ws-jarvis` | WebSocket stream | Real-time bidirectional agent chat |

Static/misc pages: `GET /chart.js`, `GET /design-preview`, `GET /projects-dashboard`, `GET /notes.json`.

**Removed** (documented previously, no longer exist): `POST /sync/obsidian`, `POST /sync/obsidian/auto` — Obsidian sync is startup-only now (see Cron Jobs).

#### Mobile Control Center (Flutter, 4-tab redesign)

The mobile control center (`jarvis_mobile/lib/screens/control_center/`) is a 4-tab shell — **סקירה** (overview), **מוח** (brain), **סוכנים** (agents), **שיפור** (improve) — distinct from the 6-tab web dashboard in `progress-map.html`. Role-gated: non-admins see סקירה + שיפור; admins see all four. Each tab is wired to real endpoints (no mock data, no dead buttons):
- **סקירה** → `/health`, `/control-center/events`, `/execution-log`
- **מוח** → `/decision-trace`, `/health/providers`, `/memories/pending` (+ approve / `DELETE /memories/:id`)
- **סוכנים** → `/progress-map/agents` (+ toggle / risk), `/progress-map/metrics`
- **שיפור** → `/e2e-reports`, `/stats/weekly-score`, `/dashboard/backlog`, `/proposals`, `/survey-check` + `/survey-submit`, `/workshop/:id/chat` + `/save-spec`

## Development Workflows

### Adding a New Agent

1. Create `agents/myAgent.js`. Pick a signature that matches how you'll actually call it — new agents generally take `repos` (from `services/dataAccess`) rather than a raw `supabase` client:
   ```javascript
   function runMyAgent(userMessage, repos, useLocal, settings) {
     return { answer: "...", action?: {...} };
   }
   module.exports = { runMyAgent };
   ```

2. Register in `agents/router.js`:
   - Add keyword pattern to `KEYWORDS` object
   - Add to `VALID_INTENTS` array
   - Ensure keyword catches all natural Hebrew queries for your intent; watch for cross-intent collisions

3. Register a dispatch entry in `agents/dispatcher.js`'s `REGISTRY`:
   - Add an entry with `mode: 'sync'` (or `'background'` if it's slow/best-effort) and an `invoke(ctx, agents)` adapter that calls your agent with its actual argument order
   - This is what both `/ask-jarvis` and `/stream-jarvis` call — you don't need to duplicate wiring in each route

4. Test:
   - Unit test: `tests/unit/myAgent.test.js`
   - Integration test: `tests/integration/` if it touches Supabase
   - Verify keyword regex catches Hebrew variants

### Creating Custom Agents at Runtime

**Creation is frozen by default** — it writes LLM-generated code to disk and hot-loads it, so it requires `AGENT_FACTORY_ENABLED=true` in the environment. Listing and deleting existing custom agents work without the flag.

Users can request the `factory` intent to dynamically create custom agents:

```
צור אייג'נט לשם "תזכיר קניות" שמנהל רשימת קניות בדרך חלקלקה
Create agent named "shopping reminder" that manages a shopping list smoothly
```

The `agentFactoryAgent.js` will:
1. Generate JS code for the new agent
2. Write to `agents/custom/{agentName}.js`
3. Register in `agents/custom/registry.json`
4. Hot-load via the custom-agent loading path in `server.js`

Lifetime: custom agents persist until explicitly deleted.

### Modifying Intent Routing

When changing intent classification logic:
- Update `KEYWORDS` regex patterns in `router.js` (affects fast path)
- Update the LLM classification prompt in `router.js` (affects LLM fallback)
- Consider `config/router-overrides.json` for a targeted fix to one misrouted phrase instead of a broad regex change
- Test with `npx jest tests/unit/router.test.js`
- Check for cross-intent keyword collisions (e.g., `תזכיר` = reminder *and* memory)
- `GET /router/training-events` and `GET/POST/DELETE /router/keywords` expose router introspection/editing at runtime

#### Router Feedback Loop (👎 → override proposal)

`POST /feedback` links each 👎 to the intent that produced the reply via `routeTracker.getLastRoute(chatId)` (10-min TTL), storing it as `metadata.routedIntent` on a `feedback_down` row in `smart_telemetry_events`. `GET /router/misroutes` (`services/feedbackStore.js::computeMisroutePatterns`) groups those rows by `(routedIntent, normalized message)` and returns only patterns that recurred **2+ times** — a single bad reply is noise, the same message getting the same wrong intent repeatedly is a proposal. Each entry carries a `suggestedKeyword` (the normalized message text) a human can review and apply via the existing `POST /router/keywords` — this is detection/proposal only, nothing is auto-applied. Surfaced in the mobile control center's dev-workshop router-trainer card (third "הצעות" tab) and consumable directly via the API for any other admin surface.

### Adding Supabase Tables

1. Design schema (DDL)
2. Add the migration file to `supabase/migrations/` (this is the canonical/applied history)
3. Apply via Supabase web UI or SDK
4. Add a matching `services/dataAccess/<name>Repo.js` if agents need to read/write it, and wire it into `dataAccess/index.js`
5. Add tests that mock or provision the table
6. Update `.env` if new API keys needed

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

Test structure (Jest matches `tests/**/*.test.js`; coverage collected from `server.js`, `agents/**`, `services/**`, `controllers/**`, `routes/**`):
- `tests/unit/` — ~79 test files: agent unit tests, isolated mocks, fast (~50ms each); `tests/unit/dataAccess/` (~19 files) covers the repo layer specifically
- `tests/integration/` — ~13 test files: full flows touching Supabase, slower (~1-5s each)
- `tests/e2e/` — `runE2E.js`, the e2e runner script itself (invoked via `npm run e2e`/`e2e:local`, not a Jest `.test.js`)
- `tests/helpers/` — `fakeRepos.js`, `supabaseMock.js` shared test doubles
- `tests/fixtures/` — `memories.json`, `profile.json`, `reminders.json`, `tasks.json` sample data

## File Organization

```
jarvis-server-nadav/
├── server.js                    # Main Express app, request routing, cron setup (~290KB)
├── mcp-server.js                 # Standalone MCP server exposing Jarvis agents as tools (npm run mcp:server)
├── package.json                 # Dependencies, Jest config, npm scripts
├── .env.example                 # Example environment variables
├── README.md                     # Project overview
├── CLAUDE.md                     # This file
├── AUDIT.md                      # Security + architecture audit
│
├── agents/                       # Core agent implementations
│   ├── router.js                # Intent classification
│   ├── dispatcher.js            # Central intent→agent dispatch registry
│   ├── orchestratorAgent.js     # Multi-intent message splitting
│   ├── chatAgent.js             # Main conversational AI
│   ├── memoryAgent.js           # Memory CRUD + extraction
│   ├── taskAgent.js             # Task management
│   ├── reminderAgent.js         # Reminders + scheduling
│   ├── devTaskAgent.js          # Capability-gap detection → dev task filing
│   ├── settingsAgent.js         # NL settings-change parsing
│   ├── manusAgent.js            # Manus.im heavy autonomous tasks
│   ├── providerConfig.js        # LLM provider chain config (pure data)
│   ├── [weather|news|stocks|...].js
│   ├── models.js                # LLM provider abstraction
│   ├── utils.js                 # Shared utilities
│   ├── custom/                  # User-created custom agents
│   │   ├── registry.json        # Index of custom agents (empty until first is created)
│   │   └── [userAgentName].js   # Generated at runtime
│   └── e2e/                     # E2E testing utilities
│       ├── apiProbe.js
│       ├── codeErrorScanner.js
│       ├── flutterScan.js
│       ├── learning.js
│       ├── staticScan.js
│       └── uxScan.js
│
├── services/                     # Business logic layer
│   ├── agentRegistryService.js  # Custom agent lifecycle
│   ├── agentMetrics.js          # Per-agent latency/mode metrics
│   ├── pineconeMemory.js        # Semantic search
│   ├── obsidianSync.js          # Vault syncing (startup-only)
│   ├── conversationSummary.js   # History compression
│   ├── policyEngine.js          # Access control
│   ├── priorityEngine.js        # Smart Day scoring/quadrants/conflicts
│   ├── proactiveEngine.js       # Proactive nudges
│   ├── profileLearner.js        # Nightly profile learning
│   ├── styleLearner.js          # Response-style learning from feedback
│   ├── pushService.js           # FCM/ntfy push notifications
│   ├── weatherSource.js         # Keyless weather (Open-Meteo)
│   ├── newsSource.js            # Keyless news (Google News RSS)
│   ├── documentParser.js        # PDF text extraction
│   ├── dataAccess/              # Per-table repo factories (~27 files)
│   │   └── index.js             # createRepos() bundler
│   └── mcp/                     # MCP client integration
│       ├── mcpClientManager.js
│       ├── sdkLoader.js
│       └── toolPolicy.js
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
│   ├── agentCenter.js           # Dashboard, mounted at /progress-map
│   └── wsJarvis.js              # WebSocket
│
├── tests/                        # Test suites
│   ├── unit/                     # Agent unit tests (~79 files) + dataAccess/ (~19)
│   ├── integration/               # Full flow tests (~13 files)
│   ├── e2e/                       # runE2E.js runner script
│   ├── helpers/                   # fakeRepos.js, supabaseMock.js
│   └── fixtures/                  # Sample JSON data
│
├── config/                       # Configuration files
│   ├── policyRules.json         # RBAC blocklist/allowlist
│   ├── mcpServers.json          # External MCP server registry/config
│   ├── router-overrides.json    # Manual intent-routing overrides
│   └── claude_desktop_config.example.json
├── docs/                         # Documentation
│   ├── endpoint_permissions.md
│   ├── mobile_telemetry_data_policy.md
│   └── superpowers/
│       ├── migrations/          # Curated SQL migration subset
│       ├── plans/               # Dated planning docs
│       └── specs/               # Dated design specs
│
├── supabase/
│   └── migrations/               # Canonical applied SQL migration history (28+ files)
│
├── backlog.json                  # Feature backlog + proposals
├── features.json                 # Completed features tracker
├── agent-center.html             # Agent dashboard UI
└── jarvis_mobile/                # Flutter mobile app (separate project)
    ├── lib/
    │   ├── main.dart, main_shell.dart, app_settings.dart, ...
    │   ├── screens/               # incl. control_center/ (4-tab mobile dashboard)
    │   ├── services/
    │   ├── theme/
    │   ├── widgets/
    │   └── platform/
    ├── pubspec.yaml
    └── ...
```

## Known API Gotchas

- **Agent function signatures are inconsistent** — the "standard" `run*Agent(userMessage, supabase, useLocal, settings)` shape is aspirational, not actual. Most agents take `repos` instead of `supabase`, and several drop `useLocal`/`settings` (`stocksAgent`, `reminderAgent`, `translationAgent`, `shoppingAgent`, `notesAgent`), or take entirely different params (`chatAgent`, `orchestratorAgent`, `manusAgent`, `settingsAgent`, `securityAgent`, `codeErrorAgent`). `agents/dispatcher.js`'s `REGISTRY` exists to normalize these. **Always check the actual export before wiring a new call site.**
- **`/memories` CRUD exists** — `GET/POST/PUT/DELETE /memories` are implemented in `server.js` (Pinecone search with keyword fallback).
- **Memory approval gate** — the `memories` table has a `status` column (`pending`\|`approved`, default `approved`). Only **passively auto-extracted `context` memories** become `pending`; they are NOT upserted to Pinecone (so excluded from recall) until approved via `POST /memories/:id/approve`. `allContents()` (keyword-recall fallback) also excludes `pending`. Migration: `docs/superpowers/migrations/memory_status.sql`.
- **Decision trace** — every `/ask-jarvis` routing decision is recorded fire-and-forget to `decision_trace` (`input`, `intent`, `candidates`, `ambiguous`, `route_mode`, `agent`, `model`, `duration_ms`). `candidates` is stored as a JSON string in a `jsonb` column, so readers must `JSON.parse`/`jsonDecode` it. The router exposes no numeric confidence — none is fabricated. Migration: `docs/superpowers/migrations/decision_trace.sql`.
- **Obsidian sync is no longer scheduled or manually triggerable** — `POST /sync/obsidian` and `POST /sync/obsidian/auto` were removed; sync now runs once at server startup only (`obsidianSync.initSync()` + `fullSyncFromDb()`).
- **Two migration directories** — `supabase/migrations/` is the canonical applied history; `docs/superpowers/migrations/` holds a curated subset (decision_trace, memory_status, execution_log, prompt_library, test_cases). Don't assume a file in one implies it's mirrored in the other.
- **Tasks field name is `content`**, not `title`. The `tasks` table has `content`, `priority`, `done`, `created_at`, `due_date`, `category`, `recurrence` (`daily|weekly|monthly|NULL`), and `tags`.
- **Reminders field names**: `text` (not `title`), `scheduled_time` (ISO string, not `remind_at`), `fired` (boolean). `GET /reminders` only returns unfired reminders.
- **Response wrappers**: `/tasks` → `{ tasks: [] }`, `/reminders` → `{ reminders: [] }`, `/chat-history` → `{ history: [] }`. Don't assume a bare array.
- **Policy middleware on reminders**: all CRUD routes require policy. The `free/member` allowlist in `config/policyRules.json` covers all `reminders.*` actions, so unauthenticated requests pass as `free/member`.
- **`test.js` at repo root is not part of the Jest suite** — it's a tiny ad-hoc manual smoke-test script (`X-API-Key` header via `APP_SECRET`), separate from `mcp-server.js` and from anything under `tests/`.

## Key Conventions & Patterns

### Agent Function Signature

There is no single enforced signature anymore (see Known Gotchas). The historical/aspirational shape, still followed by some agents:

```javascript
async function run*Agent(userMessage, supabase, useLocal, settings) {
  // userMessage: string (user's input in Hebrew or English)
  // supabase / repos: Supabase client instance, or a services/dataAccess repos bundle
  // useLocal: boolean (use local Ollama if true, cloud providers if false) — often omitted
  // settings: { userName, assistantName, gender, personality, voiceMode, ... } — often omitted

  return {
    answer: "string response",
    action: {
      type: "action_type",
      data: { /* ... */ }
    }  // optional
  };
}
```

`agents/dispatcher.js`'s per-intent `invoke(ctx, agents)` adapters are the actual contract callers should rely on.

### Error Handling

- Catch and log errors; avoid throwing (user gets generic fallback)
- LLM provider failover is transparent (handled in `models.js`/`providerConfig.js`)
- Database errors: fall back to in-memory cache if Supabase is down
- Missing env vars: log warning, continue with degraded service

### Hebrew Localization

- All prompts, keywords, and system messages in modern Hebrew
- Use gender-neutral or configurable pronouns based on user settings
- Date/time in Jerusalem timezone (`Asia/Jerusalem`)
- Currency references default to NIS (₪)

### Testing Best Practices

- Mock Supabase (or the relevant `dataAccess` repo) with `jest.mock()` / `tests/helpers/fakeRepos.js` in unit tests
- Use fixtures in `tests/fixtures/` for complex test data
- E2E tests should be idempotent (create fresh test records)
- Clear test data after each suite to avoid cross-test pollution

### Security Notes

- **Policy enforcement**: All sensitive actions gated by `requirePolicy()` middleware; MCP tools gated by `services/mcp/toolPolicy.js` (fail-closed)
- **Input validation**: Sanitize user input before LLM calls
- **Rate limiting**: Express rate-limit middleware on transcription, error scanning
- **Secrets**: Never commit `.env` file; use `.env.example` as template
- **Audit trail**: Policy engine logs all permission checks

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

### MCP server issues
- `npm run mcp:server` runs the standalone process; check `MCP_ACTOR_ROLE`/`MCP_ACTOR_PLAN` if tool calls get policy-denied
- If `server.js` isn't picking up external MCP tools, verify `MCP_ENABLED=true` and check `config/mcpServers.json`

## Flutter Mobile App

Located in `jarvis_mobile/`. Communicates with server via HTTP (and WebSocket for streaming):

**Main endpoints used:**
- `POST /ask-jarvis` — Send message + get answer
- `POST /stream-jarvis` — Stream response (SSE)
- `GET /chat-history` — Fetch past conversations
- `GET /check-reminders` — Poll for due reminders
- `GET /tasks`, `GET /notes`, `GET /reminders`, `GET /shopping` — Fetch lists
- `GET /contacts` — Fetch saved contacts
- `GET /calendar-events`, `GET /upcoming-items` — Calendar integration
- `GET /stats` — Usage analytics
- Control center tabs — see Mobile Control Center section above

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
- **docs/superpowers/plans/** and **docs/superpowers/specs/** — dated planning/design docs for recent feature work (control center redesign, brain graph, workshop flow, router trainer, etc.)
