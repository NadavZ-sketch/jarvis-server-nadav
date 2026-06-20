# מרכז שליטה — מפרט עיצוב מחדש
**תאריך:** 2026-06-20  
**סטטוס:** מאושר לפיתוח  
**קובץ מקור (מובייל):** `jarvis_mobile/lib/screens/progress_map_screen.dart` (260KB → יפוצל)

---

## רקע ומוטיבציה

### בעיות בגרסה הנוכחית
1. לא ניתן לדעת אם ג'רוויס משתפר לאורך זמן
2. פקודות לא מבוצעות במלואן — אין ראות על כשלים
3. אין מנגנון לשיפור ג'רוויס על בסיס ניסיון המשתמש
4. פיצ'רים חופפים ומפוזרים ללא סדר
5. חלק מהפיצ'רים מציגים תוצאות ריקות/מזויפות

### עקרונות הגרסה החדשה
- **רק נתונים אמיתיים** — אם אין נתון, לא מציגים widget
- **ראות מלאה** — כל פקודה עם לוג מלא: agent → model → ms → תוצאה
- **לולאת שיפור** — משוב → ניתוח → הצעות → ייצוא לפיתוח
- **ממשק נקי** — כרטיסיות מצומצמות, פתיחה בלחיצה

---

## ארכיטקטורת ניווט

### מבנה קיים (לא משתנה)
`main_shell.dart` — 4 טאבים תחתיים:
- 0: בית (`smart_home_screen.dart`)
- 1: שיחה
- 2: משימות
- 3: מרכז שליטה ← **זה מה שמשתנה**

### מבנה חדש — מרכז השליטה
4 לשוניות עליונות (TabBar) במקום 6:

| # | שם | תוכן עיקרי |
|---|----|----|
| 0 | סקירה | סטטוס שרת · מודלים פעילים · לוג ביצוע · סוכנים (accordion) |
| 1 | אינטליגנציה | ציון שבועי · לולאת משוב · הצעות אוטו-כוונון · expectation vs reality |
| 2 | סדנת פיתוח | הצעת פיצ'ר/באג → שיחה → ספק → ייצוא + כלים: Prompt Library / Test Recorder / Changelog |
| 3 | בדיקות | E2E reports + flaky detection + תזמון · סקרים + ציר זמן + שאלות אדפטיביות |

### פיצול קבצים
```
progress_map_screen.dart (260KB) → 5 קבצים:
  screens/control_center/
    control_center_shell.dart      # TabBar + state management
    tab_overview.dart              # טאב 0
    tab_intelligence.dart          # טאב 1
    tab_devworkshop.dart           # טאב 2
    tab_tests.dart                 # טאב 3
```

---

## טאב 0 — סקירה

### סטטוס שרת
- Ping לכל X שניות (adaptive: 30s בפוקוס, 120s ברקע)
- מציג: online/offline + latency בms

### שרשרת מודלים פעילה
שורה אופקית: `Ollama → Groq → DeepSeek → Gemini`
- המודל הפעיל כרגע מוצג עם highlight (border + dot ירוק)
- נתון מגיע מ-`GET /health` (להוסיף שדה `active_model`)

### מדדי ביצועים — 7 ימים
3 כרטיסים: הודעות · זמן תגובה ממוצע · שיעור הצלחה  
כל כרטיס עם חץ מגמה (↑↓→) ואחוז שינוי

### לוג ביצוע חי
10 הרשומות האחרונות מ-`GET /execution-log`:
```
cmd (קצוב) | agent | model | Xms | ✓/✗
```
עמודה לכל שדה. ✗ פתיחה לפרטים.  
עדכון כל 30 שניות.

### סוכנים פעילים (Accordion)
- מוצגים רק סוכנים שנקראו ב-7 הימים האחרונים
- כל כרטיס: שם + פעמים שנקרא + סטטוס + last used
- לחיצה פותחת: פרטי שימוש, מגמה, אחרון הצלחה/כשל

---

## טאב 1 — אינטליגנציה

### ציון שבועי (0–100)
מורכב מ-3 מדדים (משקולות שוות):
- שיעור הצלחת בקשות (מלוג ביצוע)
- ממוצע דירוגי 👍👎 (מהמשוב האינליין)
- ציוני סקרים שבועיים

### לולאת משוב — תגובות אחרונות
5 תגובות אחרונות שטרם דורגו:
- תקציר תגובה + כפתורי 👍 👎
- POST `/feedback` → שמירה ב-Supabase (`message_feedback` table)

### הצעות אוטו-כוונון
Jarvis מנתח דפוסים ומציע שיפורים.  
כל הצעה: תיאור + כפתורי אשר/דחה.  
מגיע מ-`GET /insights/proposals`.

### לוג ציפייה מול מציאות
השוואה: מה ביקש המשתמש ← מה החזיר הסוכן ← האם תאם  
נתון מ-`GET /execution-log` (שדה `user_expectation` אם קיים)

