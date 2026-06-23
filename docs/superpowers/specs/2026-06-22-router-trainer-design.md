# מאמן Router — מפרט עיצוב
**תאריך:** 2026-06-22  
**סטטוס:** ממתין לאישור לפיתוח  
**טאב:** סדנת פיתוח (Tab 2) — מחליף את "מקליט שיחה"

---

## רקע ומוטיבציה

כאשר ג'רוויס לא מזהה כוונה ברורה, הוא מנתב הודעות ל-`chat` (ברירת מחדל). המשמעות: הודעות שיכולות היו להפעיל agent ייעודי (תזכורת, קניות, ספורט וכו') — מטופלות כשיחה כללית.

הפיצ'ר **מאמן Router** נותן למשתמש ראות על הפערים האלה ומאפשר לתקן אותם: לבחור כוונה לכל הודעה ולהגדיר keyword שיזהה הודעות דומות בעתיד — ביצוע מיידי ללא הפעלה מחדש של השרת.

### מה הוחלט
- אחסון היסטוריה: `smart_telemetry_events` (ללא migration חדש)
- Keywords: `config/router-overrides.json` (hot-reload, קריאה רעננה בכל פנייה)
- התאמה: substring (לא regex)
- מגבלה: הוספה לכוונות קיימות בלבד (לא יצירת כוונות חדשות)
- ביצוע מיידי: override נכנס לתוקף בפנייה הבאה לשרת

---

## ארכיטקטורה

### שרת — שינויים ב-`agents/router.js`

**שלב 1 — רישום "default chat":**  
כאשר הודעה נופלת לברירת מחדל `chat`, נרשם אירוע לטבלת `smart_telemetry_events`:
```
event_type: 'router_chat_default'
payload: { message: userMessage, timestamp: ISO }
user_id: settings.userId (אם קיים)
```

**שלב 2 — בדיקת overrides (לפני KEYWORDS):**  
`classifyIntent()` תקרא `loadRouterOverrides()` ותבדוק substring מול ה-message (case-insensitive) לפני הבדיקה הרגילה של KEYWORDS. הפונקציה קוראת את הקובץ רעננה אחת ל-5 שניות (TTL cache קצר).

```javascript
// config/router-overrides.json — מבנה:
{
  "overrides": [
    { "keyword": "תשלח לאמא", "intent": "messaging" },
    { "keyword": "חלב", "intent": "shopping" }
  ]
}
```

**חשוב:** הבדיקה היא `message.toLowerCase().includes(keyword.toLowerCase())`.

### שרת — 4 endpoints חדשים ב-`server.js`

| Method | Path | תיאור |
|--------|------|--------|
| `GET` | `/router/training-events` | הודעות שנפלו ל-chat ברירת מחדל. מחזיר עד 50 אחרונות מ-`smart_telemetry_events` |
| `GET` | `/router/keywords` | קורא ומחזיר את `config/router-overrides.json` |
| `POST` | `/router/keywords` | מוסיף override: `{ keyword, intent }`. מוחק duplicates לפני הוספה |
| `DELETE` | `/router/keywords` | מוחק override: `{ keyword, intent }` ב-request body |

**GET /router/training-events — תגובה:**
```json
{
  "events": [
    {
      "id": "uuid",
      "message": "תשלח לאמא שאני בדרך",
      "created_at": "2026-06-22T10:30:00Z"
    }
  ]
}
```

**GET /router/keywords — תגובה:**
```json
{
  "overrides": [
    { "keyword": "תשלח לאמא", "intent": "messaging" },
    { "keyword": "חלב", "intent": "shopping" }
  ]
}
```

**POST /router/keywords — body:**
```json
{ "keyword": "תשלח לאמא", "intent": "messaging" }
```

**DELETE /router/keywords — body:**
```json
{ "keyword": "תשלח לאמא", "intent": "messaging" }
```

**כל ה-endpoints:** מחזירים `{ error: "..." }` עם status 400/500 במקרה שגיאה.

### קובץ `config/router-overrides.json`
- נוצר אוטומטית אם לא קיים (מבנה ריק: `{ "overrides": [] }`)
- נשמר מקומית בשרת (מתמיד — שרידות בין הפעלות)
- לא מתווסף ל-gitignore (הוא חלק מההגדרות, לא secrets)

---

## Flutter — tab_dev_workshop.dart

### מה מוחלף
הפונקציה `_recorderCard()` (מקליט שיחה) מוחלפת ב-`_routerTrainerCard()`.

### מבנה המסך — Router Trainer Card

ה-card מכיל `TabBar` בתוכו עם שתי לשוניות:
1. **"הודעות"** — הודעות שנפלו ל-chat ברירת מחדל
2. **"Keywords שלי"** — כל ה-overrides שנוספו

