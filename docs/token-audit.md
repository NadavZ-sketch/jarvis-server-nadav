<div dir="rtl">

# אודיט צריכת טוקנים — מרכז הבקרה / מפת ההתקדמות (Progress Map)

> **מסמך מדידה בלבד.** לא שונה אף קוד יישומי ולא שונתה אף התנהגות. הקובץ היחיד שנכתב הוא מסמך זה (`docs/token-audit.md`). כל ההמלצות בהמשך הן **לא מיושמות** — רק הצעות לעתיד.

## מטרה

למפות היכן נשרפים טוקנים של מודלי השפה (LLM) באזור מרכז הבקרה / מפת ההתקדמות, להעריך עלות יחסית, ולהציע ייעול עתידי.

---

## רקע: מחסנית ה-LLM (`agents/models.js`)

שלוש נקודות כניסה רלוונטיות:

- **`callGemma4(messages, useLocal=true, maxTokens=800, opts)`** — קריאה לא-זורמת. `agents/models.js:103`.
- **`callGemma4Stream(...)`** — גרסה זורמת (SSE) ל-`/stream-jarvis`. `agents/models.js:226`. **לא בשימוש** ע"י אנדפוינטים של מרכז הבקרה.
- **`callGeminiWithSearch(prompt)`** — Gemini עם Google Search grounding. `agents/models.js:271`. **לא בשימוש** ע"י מרכז הבקרה (משמש את newsAgent/weatherAgent בלבד).

### שרשרת ה-failover (`agents/providerConfig.js`)

ברירת מחדל בענן (`useLocal=false`, ללא `cloudProvider` מועדף) — `CLOUD_DEFAULT_ORDER` ב-`providerConfig.js:67`:

| # | ספק | מודל | timeout |
|---|-----|------|---------|
| 1 | **groq** (ראשי) | `llama-3.3-70b-versatile` | 7s |
| 2 | deepseek | `deepseek-chat` | 9s |
| 3 | openrouter (אם יש מפתח) | `deepseek/deepseek-v4-flash:free` | 10s |
| 4 | gemini (terminal) | `gemini-2.5-flash-lite` | 15s |

כל אנדפוינטי מרכז הבקרה קוראים עם `useLocal=false` ולכן הספק האפקטיבי בפועל הוא בדרך כלל **Groq / llama-3.3-70b-versatile** (אלא אם נופל ל-fallback). `top_p` מקובע ל-`0.9` (`models.js:40`), `temperature` ברירת מחדל `0.5` (`providerConfig.js:85`).

**הערה חשובה לעלות:** `max_tokens` מגביל רק את **פלט** המודל. עלות הפרומפט (קלט) נקבעת מאורך ה-messages ואינה מוגבלת בקוד הזה.

---

## הנחות אומדן