### דפוסי שימוש
Chip cloud של נושאים נפוצים בשבוע האחרון (מ-`GET /stats`)

---

## טאב 2 — סדנת פיתוח

### תצוגה ראשית
**רשת הצעות (2 כפתורים):**
- ➕ הצע פיצ'ר
- 🐛 דווח בעיה

**שורת כלים (3 כפתורים):**  
Prompt Library | Test Recorder | Changelog

**רשימת הצעות פתוחות:**  
כל הצעה: כותרת + סטטוס (טיוטה/ספק/יוצא) + תאריך

---

### תצוגת סדנה (Workshop)
נפתחת בלחיצה על הצעה קיימת או יצירת חדשה.

**שרשור שיחה:**  
היסטוריית הודעות + שדה קלט בתחתית.  
POST `/progress-map/command` עם `{ type: 'workshop', proposalId, message }`

**ספק אוטומטי (מתעדכן בזמן אמת):**
```
שם: ___
סוג: פיצ'ר / תיקון / שיפור UX
תיאור: ___
קריטריוני קבלה: ___
```

**4 כפתורי ייצוא:**
- 📄 ספק → `docs/superpowers/specs/`
- 🤖 AI Prompt → clipboard
- 🐙 GitHub Issue → `mcp__github__issue_write`
- 📋 העתק לכלוב

---

### Prompt Library
רשימת prompts מערכתיים עם גרסאות:

| שדה | תיאור |
|-----|-------|
| `id` | UUID |
| `name` | שם הפרומפט |
| `content` | תוכן |
| `version` | מספר גרסה (1, 2, 3...) |
| `created_at` | תאריך |
| `is_active` | האם פעיל |

CRUD: GET/POST/PUT/DELETE `/prompt-library`  
פעולות UI: ערוך · השווה גרסאות · שחזר גרסה ישנה

---

### Multi-turn Test Recorder
מקליט שיחות כ-test cases ומריץ אותן מחדש.

**מבנה test case:**
```json
{
  "id": "tc_001",
  "name": "שם הבדיקה",
  "turns": [
    { "input": "...", "expected_intent": "reminder", "expected_contains": ["תזכורת"] }
  ],
  "last_run": "2026-06-20T14:00:00Z",
  "last_status": "pass" | "fail" | "pending"
}
```

**API:** GET/POST `/test-cases` · POST `/test-cases/:id/run`  
**UI:** רשימה עם pass/fail + כפתור "הקלט שיחה חדשה" + כפתור "הרץ"

---

### Changelog Auto-Generator
**Flow:**
1. לחץ "ייצר מ-git commits"
2. `GET /changelog/generate` → server קורא `git log` + LLM מקטלג
3. מוצג: feature / fix / UX עם עריכה ידנית
4. ייצוא: Markdown לקובץ | GitHub Release

**קטגוריות:** ✨ חדש · 🐛 תיקון · 💄 UX · ⚙️ תשתית

---

## טאב 3 — בדיקות וסקרים

### E2E Reports

**רשימה:**
- סיכום: אחוז הצלחה · מספר בדיקות · כמה flaky
- כפתור "הרץ את כל הבדיקות" → POST `/e2e-reports` (existing endpoint)
- כרטיס תזמון: ידני / יומי / כל שעתיים / אחרי deploy → שמירה ב-user profile

**מיני-טרנד:**  
5 ברים בגובה משתנה ליד כל דוח (5 ריצות אחרונות — ירוק/אדום/צהוב)

**Flaky Detection:**  
בדיקה שיש לה ≥2 עברו + ≥2 נכשלו מהריצות החמש האחרונות → badge `⚡ לא יציב` + לוח ריצות בפירוט

**פירוט דוח:**
- Progress bar
- כל צעד: שם + תיאור מה נבדק + agent + ms + תוצאה
- Toggle "הסבר מלא" → תיאור טבעי + JSON output בפועל
- צעד כושל: שגיאה מדויקת + "למה" בשפה פשוטה

**ניתוח Jarvis (דוחות נכשלים/flaky בלבד):**
- תקציר כללי
- שורש הבעיה
- הצעת תיקון

**4 ייצואים:** סדנת פיתוח · GitHub Issue · AI Prompt · clipboard

---

### סקרים

**ציר זמן:**  
גרף 6 שבועות: ציון כללי (סגול) + תגובות חיוביות (ירוק)  
נתון מ-`GET /stats/weekly-score?weeks=6`

**דירוג אינליין (נמצא בטאב שיחה, מזין לכאן):**  
👍👎 אחרי כל תגובת ג'רוויס → POST `/feedback/inline`  
ה-widget מסתלק אחרי דירוג או לחיצת "דלג"

**שאלות אדפטיביות:**  
שאלת scale עם `lowThreshold` (≤2) ו-`highThreshold` (≥4):
- ציון נמוך → מופיעה שאלת `lowFollowup`
- ציון גבוה → מופיעה שאלת `highFollowup`

