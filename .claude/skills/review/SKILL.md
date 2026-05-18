---
name: review
description: Full code review for the Jarvis server. Covers test coverage gaps, security vulnerabilities, code quality, and business logic. Use when asked to review a PR, review changes, or run /review.
---

# Jarvis Server — Code Review

## Instructions

Run all five review passes in order. Report findings in Hebrew. Use the severity scale:
- 🔴 **קריטי** — blocks merge
- 🟠 **גבוה** — must fix before merge
- 🟡 **בינוני** — should fix soon
- 🔵 **נמוך** — nice to have

---

### Step 1: Collect Changed Files

```bash
git diff origin/main...HEAD --name-only
git diff origin/main...HEAD --stat
```

List every changed file and its category (agent / service / controller / route / test / config).

---

### Step 2: Test Coverage Analysis

**2a. Run coverage:**
```bash
npx jest --coverage --coverageReporters=text 2>&1 | grep -E "(PASS|FAIL|%|Uncovered)"
```

**2b. For each changed non-test file, check:**
- Does a corresponding test file exist in `tests/unit/` or `tests/integration/`?
- What is the line/branch coverage percentage?
- Which lines are uncovered (from the `Uncovered Line #s` column)?

**2c. Flag these patterns as coverage gaps:**
- New exported function with 0 test cases
- New branch (`if/else`, `try/catch`) with no test covering the alternate path
- New error path (`catch (err)`) with no test that triggers it
- Changed JSON parsing logic with no test for malformed input
- Changed LLM prompt handling with no test for unexpected LLM output

**2d. Report format:**
```
📊 כיסוי בדיקות
- agents/myAgent.js: 45% שורות (55% ענפים) — חסרות בדיקות לשורות: 34-67, 89
- ❌ אין קובץ בדיקה ל-services/newService.js
- ⚠️  פונקציה חדשה `runFoo()` ב-agents/foo.js — אין בדיקה
```

---

### Step 3: Security Scan

For every changed file, check the following. Report file:line for each finding.

**3a. Injection**
- User input passed directly to `require()`, `eval()`, `new Function()`, or `child_process`
- User input used to construct file paths without `path.resolve()` + boundary check
- Template literals with user data passed to shell commands
- LLM output written to filesystem without sanitization (especially in `agentFactoryAgent.js`)

**3b. Path Traversal**
- `path.join()` or `path.resolve()` with user-controlled segments
- Missing check: `resolvedPath.startsWith(SAFE_DIR + path.sep)`
- `require()` with a path that comes from a database, file, or user input

**3c. Authentication & Authorization**
- New endpoint without `requirePolicy()` middleware on sensitive actions
- WebSocket handler accepting user-supplied IDs without validation
- OAuth flows missing `state` parameter validation
- Hardcoded credentials or test tokens that might reach production

**3d. Information Disclosure**
- `res.status(500).json({ error: err.message })` — leaks internal error details
- Stack traces or file paths in responses
- API keys or secrets in log output (`console.log` with env vars)

**3e. CORS & CSRF**
- New `app.use(cors({ origin: '*' }))` or similar wildcard
- State-changing endpoints (POST/PUT/DELETE) without CSRF protection
- WebSocket server created without `verifyClient` origin check

**3f. Rate Limiting**
- New public endpoint without `_rl()` rate limiter applied
- Existing limiter with `max` > 30/min on sensitive actions (email, auth, scan)

**3g. Secrets in Code**
- Hardcoded API keys, passwords, or tokens (even test values)
- `.env` file accidentally committed
- Credentials in comments or test fixtures

**3h. Report format:**
```
🔒 אבטחה
🔴 agents/foo.js:42 — path traversal: filePath ממשתמש עובר ל-require() ללא בדיקת גבול
🟠 server.js:310 — endpoint POST /new-action חסר requirePolicy()
🟡 agents/bar.js:88 — err.message נחשף לקליינט
```

---

### Step 4: Code Quality

**4a. Error handling**
- `async` functions without `try/catch` that call external APIs or DB
- `catch` blocks that swallow errors silently (`catch (_) {}`) in non-trivial paths
- Missing null-check before accessing `.data[0]` from Supabase results

**4b. LLM response parsing**
- JSON extracted with `lastIndexOf('{')` instead of `indexOf('{')` (known bug pattern)
- No fallback when LLM returns empty string or non-JSON
- Prompt built by string concatenation of user input without sanitization

**4c. Agent patterns**
- Agent function signature matches: `async function run*Agent(userMessage, supabase, useLocal, settings)`
- Returns `{ answer: string, action?: object }` — no extra fields
- No direct `process.exit()` or throws that escape to server.js

**4d. Async patterns**
- `await` inside `.forEach()` (use `for...of` or `Promise.all`)
- Unhandled Promise rejections (missing `.catch()` on fire-and-forget calls)
- `setImmediate` / background tasks that could silently fail

**4e. Report format:**
```
🧹 איכות קוד
🟠 agents/foo.js:55 — JSON parsing: lastIndexOf('{') — שים לב לבאג הידוע
🟡 agents/bar.js:30 — forEach עם await — שנה ל-for...of
🔵 server.js:200 — חסר null-check לפני data[0].id
```

---

### Step 5: Operational & Business Logic

**5a. Intent routing (if `router.js` changed)**
- Does the new keyword regex match all Hebrew variants of the intent?
- Is there a collision with an existing intent (e.g., `תזכיר` matches both `reminder` and `memory`)?
- Is the intent added to `VALID_INTENTS` and `LLM_CLASSIFY_PROMPT`?
- Is there a matching `case` in the `/ask-jarvis` dispatch chain in `server.js`?

**5b. Agent dispatch (if `server.js` changed)**
- New agent imported and wired in both `/ask-jarvis` and `/stream-jarvis`?
- Background agents (`code_error`, `e2e`) use `setImmediate` — is the new agent latency-sensitive?

**5c. Supabase schema (if new table or column)**
- Migration applied?
- Select queries use `.select('specific_columns')` not `*` for sensitive tables
- Row-level security (RLS) considered?

**5d. Cron jobs (if cron changed)**
- Timezone set to `Asia/Jerusalem`?
- Idempotent (safe to run twice)?
- Handles Supabase being unavailable?

**5e. Business logic correctness**
- Does the change do what the PR description says it does?
- Are there edge cases the author didn't consider (empty input, Hebrew vs. English, null from DB)?
- Does it break any existing agent behavior visible in the test suite?

**5f. Report format:**
```
⚙️ היגיון תפעולי ועסקי
🔴 agents/newAgent.js לא רשום ב-router.js ולא ב-server.js — לא נגיש
🟠 agents/reminderAgent.js: חישוב DST לא מטפל בחזרה לשעון חורף
🔵 הודעת ה-PR לא מסבירה למה נשנה הטיימאוט מ-3000 ל-5000ms
```

---

### Step 6: Final Report

Produce a consolidated report in Hebrew:

```
## סקירת קוד — [שם ה-PR / branch]

### 📊 כיסוי בדיקות
[ממצאים]

### 🔒 אבטחה
[ממצאים]

### 🧹 איכות קוד
[ממצאים]

### ⚙️ היגיון תפעולי ועסקי
[ממצאים]

---
### סיכום
| חומרה | מספר ממצאים |
|-------|-------------|
| 🔴 קריטי | N |
| 🟠 גבוה | N |
| 🟡 בינוני | N |
| 🔵 נמוך | N |

**המלצה:** ✅ מאושר לאיחוד / 🔁 נדרשים תיקונים / ❌ חסום
```

If there are 🔴 Critical or more than 2 🟠 High findings, recommend blocking the merge.