#### לשונית הודעות — Accordion UI

**מצב ברירת מחדל (מקופל):**
- כל הודעה = שורה קומפקטית: נקודת סטטוס + טקסט הודעה (נחתך עם ellipsis)
- רשימה ניתנת לגלילה, רוחב מלא של ה-card
- פיל "N פתוחות" ב-header

**לחיצה על שורה — התרחב inline:**
- שורה אחת פתוחה בכל פעם (פתיחת שורה אחרת סוגרת את הנוכחית)
- בתוך ה-expansion מוצגים:
  1. **רשת Intent Chips** — 12 כוונות עם emoji + שם (ראה רשימה מטה)
  2. **שדה keyword** — מולא מראש עם 3 המילים הראשונות של ההודעה
  3. **כפתור "שמור"** — מופעל רק כשגם intent וגם keyword נבחרו/הוזנו

**Intent Chips — 12 כוונות:**
```
📅 reminder   ✅ task       📈 stocks
🛒 shopping   💬 messaging  ⚽ sports
🌤 weather    📰 news       🌍 translate
🎵 music      📝 notes      🧠 memory
```

**לאחר שמירה:**
- שורה מסומנת כ-"טופלה": רקע ירוק עמום, טקסט ירוק, badge עם שם הכוונה
- הודעת Toast: `✓ "${keyword}" ← ${intent} — פעיל מיד`
- המונה בפיל מתעדכן
- הkeyword מופיע ב"Keywords שלי"

#### לשונית Keywords שלי

- רשימת כל ה-overrides שנוספו: `[intent badge] ← [keyword]` + כפתור מחיקה (×)
- כשהרשימה ריקה: הודעת placeholder "עדיין לא הוספת keywords"
- מחיקה קוראת ל-`DELETE /router/keywords`

### ApiService (`api_service.dart`) — 4 מתודות חדשות

```dart
Future<List<Map<String, dynamic>>> fetchRouterTrainingEvents()
Future<List<Map<String, dynamic>>> fetchRouterKeywords()
Future<bool> addRouterKeyword({ required String keyword, required String intent })
Future<bool> deleteRouterKeyword({ required String keyword, required String intent })
```

### State Management

ב-`tab_dev_workshop.dart`, מחלקת ה-State תשמור:
- `List<Map<String,dynamic>> _trainingEvents` — הודעות ברירת מחדל
- `List<Map<String,dynamic>> _keywords` — overrides קיימות
- `Set<String> _handled` — IDs של הודעות שטופלו (מקומי בלבד, לא נשלח לשרת)
- `int? _openRowIndex` — אינדקס השורה הפתוחה כרגע
- `bool _loading` — spinner ב-init

---

## זרימת עבודה טיפוסית

1. משתמש שולח "תשלח לאמא שאני בדרך" → Router נופל ל-`chat` → נרשם ב-`smart_telemetry_events`
2. משתמש פותח מרכז שליטה → סדנת פיתוח → רואה "1 פתוחות" ב-Router Trainer
3. לוחץ על השורה → בוחר chip 💬 `messaging` → keyword מולא "תשלח לאמא שאני"
4. לוחץ "שמור" → `POST /router/keywords` נשלח → קובץ overrides מתעדכן
5. בפנייה הבאה: "תשלח לאמא שלום" → `loadRouterOverrides()` מוצא substring "תשלח לאמא" → מנתב ל-`messaging`

---

## מה לא בסקופ

- **אין LLM לניבוי כוונה** — המשתמש בוחר ידנית
- **אין ייצוא/ייבוא** של overrides
- **אין עריכת keywords** — רק הוספה + מחיקה
- **אין priority** בין overrides (first-match)
- **אין regex** — substring בלבד
- **אין ניהול היסטוריה** — אירועים נשמרים בטבלה ולא נמחקים ידנית מ-UI זה

---

## בדיקות נדרשות

### Unit — router.js
- Override עם substring match (case-insensitive) נבחר לפני KEYWORDS
- Override לא קיים → KEYWORDS כרגיל
- קובץ overrides ריק → fallback ל-KEYWORDS
- אירוע `router_chat_default` נרשם כשמגיעים ל-default

### Unit — Flutter
- `fetchRouterTrainingEvents()` מפרסר תגובת JSON נכון
- `addRouterKeyword()` שולח POST עם body נכון
- שורה נשארת פתוחה עד שמירה (לא נסגרת בלחיצה על עצמה כשהיא כבר פתוחה)
- לחיצה על שורה אחרת סוגרת את הקודמת

### Integration — Server
- `POST /router/keywords` יוצר קובץ אם לא קיים
- `DELETE /router/keywords` מסיר רק את הרשומה הספציפית
- duplicate keyword לא מוסיף שורה כפולה