**ייצוא תוצאות:**
- CSV: כל תשובות גולמיות + timestamp → `GET /surveys/export?format=csv`
- PDF: דוח מסוכם → `GET /surveys/export?format=pdf`
- Sentiment: ניתוח AI של טקסט חופשי → `POST /surveys/analyze-sentiment`

---

## שינויים בשרת (Node.js)

### Endpoints חדשים

| Method | Path | תיאור |
|--------|------|-------|
| `GET` | `/execution-log` | 50 הרשומות האחרונות: `{cmd, agent, model, ms, status, error?}` |
| `GET` | `/stats/weekly-score` | ציון 0–100 + breakdown + היסטוריה 6 שבועות |
| `POST` | `/feedback` | דירוג תגובה: `{message_id, rating: 'up'|'down', chatId}` |
| `POST` | `/feedback/inline` | 👍👎 מהשיחה, ללא message_id |
| `GET/POST/PUT/DELETE` | `/prompt-library` | CRUD לספריית פרומפטים |
| `GET/POST` | `/test-cases` | רשימת test cases + יצירה |
| `POST` | `/test-cases/:id/run` | הרצת test case |
| `GET` | `/changelog/generate` | ייצור changelog מ-git log + LLM |
| `GET` | `/surveys/export` | `?format=csv|pdf` |
| `POST` | `/surveys/analyze-sentiment` | ניתוח sentiment לתשובות חופשיות |
| `GET/PUT` | `/e2e-schedule` | קריאה/שמירה של תזמון E2E |

### שינויים ב-endpoints קיימים

| Endpoint | שינוי |
|----------|-------|
| `GET /health` | הוסף שדה `active_model: string` |
| `GET /stats` | הוסף `weekly_score`, `trend`, `positive_rate` |
| `GET /e2e-reports` | הוסף `flaky_count`, `runs_history[]` לכל דוח |

### טבלאות Supabase חדשות

```sql
-- דירוגי תגובות
CREATE TABLE message_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id TEXT,
  chat_id TEXT,
  rating TEXT CHECK (rating IN ('up', 'down')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- לוג ביצוע
CREATE TABLE execution_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cmd TEXT,
  agent TEXT,
  model TEXT,
  duration_ms INTEGER,
  status TEXT CHECK (status IN ('ok', 'fail')),
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ספריית פרומפטים
CREATE TABLE prompt_library (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  content TEXT NOT NULL,
  version INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Test cases
CREATE TABLE test_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  turns JSONB NOT NULL,
  last_run TIMESTAMPTZ,
  last_status TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## סדר יישום מוצע

### שלב 1 — תשתית שרת (ללא שינויי UI)
1. הוסף `execution_log` table + middleware שרושם כל בקשה
2. מימש `GET /execution-log`
3. הוסף `active_model` ל-`GET /health`
4. מימש `POST /feedback` + `message_feedback` table

### שלב 2 — פיצול קובץ Flutter
1. צור `screens/control_center/` directory
2. חלץ כל טאב לקובץ נפרד
3. צור `control_center_shell.dart`
4. וודא שהניווט עובד זהה

### שלב 3 — טאב 0 (סקירה)
1. שרשרת מודלים (מ-`/health`)
2. לוג ביצוע (מ-`/execution-log`)
3. Accordion סוכנים (מ-`/stats`)
4. מדדי 7 ימים (מ-`/stats`)

### שלב 4 — טאב 3 (בדיקות) — פחות שינויים בשרת
1. Flaky detection (לוגיקה ב-Flutter)
2. כרטיס תזמון (`/e2e-schedule`)
3. פירוט צעדים עם הסברים
4. ציר זמן סקרים (`/stats/weekly-score`)
5. שאלות אדפטיביות (לוגיקה ב-Flutter)
6. ייצוא CSV/PDF (`/surveys/export`)

### שלב 5 — טאב 1 (אינטליגנציה)
1. ציון שבועי (`/stats/weekly-score`)
2. לולאת משוב (מ-`message_feedback`)
3. הצעות אוטו-כוונון (`/insights/proposals`)
4. דירוג אינליין בטאב שיחה

### שלב 6 — טאב 2 (סדנת פיתוח)
1. Workshop flow (שיחה + ספק)
2. Prompt Library CRUD
3. Test Recorder
4. Changelog Generator

---

## הגדרות נוספות

### Role gating
- `regular`: טאבים 0 + 3 בלבד
- `admin`: כל הטאבים

### אין mock data
אם endpoint לא מחזיר נתונים — מציגים empty state עם הסבר, לא מספרים מדומים.

### RTL
כל הממשק עברית RTL. כפתורי ייצוא עם tooltip באנגלית.

### ביצועים
- Lazy load כל טאב רק בביקור ראשון
- Adaptive polling: 30s בפוקוס, 120s ברקע
- TTL cache: execution-log (30s), weekly-score (5min)
