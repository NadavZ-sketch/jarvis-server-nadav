---
name: review
description: Full code review for the Jarvis server. Covers test coverage gaps, security vulnerabilities, code quality, and business logic. Use when asked to review a PR, review changes, or run /review.
---

# Jarvis Server — Code Review

## Instructions

Run the automated review scripts, interpret their output, and produce a consolidated Hebrew report.

---

### Step 1: Collect context

```bash
git diff origin/main...HEAD --stat
```

---

### Step 2: Run the three review scripts

Run all three in parallel:

```bash
node scripts/review-coverage.js 2>&1
node scripts/review-security.js 2>&1
node scripts/review-logic.js 2>&1
```

Each script exits with code 0 (clean) or 1 (findings that block merge).

---

### Step 3: Interpret results

Use this severity scale in the final report:
- 🔴 **קריטי** — blocks merge immediately
- 🟠 **גבוה** — must fix before merge
- 🟡 **בינוני** — should fix in a follow-up PR
- 🔵 **נמוך** — nice to have

**Coverage script output:**
- 🟠 = קובץ חדש עם כיסוי נמוך מ-30%
- 🟡 = קובץ קיים עם כיסוי מתחת לסף (60% שורות / 50% ענפים / 60% פונקציות)
- If a changed file has no test file at all → flag as 🟠 and recommend creating one

**Security script output:**
- Each finding includes `[RULE-ID] file:line` — include these in the report
- If exit code is 1, the PR **must not merge** until critical/high findings are resolved

**Logic script output:**
- Flags missing agent wiring, wrong signatures, missing cron timezone, SELECT *, etc.

---

### Step 4: Manual checks (quick scan, 2 minutes)

After running scripts, do a quick manual pass on the diff for things scripts can't catch:

1. **Business logic** — Does the change do what the PR description says? Any Hebrew edge cases (RTL, gender forms, timezone)?
2. **New LLM prompts** — Is the prompt in Hebrew? Does it have a fallback for empty/null LLM response?
3. **Supabase queries** — `.single()` without null-check on result? `.limit(1)` missing on open queries?
4. **Breaking changes** — Does anything change the shape of `{ answer, action }` returned to the mobile app?

---

### Step 5: Final report

Produce a consolidated report in Hebrew:

```
## סקירת קוד — [branch/PR name]

### 📊 כיסוי בדיקות
[output from review-coverage.js, grouped by severity]

### 🔒 אבטחה
[output from review-security.js]

### ⚙️ היגיון תפעולי
[output from review-logic.js]

### 👁️ בדיקה ידנית
[findings from Step 4]

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

**Decision rule:**
- Any 🔴 finding → ❌ חסום
- 3+ 🟠 findings → ❌ חסום
- 1-2 🟠 findings → 🔁 נדרשים תיקונים
- Only 🟡/🔵 → ✅ מאושר (with follow-up noted)
