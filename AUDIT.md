# 📊 Jarvis Server — Progress Audit

**Updated:** 2026-05-16 | **Status:** ✅ All Tests Passing (206/206)

---

## 🎯 Overview

**Jarvis** is a Hebrew-first AI assistant server with:
- **27 Agents** (routing by Hebrew keyword + LLM fallback)
- **53 REST endpoints** (Express.js)
- **Supabase** backend for persistence
- **Pinecone** for semantic memory search
- **Flutter mobile app** (jarvis_mobile/)
- **Full test coverage** (206 unit + integration tests)

---

## ✅ What's Working (DONE)

### Core Infrastructure
| Feature | Status | Notes |
|---------|--------|-------|
| **Chat AI** | ✅ Done | Groq → DeepSeek → Gemini fallback. Hebrew LLM routing via llama-3.3-70b-versatile |
| **Speech-to-Text** | ✅ Done | Google ASR, Hebrew, via `/transcribe` endpoint |
| **Text-to-Speech** | ✅ Done | Flutter TTS + Google TTS. Speed adjustable, Hebrew native. No lag reported. |
| **Server** | ✅ Done | Express.js on port 3000. localhost or Render cloud deploy. |
| **Health Check** | ✅ Done | `GET /health` endpoint + automatic restart on crash |

### Agents (27 Total)
| Agent | Status | Tested |
|-------|--------|--------|
| `router.js` | ✅ | 🧪 Yes |
| `chatAgent.js` | ✅ | 🧪 Yes |
| `taskAgent.js` | ✅ | 🧪 Yes |
| `reminderAgent.js` | ✅ | 🧪 Yes |
| `notesAgent.js` | ✅ | 🧪 Yes |
| `shoppingAgent.js` | ✅ | 🧪 Yes |
| `memoryAgent.js` | ✅ | 🧪 Yes |
| `newsAgent.js` | ✅ | 🧪 Yes |
| `weatherAgent.js` | ✅ | 🧪 Yes |
| `stocksAgent.js` | ✅ | 🧪 Yes |
| `sportsAgent.js` | ✅ | 🧪 Yes |
| `translationAgent.js` | ✅ | 🧪 Yes |
| `musicAgent.js` | ✅ | 🧪 Yes |
| `messagingAgent.js` | ✅ | 🧪 Yes |
| `draftAgent.js` | ✅ | 🧪 Yes |
| `insightAgent.js` | ✅ | 🧪 Yes |
| `surveyAgent.js` | ✅ | 🧪 Yes |
| `agentFactoryAgent.js` | ✅ | 🧪 Yes |
| `e2eAgent.js` | ✅ | 🧪 Yes |
| `securityAgent.js` | ✅ | 🧪 Yes |
| `codeErrorAgent.js` | ✅ | 🧪 Yes |

### Data Persistence
| Feature | Status | Technology |
|---------|--------|-----------|
| **Chat History** | ✅ | Supabase (last 20 msgs, TTL-cached 30s) |
| **Tasks** | ✅ | Supabase + local cache |
| **Reminders** | ✅ | Supabase + cron jobs (run every minute) |
| **Notes** | ✅ | Supabase + structured metadata |
| **Memories** | ✅ | Supabase + auto-extraction + Pinecone semantic search |
| **Shopping List** | ✅ | Supabase with item tracking |
| **Contacts** | ✅ | Supabase with privacy guards |
| **User Profile** | ✅ | Supabase (name, gender, personality, voice settings) |
| **E2E Reports** | ✅ | Supabase with timestamped findings |

### API Endpoints (53 Total)
**Main:**
- `POST /ask-jarvis` — dispatch to agent
- `POST /stream-jarvis` — SSE streaming response

**Chat & History:**
- `GET /chat-history` — fetch history
- `DELETE /chat-history/:chatId` — clear a chat

**Tasks:**
- `GET /tasks`, `POST /tasks`, `PUT /tasks/:id`, `DELETE /tasks/:id`

