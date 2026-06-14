# Home + Today Merge — Design Spec
**תאריך:** 2026-06-14  
**סקופ:** Flutter mobile — מסך בית + Today Tab

---

## סיכום

מאחדים את Today Tab (sub-tab בתוך מסך "משימות") לתוך מסך הבית.
מטרה: ביטול כפילות data, פחות friction, מסך בית עשיר יותר.

---

## מה נמחק

- `today_tab.dart` — נמחק לחלוטין
- Sub-tab "היום" מ-`productivity_screen.dart` — מוסר
- Productivity screen פותח ישירות ב-index 0 (משימות), 3 sub-tabs נשארים: משימות / תזכורות / לוח שנה

---

## מה משתנה ב-Home Screen

### סדר כרטיסים — ברירת מחדל חדשה (`kHomeCards`)

```
hero          ← ברכה + briefing (מורחב)
week_strip    ← NEW
day_focus     ← NEW (מחליף jarvis)
quick_actions
tasks
reminders
weather_news
```

`kLegacyCardIds` מתעדכן: `'jarvis' → 'day_focus'` — שדרוג שקוף למשתמשים עם סדר שמור.

---

## כרטיסים חדשים

### 1. WeekStripCard (`id: 'week_strip'`)

כרטיס רגיל ב-`kHomeCards` — ניתן לסדר ולהסתיר.  
מציג את רצועת השבוע הקיימת (`WeekStripWidget`) עם DayMeta (tasks / reminders / overdue לכל יום).  
לחיצה על יום שאינו היום — ניווט ל-Calendar tab.  
גובה קבוע: compact.

**Data:** `HomeController.weekData` — נטען ב-`_loadSecondary()`, non-blocking.

### 2. DayFocusCard (`id: 'day_focus'`, מחליף `jarvis`)

כרטיס דו-שכבתי, גובה ~110px:

**שכבה עליונה — AI Rank Row:**
```
⚡ "קדם ראשון: [שם משימה] — [סיבה 5-8 מילים]"
```
- מוסתר לחלוטין אם אין data (לא placeholder)
- fade in כשמגיע data
- cache 8h (SharedPreferences)
- טעינה: `POST /ask-jarvis` עם prompt: tasks+reminders → TOP 1 + סיבה קצרה

**שכבה תחתונה — Day Timeline:**
```
○────●──────────────○──────○
08:00  עכשיו       16:00  19:30
```
- ציר אופקי RTL, 3 זונות: בוקר / צהריים / ערב
- עיגול = task, פעמון קטן = reminder
- `▶` / `●` = מיקום נוכחי (now)
- tap על נקודה → snackbar עם שם הפריט
- חישוב מקומי מ-`HomeController.tasks` + `HomeController.reminders`, ללא LLM

**אנימציה:**
- pulse עדין פעם אחת בטעינה (opacity 0.6→1.0, 600ms)
- dot נוכחי: pulse חוזר איטי (scale 1.0→1.15, 2s, repeat)

---

## שינויים ב-HeroCard

- **שעון:** מסיר לחלוטין. `Timer.periodic` נמחק. HeroCard מציג ברכה + תאריך בלבד.
- **Briefing section:** מוסף מתחת לברכה, מתכווץ/מתרחב.
  - `AnimatedSize` (חלק יותר מ-`AnimatedCrossFade`)
  - מורחב כברירת מחדל אם יש תוכן, מכווץ אם ריק
  - כפתור refresh קטן בפינה
  - cache 20h (SharedPreferences), מפתח: `today_briefing_v2::{focus}`

---

## שינויים ב-HomeController

```dart
// שדות חדשים
List<Map<String,dynamic>> weekData = [];
String? briefing;
bool briefingLoading = false;
String? aiRank;
bool aiRankLoading = false;

// _loadSecondary() מתרחב
void _loadSecondary() {
  _loadDashboardContext();  // קיים
  _loadWeekData();          // מ-TodayTab
  _loadBriefingCache();     // מ-TodayTab, cache 20h
  _loadAiRankCache();       // חדש, cache 8h
}
```

`_loadWeekData()` ו-`_loadBriefingCache()` מועברים מ-`TodayTab._TodayTabState` — לוגיקה זהה, מועברת ל-controller.

`_loadAiRankCache()`:
1. בודק SharedPreferences — אם cache תקף (< 8h) משתמש בו
2. אחרת: `POST /ask-jarvis` עם prompt מובנה, שומר result

---

## אנימציות

| אירוע | אנימציה |
|---|---|
| טעינה ראשונית | stagger: כל כרטיס — delay 80ms×index, fade+slide 12px מלמטה |
| השלמת משימה | checkbox: scale spring (1.0→1.3→1.0, 300ms, ירוק) → שורה: slide+fade out אחרי 350ms |
| DayFocusCard | pulse פעם אחת (opacity 0.6→1.0, 600ms) |
| AI Row | fade in כשמגיע data |
| Dot נוכחי (▶) | pulse חוזר (scale 1.0→1.15, 2s, repeat) |
| WeekStrip בחירה | dot: scale 1.0→1.35 + color transition, 200ms |
| Load chip | AnimatedColor בשינוי סטטוס (light=ירוק, heavy=אדום) |

**Stagger:** עטוף ב-`AnimationController` per card, מבוסס index ב-`kHomeCards` — אוטומטי לכל כרטיס עתידי.

---

## Data Flow

```
HomeController.load()  [initial, parallel]
  ├── api.getTasks()
  ├── api.getReminders()
  └── api.getTodayMessage()
        ↓ notifyListeners()
  _loadSecondary()  [non-blocking fan-out]
  ├── _loadDashboardContext()   [15min gate]
  ├── _loadWeekData()           [calendar API]
  ├── _loadBriefingCache()      [cache 20h → /ask-jarvis fallback]
  └── _loadAiRankCache()        [cache 8h → /ask-jarvis fallback]
```

שגיאה בכל secondary load: silent — מסתיר את הרכיב, לא שובר את המסך.

---

## Error Handling

- `weekData` fail → WeekStripCard מציג empty state שקט (אין dots)
- `briefing` fail → HeroCard מסתיר briefing section
- `aiRank` fail → DayFocusCard מסתיר AI row, מציג רק timeline
- `aiRank` load איטי → AI row מוסתר עד שמגיע (לא spinner)

---

## Testing

- `HomeController` unit tests: `loadAiRankCache` — cache hit / cache miss / fail
- `DayFocusCard` widget test: renders timeline מ-tasks+reminders, AI row hidden כשאין data
- `WeekStripCard` widget test: מציג DayMeta נכון
- `HeroCard` widget test: briefing section מתרחב/מתכווץ, ללא Timer.periodic
- Integration: Productivity screen נפתח ב-משימות (index 0), אין sub-tab "היום"

---

## מה לא בסקופ

- מבנה overdue/focus-top-3 ב-TasksCard — שלב נפרד
- שינויים ב-RemindersCard, WeatherNewsCard, QuickActionsCard
- שינויים ב-web dashboard
