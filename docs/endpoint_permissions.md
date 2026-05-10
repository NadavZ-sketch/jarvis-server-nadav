# Endpoint Permissions Matrix

הטבלה מגדירה מי מורשה לקרוא/לכתוב לכל endpoint מרכזי בשרת.

| Endpoint | Method | Anonymous/Public | Authenticated User | Internal Server (service role) | Notes |
|---|---|---:|---:|---:|---|
| `/health` | GET | ✅ Read | ✅ Read | ✅ Read | Health check בלבד |
| `/ask-jarvis` | POST | ⚠️ Limited | ✅ Write (chat request) | ✅ Write | מומלץ לדרוש JWT לפני פרודקשן |
| `/stream-jarvis` | POST | ⚠️ Limited | ✅ Write | ✅ Write | כמו ask-jarvis |
| `/chat-history` | GET | ❌ | ✅ Read own | ✅ Read all | חייב סינון לפי `user_id` |
| `/chat-history` | DELETE | ❌ | ✅ Delete own | ✅ Delete all | חובה אימות משתמש |
| `/memories` | GET | ❌ | ✅ Read own | ✅ Read all | RLS לפי user |
| `/memories` | POST/PUT/DELETE | ❌ | ✅ Write own | ✅ Write all | RLS לפי user |
| `/reminders` | GET | ❌ | ✅ Read own | ✅ Read all | RLS לפי user |
| `/reminders` | POST/PUT/DELETE | ❌ | ✅ Write own | ✅ Write all | RLS לפי user |
| `/tasks` | GET/POST/PUT/DELETE | ❌ | ✅ Own only | ✅ All | אם נשמר ב-DB -> RLS |
| `/notes` | GET/POST/PUT/DELETE | ❌ | ✅ Own only | ✅ All | אם נשמר ב-DB -> RLS |
| `/contacts` | GET/POST/PUT/DELETE | ❌ | ✅ Own only | ✅ All | מידע רגיש |
| `/shopping` | GET/POST/PUT/DELETE | ❌ | ✅ Own only | ✅ All | מידע אישי |
| `/send-email` | POST | ❌ | ⚠️ Sensitive action | ✅ Allowed | נדרש אישור מפורש לפני שליחה |
| `/admin/*` (אם קיים) | Any | ❌ | ❌ | ✅ Only | לגישה פנימית בלבד |

## Security Rules

1. **Service role key** נשאר רק בשרת (`SUPABASE_SERVICE_ROLE_KEY`) ולעולם לא נשלח ל-client/mobile.
2. אפליקציית מובייל/ווב מקבלת לכל היותר **anon key** (`SUPABASE_ANON_KEY`) + JWT של המשתמש.
3. כל טבלה אישית חייבת `user_id` + RLS פעיל.
4. פעולות רגישות (email, מחיקה) דורשות אימות + אישור משתמש.