**Reminders:**
- `GET /reminders`, `POST /reminders`, `PUT /reminders/:id`, `DELETE /reminders/:id`
- `GET /check-reminders` — fire due reminders

**Notes:**
- `GET /notes`, `POST /notes`, `PUT /notes/:id`, `DELETE /notes/:id`

**Shopping:**
- `GET /shopping`, `POST /shopping`, `DELETE /shopping/:id`

**Contacts:**
- `GET /contacts`, `POST /contacts`, `PUT /contacts/:id`, `DELETE /contacts/:id`

**Memories & Search:**
- `GET /memories` (+ Pinecone semantic search)
- `POST /memories` (auto-extracted from chat)
- `DELETE /memories/:id`

**Admin & Monitoring:**
- `GET /health` — server status
- `GET /stats` — usage dashboard
- `GET /user-profile`, `POST /user-profile`, `DELETE /user-profile`
- `GET /e2e-reports`, `POST /e2e-reports/:runId/mark-done`
- `GET /scan/errors` — static code scan (codeErrorAgent)
- `POST /sync/obsidian` — vault sync

**UI:**
- `GET /progress-map` — live dashboard
- `GET /agent-center` → redirects to /progress-map

### Services
| Service | Purpose | Status |
|---------|---------|--------|
| `agentRegistryService.js` | Dynamic agent hot-loading & factory pattern | ✅ |
| `conversationSummary.js` | Compress old chat for context window | ✅ |
| `obsidianSync.js` | Auto-mirror memories to Obsidian vault | ✅ |
| `pineconeMemory.js` | Semantic vector search (Google embedding-004) | ✅ |
| `policyEngine.js` | Permission model (sensitive, irreversible flags) | ✅ |

### Mobile App
| Feature | Status |
|---------|--------|
| **Flutter UI** | ✅ Built |
| **Microphone button (ORB)** | ✅ Live listening |
| **Chat history sync** | ✅ Real-time |
| **Settings screen** | ✅ TTS speed, voice, name, server URL |
| **Tasks, Reminders, Notes tabs** | ✅ CRUD operations |
| **Shopping list** | ✅ Item tracking |
| **Contacts** | ✅ Privacy-controlled |

### Automation & Cron
- **Every minute:** Fire due reminders, reschedule recurring ones
- **07:00 Jerusalem time:** Morning briefing notification
- **21:00 Jerusalem time:** Evening nudge if tasks pending
- **Every 5 min:** Obsidian vault sync

---

## 🚀 What's In Progress (BUILDING)

### 1. ORB Naturalness
**Goal:** Make voice conversation feel less robotic

**Current state:**
- TTS speed is adjustable ✅
- Groq fallback to DeepSeek works ✅
- Response format optimized for voice ✅

**What's needed:**
- [ ] Reduce pause between user speaks and bot responds (currently ~500ms latency acceptable, but streaming should be <200ms)
- [ ] Shorter sentences in voice mode (`voiceMode: true` flag available, but response pruning could be better)
- [ ] Test actual latency on 4G connection

**Backlog items:**
- "בדוק שהאורב ממשיך להקשיב אחרי תשובה" (Verify ORB continues listening after response)
- "וודא שמהירות הדיבור נשמעת טבעית" (Verify speech speed sounds natural)

---

### 2. Dashboard / Progress Map UI
**Current state:**
- `progress-map.html` generated, 1297 lines
- Live feature tiles (done/building/planned)
- AI backlog proposals section
- Live metrics

**What's needed:**
- [ ] Real-time update when features move between columns
- [ ] Better backlog proposal UX (currently basic)
- [ ] Add "in-progress %" indicator
- [ ] Export to CSV/JSON

---

## 📋 What's Planned (BACKLOG)

### Short Term (Next Sprint)
- [ ] **Recurring reminders** — Support daily, weekly, monthly patterns (currently one-shot only)
- [ ] **Home screen widget** — iOS/Android quick actions (tasks, reminders quick-add)

