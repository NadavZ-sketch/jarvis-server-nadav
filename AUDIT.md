# 📊 Jarvis Server — Progress Audit

**Updated:** 2026-07-01 | **Status:** ✅ All Tests Passing (1038/1038)

> For full architecture, endpoint list, and agent signatures, see **CLAUDE.md** —
> it's kept in sync with the codebase and is the source of truth for structure.
> This file tracks status snapshots, known issues, and what's next.

---

## 🎯 Overview

- **33 agents** (`agents/*.js`) — Hebrew keyword routing + LLM fallback, dispatched via `agents/dispatcher.js`
- **22 services** (`services/*.js`) — data-access seam, policy engine, priority/proactive engines, MCP client, etc.
- **~140 REST endpoints** (Express.js) — see CLAUDE.md's endpoint table for the full list
- **Supabase** backend for persistence, **Pinecone** for semantic memory search (optional)
- **Flutter mobile app** (`jarvis_mobile/`) with a 4-tab control center
- **1038 tests passing** (112 suites: unit + integration), 0 failing

---

## ✅ Recent Work

- Extracted the projects/milestones/sprints REST API (19 routes) out of `server.js` into
  `routes/projects.js` + `controllers/projectsController.js`, following the same pattern
  already used for tasks/reminders/chat. `server.js` dropped from 6153 → ~5815 lines.
  Added `tests/integration/projectsRoutes.test.js` (9 new tests) covering the extracted routes.
- Brain/constellation graph work (control-center visualization): physics-based node graph,
  knowledge tab v2, thinking/profile tabs v2 — see recent git history for details.

**Still inline in `server.js`:** ~120 routes across domains like memories, notes, shopping,
contacts, e2e-reports, surveys, dashboard/backlog/proposals, workshop chat, and calendar.
These are candidates for the same routes/controllers extraction in future passes — each
domain is generally self-contained (reads/writes one or two `repos` entries) which makes
incremental extraction low-risk, one domain at a time, with integration tests added per file.

---

## 🧪 Test Status

```
✅ Test Suites: 112 passed, 112 total
✅ Tests:       1038 passed, 1038 total
⏱️  Time:        ~7s
```

Run `npm test` for unit + integration, `npm run test:coverage` for thresholds
(~54% stmts/44% branches/51% funcs/57% lines — see `package.json`), `npm run e2e:local`
for the live E2E self-test runner against a local server.

---

## ⚠️ Known Issues & TODOs

### Verified as of this update
1. **`npm audit`** reports **14 vulnerabilities (4 moderate, 10 high)**, mostly transitive
   (`ws` uninitialized memory disclosure / memory-exhaustion DoS). Run `npm audit` for the
   current list before assuming these are unchanged; `npm audit fix` covers what it can
   without breaking changes.
2. **Rate limiting** is applied via `_rl()` on 49 distinct route registrations in `server.js`
   (not just `/transcribe` and `/scan/errors` — that was stale). Still no *global* default
   rate limit; routes without an explicit `_rl()` call are unlimited.
3. **`server.js` is still ~5815 lines.** The dispatcher/controllers/routes pattern exists
   and is being applied incrementally (see Recent Work above), but most domain CRUD is
   still inline in the main file.

### Carried forward, not re-verified this pass
- Multi-user auth: server is still single-user by design (no JWT/RLS) — this is a
  deliberate scope choice, not a bug, per CLAUDE.md's architecture.
- Dashboard AI-generated backlog proposals: worth re-checking whether `/dashboard/backlog/generate`
  and `/dashboard/backlog/analyze` are read-only or now write back to `backlog.json` — CLAUDE.md
  lists these as implemented endpoints, but this audit doesn't re-verify the write path.

---

## 📈 Metrics

| Metric | Value | Notes |
|--------|-------|-------|
| **Agents** | 33 | Hebrew-first routing, dispatched via `agents/dispatcher.js` |
| **Services** | 22 | Includes `dataAccess/` (per-table repos) and `mcp/` (MCP client) |
| **Endpoints** | ~140 | Full CRUD across tasks/reminders/notes/projects/memories/etc. |
| **Test coverage** | 1038 tests, 112 suites | 100% pass rate |
| **LLM fallback chain** | 5 providers | Ollama (local) → Groq → DeepSeek → OpenRouter → Gemini |
| **Memory search** | Pinecone (semantic) + keyword fallback | Falls back gracefully if `PINECONE_API_KEY` unset |
| **npm audit** | 14 vulnerabilities (4 moderate, 10 high) | Mostly transitive; re-check before treating as current |

---

## 🛠️ Setup & Commands

```bash
npm install                    # install dependencies
node server.js                 # start the server (port 3000)
npm test                        # run all unit + integration tests (1038 tests, ~7s)
npm run test:coverage           # coverage report
npm run e2e:local               # E2E self-tests against localhost
npm run lint                    # syntax validation
npm run review                  # coverage-gap + security + logic review
```

See CLAUDE.md's "Required & Optional Environment Variables" section for the full,
currently-accurate `.env` list — it's more complete than what used to be duplicated here.

---

## 📞 How to Extend

See CLAUDE.md's **Development Workflows** section ("Adding a New Agent", "Modifying Intent
Routing", "Adding Supabase Tables") — kept current there instead of duplicated here.

---

**Last Updated:** 2026-07-01