- אנגלית/JSON/קוד: **~1 טוקן ≈ 4 תווים**.
- עברית: **~1 טוקן ≈ 2.5 תווים** (טוקנייזרים מפצלים עברית לתת-מילים; ערך שמרני).
- האומדנים הם לפרומפט **הסטטי** (system + תבנית user) בתוספת מילוי טיפוסי. תוכן דינמי (רשימות פיצ'רים, פרומפט קיים של סוכן, תשובות משתמש) משתנה ולכן מצוין כטווח.
- טוקני **פלט** = `max_tokens` במקרה הגרוע; בפועל לרוב נמוך יותר.

---

## היכן נשרפים הטוקנים

| Endpoint | מודל/ספק | אומדן prompt (tokens) | max_tokens (פלט) | תדירות טיפוסית | הערכת עלות יחסית |
|----------|----------|----------------------|------------------|----------------|------------------|
| `POST /dashboard/backlog/generate` <br/>`server.js:3783` | Groq · llama-3.3-70b (cloud) | ~250–500 (system+סטטוס פיצ'רים דינמי) | **2000** | נדיר — לחיצת כפתור "ייצר Backlog" (`progress-map.html:774`) | **גבוה** (max_tokens הכי גדול) |
| `POST /dashboard/generate-prompt` <br/>`server.js:3897` | Groq · llama-3.3-70b (cloud) | ~350–600 (פרומפט עברי ארוך + `description` משתמש) | **1500** | נדיר — לחיצת כפתור (`progress-map.html:815`) | **גבוה** |
| `POST /progress-map/build-prompt` <br/>`routes/agentCenter.js:228` | Groq · llama-3.3-70b (cloud) | ~300–900 (תלוי באורך `agent.prompt` הקיים + תשובות הבהרה) | **800** | נדיר — שלב 2 באשף שינוי סוכן (`progress-map.html:1493`) | **בינוני-גבוה** |
| `POST /progress-map/analyze` <br/>`routes/agentCenter.js:171` | Groq · llama-3.3-70b (cloud) | ~200–350 (system קצר + הקשר סוכן + תבנית JSON) | **400** | נדיר — שלב 1 באשף שינוי סוכן (`progress-map.html:1453`) | **בינוני** |
| `POST /progress-map/metrics/query` <br/>`routes/agentCenter.js:146` | Groq · llama-3.3-70b (cloud) | ~150–400 (system קצר + טבלת מדדים דינמית + שאלה) | **300** | **לא נצרך** ע"י ה-UI כיום (אין קורא ב-`progress-map.html` או ב-Flutter) | **נמוך** |
| `GET /control-center/events` <br/>`server.js:2460` | — אין LLM — | 0 | 0 | תדיר (polling 15–60s) | **אפס (לא LLM)** |
| `GET /stats` <br/>`server.js:1209` | — אין LLM — | 0 | 0 | תדיר (polling 30s בווב) | **אפס (לא LLM)** |

### פירוט הפרומפטים שנמדדו (ציטוט מיקום)

1. **`/dashboard/backlog/generate`** — פרומפט אנגלי בודד (string) שנבנה ב-`server.js:3792–3804`. כולל ספירה ושמות של פיצ'רים `done/building/planned` מתוך `features.json`. גודל סטטי ~1.4K תווים ≈ **~350 טוקן**; גדל עם מספר הפיצ'רים. `callGemma4(prompt, false, 2000)` ב-`server.js:3806`.

2. **`/dashboard/generate-prompt`** — פרומפט עברי ארוך (`server.js:3902–3919`) + `description` של המשתמש. הטקסט הסטטי ~1.0K תווים עבריים ≈ **~400 טוקן**. `callGemma4(prompt, false, 1500)` ב-`server.js:3921`.

3. **`/progress-map/build-prompt`** — system קצר (`routes/agentCenter.js:248`) + user template (`agentCenter.js:250–268`). ה-`agentCtx` מזריק את **הפרומפט הקיים של הסוכן** (`agent.prompt`, `agentCenter.js:238`). פרומפטי הסוכנים ב-registry קצרים (~150–300 תווים — ראו `services/agentRegistryService.js:65,88,108…`), ולכן הקלט הכולל ~750–2.3K תווים ≈ **~300–900 טוקן**. `callGemma4(..., false, 800)` ב-`agentCenter.js:274`.

4. **`/progress-map/analyze`** — system בן ~40 תווים (`agentCenter.js:182`) + user template (`agentCenter.js:187–194`) הכולל `agentCtx` קצר ותבנית JSON של שאלות. ~600–900 תווים ≈ **~250 טוקן**. `callGemma4(..., false, 400)` ב-`agentCenter.js:201`.

5. **`/progress-map/metrics/query`** — system בן ~50 תווים (`agentCenter.js:162`) + טבלת מדדים שנבנית מ-snapshot (`agentCenter.js:151–160`) + השאלה. גדל לינארית במספר הסוכנים. ~400–1K תווים ≈ **~150–400 טוקן**. `callGemma4(..., false, 300)` ב-`agentCenter.js:161`. **אין קורא ב-frontend** — נכון לעכשיו אינו צורך טוקנים בפועל.

---

## השפעת ה-Polling (events / stats) — ללא טוקנים

שני לולאות ה-polling של מרכז הבקרה **אינן** קוראות ל-LLM. הן צורכות רוחב פס ושאילתות Supabase בלבד.

### `GET /control-center/events` (אפליקציית Flutter)

- **קצב:** adaptive — מינימום 15s, idle 30s, מקסימום 60s. ראו `jarvis_mobile/lib/screens/progress_map_screen.dart:303,314–317`. backoff אחרי 3 ו-6 polls ללא שינוי.
- **בקשות/יום (לקוח פעיל בודד, מסך פתוח):** אם רץ ברצף 15s כל היום → ~5,760/יום; ב-cadence idle 30–60s טיפוסי → **~1,440–2,880/יום**. בפועל הרבה פחות, כי המסך לרוב לא פתוח 24/7 (ה-poller נעצר ב-`dispose`/`pause`).
- **גודל payload:** JSON של `{ generatedAt, alerts[], badges{} }` (`server.js:2617–2621`). ללא alerts — מאות בתים; עם alerts — בדרך כלל **~1–4KB**.
- **עלות צד-שרת:** עד 4 שאילתות Supabase count/select (e2e_reports, chat_history, user_surveys) + קריאת `backlog.json`. **אפס טוקני LLM.**

### `GET /stats` (דאשבורד ווב `progress-map.html`)

- **קצב:** `setInterval(... , 30000)` — כל **30s** יחד עם `/health` (`progress-map.html:1138`).
- **בקשות/יום (טאב פתוח רציף):** ~2,880/יום ל-`/stats` (+עוד ~2,880 ל-`/health`).
- **גודל payload:** אובייקט counts קומפקטי (chat/tasks/reminders/memories/notes/shopping + byCategory) — **<1KB** (`server.js:1251–1258`).
- **עלות צד-שרת:** 11 שאילתות count מקבילות (`Promise.allSettled`, `server.js:1222–1234`). **אפס טוקני LLM.**

> מסקנה: ה-polling הוא עומס תעבורה/DB בלבד. **אינו** מקור לצריכת טוקנים. צרכני הטוקנים היחידים הם 5 אנדפוינטי ה-POST מונעי-לחיצה שבטבלה.

---

## המלצות לייעול עתידי (לא מיושמות)

לפי סדר עדיפות (השפעה מול מאמץ):

1. **[גבוה] להוריד `max_tokens` ב-`/dashboard/backlog/generate` מ-2000.** `server.js:3806`. הפלט הוא JSON של 6 פריטי backlog; 2000 טוקני פלט הם החסם הגדול ביותר במערכת. ערך ~900–1100 צפוי להספיק וחותך עד ~45% מתקרת הפלט. *(מדידה: ספור טוקני פלט ממוצעים בפועל לפני קיבוע.)*

2. **[גבוה] להוריד `max_tokens` ב-`/dashboard/generate-prompt` מ-1500.** `server.js:3921`. הפרומפט המיוצר בד"כ קצר מ-1500 טוקן; ~1000 סביר. בנוסף — לקצץ את הטקסט הסטטי העברי הארוך (`server.js:3902–3919`) ע"י קיצור רשימת הקבצים/הסבר ההקשר (חוסך טוקני **קלט** בכל קריאה).

3. **[בינוני] מודל קטן/זול יותר לסיווג ולמשימות מובְנות.** `/progress-map/analyze` (`agentCenter.js:201`) ו-`/progress-map/metrics/query` (`agentCenter.js:161`) מייצרים JSON קצר/תשובה קצרה — מתאימים למודל קטן (למשל Groq llama-3.1-8b או Gemini flash-lite) במקום llama-3.3-70b. ניתן לממש דרך `opts.cloudProvider`/בחירת מודל ייעודית מבלי לגעת בשרשרת ה-failover הגלובלית.

4. **[בינוני] קיצור הפרומפט המוזרק ב-`/progress-map/build-prompt`.** `agentCenter.js:238` מזריק את כל `agent.prompt`. אם פרומפטי סוכנים יגדלו בעתיד, כדאי לקצץ/לתמצת לפני ההזרקה כדי לשמור על תקרת קלט נמוכה.

5. **[בינוני] Prompt caching / חלקים קבועים.** ה-system וה-prefix הסטטי ב-`backlog/generate`, `generate-prompt`, `analyze`, `build-prompt` זהים בין קריאות. אם עוברים לספק התומך ב-prompt caching (לדוגמה דרך מנגנון קאש בצד-ספק), ניתן להוזיל את החלק הקבוע. מול Groq הנוכחי — לפחות לאחד את הטקסטים הקבועים ולמזער כפילויות.

6. **[נמוך] להסיר/לגדר את `/progress-map/metrics/query` אם נשאר ללא שימוש.** `agentCenter.js:146`. כיום אין לו קורא ב-UI (לא בווב ולא ב-Flutter) ולכן 0 צריכה — אך הוא נתיב LLM פתוח. אם לא מתוכנן שימוש, להסירו מצמצם משטח עלות פוטנציאלי.

7. **[נמוך — תעבורה, לא טוקנים] Debounce/Throttle ל-polling.** ה-Flutter כבר עושה backoff אדפטיבי (`progress_map_screen.dart:314–317`). הווב (`progress-map.html:1138`) פולל קבוע 30s גם כשהטאב מוסתר — אפשר להשהות בעת `visibilitychange`/blur. **לא חוסך טוקנים** אך מקטין שאילתות Supabase ותעבורה.

8. **[נמוך — תעבורה] לכווץ payloadים של polling.** `/stats` ו-`/control-center/events` כבר קומפקטיים; שיפור שולי בלבד.

---

## הסתייגויות מדידה

- האומדנים מבוססים על יחס תווים↔טוקנים גס; טוקנייזר אמיתי (במיוחד לעברית) עשוי לסטות ב-±30% ומעלה.
- אומדני הקלט הם לטקסט **הסטטי + מילוי טיפוסי**. תוכן דינמי (מספר פיצ'רים ב-`features.json`, אורך `agent.prompt`, אורך `description`/`answers` של המשתמש) יכול להגדיל משמעותית את הקלט בפועל.
- טוקני הפלט נאמדו כתקרת `max_tokens` (תרחיש גרוע); הצריכה הממוצעת נמוכה יותר.
- "תדירות טיפוסית" איכותית — חמשת אנדפוינטי ה-LLM כולם מונעי-לחיצה (לא מתוזמנים/לא נפוללים), ולכן נדירים יחסית.
- הספק האפקטיבי הונח כ-Groq (ראש השרשרת); בעת fallback או העדפת ספק שונה, המודל והעלות עשויים להשתנות.

</div>