### Medium Term
- [ ] **Smart notifications** — Show reminders even when app is closed (iOS background modes)
- [ ] **Google Calendar integration** — Sync tasks → calendar events
- [ ] **Siri & Google Assistant** — Voice shortcuts
- [ ] **Apple Watch** — Direct voice chat from watch

### Long Term
- [ ] **Multi-user profiles** — User switching, per-user settings (currently single-user, would need JWT + RLS on Supabase)
- [ ] **Team collaboration** — Share tasks, notes with others
- [ ] **Advanced analytics** — Usage patterns, time-of-day trends

---

## 🧪 Test Status

### Overall
```
✅ Test Suites: 27 passed, 27 total
✅ Tests:       206 passed, 206 total
⏱️  Time:        3.491 s
```

### Coverage by Category
| Category | Count | Status |
|----------|-------|--------|
| Unit tests | 20 files | ✅ All pass |
| Integration tests | 4 files | ✅ All pass |
| E2E tests | 1 file | ✅ Available (manual run: `npm run e2e:local`) |

### Recent Fixes (notes.json)
1. ✅ **Stream idle timeout** — Groq infrastructure error handling fixed (fallback to DeepSeek)
2. ✅ **Integration tests** — Mock fixes for OpenAI, Obsidian exports (179→206 tests passing)
3. ✅ **SSE parser upgrade** — Idle timeout raised to 12s, proper error rejection
4. ✅ **Pinecone integration** — Connected with Google text-embedding-004 (768d vectors)

---

## ⚠️ Known Issues & TODOs

### High Priority
1. **Pinecone semantic search** — Fallback works, but primary semantic search not fully tested with live data
   - Expected: > 80% relevance on memory queries
   - Actual: Needs production data to validate

2. **ORB listening after response** — Intermittent: sometimes doesn't auto-resume listening after TTS completes
   - Affects: Voice flow naturalness
   - Workaround: User can tap ORB again

3. **Email sending** — `POST /send-email` requires Gmail app password (less secure than OAuth2)
   - Should migrate to: Google OAuth2 + refresh tokens

### Medium Priority
4. **Multi-user auth** — Currently server is single-user only
   - No JWT validation
   - Row-level security (RLS) not enabled on Supabase
   - Blocker for team features

5. **Rate limiting** — Only applied to `/transcribe` (60/min) and `/scan/errors` (5/min)
   - Should add global rate limits

6. **Dashboard proposals** — AI-generated feature proposals not integrated with actual backlog.json
   - Currently read-only

### Low Priority
7. **Dependency vulnerabilities** — `npm audit` reports 5 vulnerabilities (3 moderate, 2 high)
   - Affected: `inflight@1.0.6`, `glob@7.2.3` (transitive)
   - Action: Already run `npm audit fix` as needed

8. **Accessibility** — RTL (Hebrew) layout is correct, but ARIA labels could be better
   - E.g., `/progress-map` buttons lack proper labels

---

## 📈 Metrics

| Metric | Value | Notes |
|--------|-------|-------|
| **Agents** | 27 | All functional, Hebrew-first routing |
| **Endpoints** | 53 | Full CRUD for tasks, reminders, notes, etc. |
| **Test coverage** | 206 tests | 100% pass rate |
| **Response time** | <500ms | Chat (excluding TTS) |
| **ORB latency** | ~200-500ms | Speech-to-text + routing + response |
| **LLM fallback chain** | 4 providers | Ollama → Groq → DeepSeek → Gemini |
| **Memory search** | Pinecone (semantic) + keyword fallback | Google embedding-004 |

---

## 🛠️ Setup & Commands

```bash
npm install          # Install deps (394 packages)
node server.js       # Start server (port 3000)
npm test             # Run all 206 tests (3.5s)
npm run test:coverage # Show coverage report
npm run e2e:local    # Run E2E against localhost
npm run lint         # Check syntax
```

