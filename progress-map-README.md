# Progress Map Source of Truth

Source of truth יחיד ל-Progress Map הוא השרת:

- `PROGRESS_MAP_CONFIG` בתוך `server.js` עבור ערכי `status` / `priority` ו-labels.
- `progress_map_schema.json` עבור מבנה הנתונים הרשמי של payload ללקוחות.
- endpoint קונפיגורציה: `GET /dashboard/backlog/config`.
- endpoint סכימה: `GET /dashboard/backlog/schema`.

כל לקוח (Web + Mobile) צריך להשתמש בשדות בדיוק כפי שהשרת מחזיר ב-`GET /dashboard/backlog`, ללא המרות ad-hoc של שמות שדות.