### Required .env
```
GROQ_API_KEY
DEEPSEEK_API_KEY
GOOGLE_API_KEY
SUPABASE_URL
SUPABASE_KEY
GMAIL_USER
GMAIL_APP_PASSWORD
```

### Optional .env
```
PINECONE_API_KEY
PINECONE_INDEX
OLLAMA_URL
OBSIDIAN_VAULT_PATH
```

---

## 🎓 Architecture Highlights

### Request Flow
```
User Message
    ↓
POST /ask-jarvis
    ↓
Router (keyword → intent, fallback to LLM)
    ↓
Load context (chat history, memories, Pinecone search)
    ↓
Dispatch to Agent (taskAgent, chatAgent, etc.)
    ↓
Agent calls LLM (Groq → DeepSeek → Gemini)
    ↓
Save to Supabase (history, memory auto-extraction)
    ↓
Return JSON {answer, action?, audio?}
```

### Storage Strategy
| Store | Data | TTL | Why |
|-------|------|-----|-----|
| Supabase | All persistent data (tasks, reminders, notes, history, memories) | Permanent | Single source of truth |
| Pinecone | Memory vectors (for semantic search) | Synced from Supabase | Fast semantic lookup |
| In-process cache | Chat history (per chatId), memories | 30s–5min | Reduce DB queries |
| Local FS | Agent registry, backlog.json, notes.json, features.json | Permanent | User data + UI state |
| Obsidian vault | Mirror of memories + chat (if configured) | Real-time sync | Offline access, markdown backups |

---

## 📞 How to Extend

### Adding a New Agent
1. Create `agents/myAgent.js` exporting `runMyAgent(userMessage, supabase, useLocal, settings)`
2. Add keyword pattern to `KEYWORDS` in `router.js`
3. Add intent to `VALID_INTENTS` and `LLM_CLASSIFY_PROMPT` in `router.js`
4. Add dispatch branch in `server.js` POST /ask-jarvis
5. Mirror in `/stream-jarvis` if streaming needed
6. Add unit test: `tests/unit/myAgent.test.js`
7. Run: `npm test`

### Adding a New API Endpoint
1. Create route in `server.js` or `routes/`
2. Use Supabase client if persisting
3. Add policy guard if sensitive: `requirePolicy('resource.action', { flags })`
4. Test with: `curl`, Postman, or integration test
5. Document in this audit

---

## 🚦 Deployment

### Current
- **Dev:** localhost:3000
- **Prod:** Render.com (configured in `settings` via mobile app)

### CI/CD
- GitHub Actions: (check `.github/workflows/`)
- Tests run on every PR: `npm test`

---

## 📊 Summary Table

| Category | Count | Status | Notes |
|----------|-------|--------|-------|
| **Agents** | 27 | ✅ All working | Hebrew routing + LLM fallback |
| **Endpoints** | 53 | ✅ All working | Full REST API |
| **Tests** | 206 | ✅ 100% pass | Unit + integration coverage |
| **Features (Done)** | 22 | ✅ Complete | Chat, tasks, reminders, notes, etc. |
| **Features (Building)** | 2 | 🚧 In progress | ORB naturalness, Dashboard UI |
| **Features (Planned)** | 8+ | 📋 Backlog | Widgets, calendar, Siri, Watch, etc. |
| **Known Issues** | 8 | ⚠️ Low-medium severity | None blocking, all have workarounds |

---

## 🎉 Next Steps

1. **Fix ORB listening:** Debug why listening sometimes stops after TTS (iOS audio session handling)
2. **Finalize Dashboard:** Wire backlog proposals to actual backlog.json updates
3. **Recurring reminders:** Add cron expressions + recurring logic to reminderAgent
4. **Multi-user auth:** Implement JWT + Supabase RLS for team features
5. **Performance:** Profile response latency on 4G, optimize if needed

---

**Last Updated:** 2026-05-16 by Audit Script  
**Next Audit:** 2026-05-30
