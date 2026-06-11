'use strict';

const path = require('path');
const fs = require('fs');

const CUSTOM_REGISTRY_PATH = path.join(__dirname, '..', 'agents', 'custom', 'registry.json');
const STATUS_OVERRIDE_PATH = path.join(__dirname, '..', 'agents', 'custom', 'agent-status.json');

async function readStatusOverrides() {
  try {
    const raw = await fs.promises.readFile(STATUS_OVERRIDE_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (_) { return {}; }
}

async function writeStatusOverrides(map) {
  try {
    const dir = path.dirname(STATUS_OVERRIDE_PATH);
    await fs.promises.mkdir(dir, { recursive: true });
    const tmp = STATUS_OVERRIDE_PATH + '.tmp.' + process.pid;
    await fs.promises.writeFile(tmp, JSON.stringify(map, null, 2), 'utf8');
    await fs.promises.rename(tmp, STATUS_OVERRIDE_PATH); // atomic on POSIX — prevents partial-read corruption
    return true;
  } catch (e) { return false; }
}

// Core agents whose dispatch path the whole app depends on — never disablable.
const PROTECTED_AGENT_IDS = ['router', 'chatAgent'];

function isProtectedAgent(agentId) {
  return PROTECTED_AGENT_IDS.includes(agentId);
}

async function setAgentStatus(agentId, status) {
  if (!agentId) throw new Error('agentId required');
  if (!['active', 'disabled'].includes(status)) throw new Error('status must be active|disabled');
  if (status === 'disabled' && isProtectedAgent(agentId)) {
    throw new Error('סוכן ליבה — לא ניתן לכיבוי');
  }
  const overrides = await readStatusOverrides();
  const prev = overrides[agentId] || {};
  overrides[agentId] = { ...prev, status, updatedAt: new Date().toISOString() };
  if (!await writeStatusOverrides(overrides)) throw new Error('failed to persist status override');
  return overrides[agentId];
}

async function setAgentRisk(agentId, riskLevel) {
  if (!agentId) throw new Error('agentId required');
  if (!['low', 'medium', 'high'].includes(riskLevel)) throw new Error('riskLevel must be low|medium|high');
  const overrides = await readStatusOverrides();
  const prev = overrides[agentId] || {};
  overrides[agentId] = { ...prev, riskLevel, updatedAt: new Date().toISOString() };
  if (!await writeStatusOverrides(overrides)) throw new Error('failed to persist risk override');
  return overrides[agentId];
}

const STATIC_AGENTS = [
  {
    id: 'router',
    name: 'Router',
    nameHe: 'ראוטר',
    role: 'מסווג כוונות',
    mission: 'מנתח כל הודעת משתמש ומכוון אותה לסוכן הנכון. משתמש בהתאמת מילות מפתח (regex) ואם אין התאמה — קורא ל-LLM. מחזיר מחרוזת intent אחת מתוך ~20 אפשרויות.',
    prompt: 'אתה מסווג כוונות. קבל הודעה בעברית/אנגלית וסווג אותה לאחד מה-intents הבאים: task, reminder, memory, chat, weather, news, shopping, notes, stocks, translate, music, sports, messaging, draft, insight, security, code_error, e2e, factory, past_conv.',
    responsibilities: ['סיווג intent בלבד', 'fallback ל-LLM לקצרים מ-12 תווים', 'תמיד מחזיר intent תקין'],
    inputs: ['הודעת משתמש (string)'],
    outputs: ['intent string'],
    tools: ['regex keyword matching', 'Groq llama-3.3-70b-versatile (fallback)'],
    permissions: ['קריאה בלבד'],
    memoryAccess: 'אין',
    restrictions: ['לא שומר כלום', 'לא מחזיר תשובה למשתמש'],
    risk: 'medium', mode: 'guard', approval: 'none', autonomy: 70, status: 'active',
    connections: [
      { agentId: 'chatAgent', name: 'Chat Agent', nameHe: 'סוכן שיחה', direction: 'outgoing', type: 'dispatch', payload: 'intent=chat', trigger: 'כל הודעה', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'taskAgent', name: 'Task Agent', nameHe: 'סוכן משימות', direction: 'outgoing', type: 'dispatch', payload: 'intent=task', trigger: 'כל הודעה', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'reminderAgent', name: 'Reminder Agent', nameHe: 'סוכן תזכורות', direction: 'outgoing', type: 'dispatch', payload: 'intent=reminder', trigger: 'כל הודעה', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'memoryAgent', name: 'Memory Agent', nameHe: 'סוכן זיכרון', direction: 'outgoing', type: 'dispatch', payload: 'intent=memory', trigger: 'כל הודעה', risk: 'low', requiresApproval: false, confidence: 'inferred' },
    ],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'chatAgent',
    name: 'Chat Agent',
    nameHe: 'סוכן שיחה',
    role: 'עוזר שיחה ראשי',
    mission: 'הסוכן הראשי לשיחות חופשיות. בונה פרומפט מערכת עשיר הכולל אישיות, מגדר, זיכרונות, היסטוריה ותאריך/שעה. תומך ב-voiceMode (תשובות קצרות ללא markdown).',
    prompt: 'אתה ג׳רביס, עוזר אישי חכם בעברית. אישיות: [personality]. מגדר: [gender]. זיכרונות: [memories]. היסטוריה: [history]. ענה בעברית טבעית ואישית.',
    responsibilities: ['שיחה חופשית בעברית', 'הטמעת זיכרונות והיסטוריה', 'תמיכה ב-voiceMode'],
    inputs: ['הודעת משתמש', 'היסטוריה (20 הודעות אחרונות)', 'זיכרונות אישיים', 'settings (personality, gender, voiceMode)'],
    outputs: ['תשובה טקסטואלית', 'audio TTS (base64)'],
    tools: ['callGemma4 / callGeminiVision (אם יש תמונה)', 'Google TTS'],
    permissions: ['קריאת היסטוריה מ-Supabase', 'קריאת זיכרונות'],
    memoryAccess: 'קריאה (+ autoExtractMemory כתיבה בסוף כל פנייה)',
    restrictions: ['לא מבצע פעולות חיצוניות ישירות'],
    risk: 'medium', mode: 'assistant', approval: 'none', autonomy: 40, status: 'active',
    connections: [
      { agentId: 'memoryAgent', name: 'Memory Agent', nameHe: 'סוכן זיכרון', direction: 'outgoing', type: 'חילוץ זיכרון אוטומטי', payload: 'הודעה + תשובה → עובדות אישיות', trigger: 'אוטומטית אחרי כל שיחה', risk: 'low', requiresApproval: false, confidence: 'inferred' },
    ],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'taskAgent',
    name: 'Task Agent',
    nameHe: 'סוכן משימות',
    role: 'ניהול משימות',
    mission: 'יוצר, מעדכן, מסמן כסיים ומוחק משימות ב-Supabase. מזהה תאריכי יעד מטקסט עברי חופשי. מחזיר action object לאפליקציה.',
    prompt: 'נהל את רשימת המשימות של המשתמש. הבן בקשות בעברית חופשית (הוסף, מחק, סמן כסיים, עדכן).',
    responsibilities: ['יצירת משימות', 'עדכון משימות קיימות', 'סימון כסיים / מחיקה'],
    inputs: ['הודעת משתמש', 'רשימת משימות קיימות מ-Supabase'],
    outputs: ['{ answer, action: { type: "task_created"|"task_updated"|"task_deleted", ... } }'],
    tools: ['Supabase tasks table', 'callGemma4'],
    permissions: ['קריאה/כתיבה/מחיקה ב-tasks'],
    memoryAccess: 'אין',
    restrictions: ['לא שולח הודעות חיצוניות'],
    risk: 'medium', mode: 'operator', approval: 'medium', autonomy: 50, status: 'active',
    connections: [
      { agentId: 'insightAgent', name: 'Insight Agent', nameHe: 'סוכן תובנות', direction: 'incoming', type: 'קריאת נתונים', payload: 'tasks table', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
    ],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'reminderAgent',
    name: 'Reminder Agent',
    nameHe: 'סוכן תזכורות',
    role: 'ניהול תזכורות',
    mission: 'יוצר, מעדכן ומוחק תזכורות ב-Supabase עם תמיכה ב-cron חוזר. ה-cron ב-server.js מפעיל תזכורות שמגיע זמנן כל דקה.',
    prompt: 'נהל תזכורות. הבן תאריכים ושעות מעברית. תמוך ב"כל יום", "כל שבוע", תזכורות חוזרות.',
    responsibilities: ['יצירת תזכורות עם scheduled_time', 'תמיכה ב-recurrence', 'מחיקה/עדכון'],
    inputs: ['הודעת משתמש', 'תזכורות קיימות'],
    outputs: ['{ answer, action: { type: "reminder_set", ... } }'],
    tools: ['Supabase reminders table', 'callGemma4'],
    permissions: ['קריאה/כתיבה/מחיקה ב-reminders'],
    memoryAccess: 'אין',
    restrictions: ['לא שולח push notifications ישירות — הcron עושה זאת'],
    risk: 'medium', mode: 'operator', approval: 'medium', autonomy: 50, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'memoryAgent',
    name: 'Memory Agent',
    nameHe: 'סוכן זיכרון',
    role: 'שמירת ואחזור זיכרונות אישיים',
    mission: 'שומר, מאחזר ומוחק עובדות אישיות על המשתמש. כולל autoExtractMemory — חילוץ פסיבי לאחר כל שיחה. תומך גם ב-Pinecone לחיפוש סמנטי.',
    prompt: 'שמור ואחזר מידע אישי. חלץ עובדות אישיות מטקסט שיחה. חיפוש בזיכרון.',
    responsibilities: ['שמירת זיכרונות ל-Supabase', 'חיפוש סמנטי ב-Pinecone (optional)', 'autoExtractMemory passively'],
    inputs: ['הודעת משתמש', 'היסטוריית שיחה (עבור auto-extract)'],
    outputs: ['{ answer, action: { type: "memory_saved"|"memory_recalled"|"memory_deleted", ... } }'],
    tools: ['Supabase memories table', 'Pinecone (optional)', 'callGemma4'],
    permissions: ['קריאה/כתיבה/מחיקה ב-memories', 'Pinecone upsert/query (אם מוגדר)'],
    memoryAccess: 'קריאה + כתיבה מלאה',
    restrictions: [],
    risk: 'medium', mode: 'operator', approval: 'medium', autonomy: 40, status: 'active',
    connections: [
      { agentId: 'chatAgent', name: 'Chat Agent', nameHe: 'סוכן שיחה', direction: 'incoming', type: 'autoExtractMemory', payload: 'שיחה → עובדות', trigger: 'אחרי כל chat turn', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'insightAgent', name: 'Insight Agent', nameHe: 'סוכן תובנות', direction: 'incoming', type: 'קריאת זיכרונות', payload: 'memories table', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
    ],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'weatherAgent',
    name: 'Weather Agent',
    nameHe: 'סוכן מזג אוויר',
    role: 'מידע מזג אוויר',
    mission: 'מושך נתוני מזג אוויר עם Google Search grounding דרך Gemini. מחזיר תחזית קצרה בעברית.',
    prompt: 'ספק מידע על מזג אוויר נוכחי ותחזית. השתמש בנתונים עדכניים.',
    responsibilities: ['תחזית מזג אוויר', 'טמפרטורה ותנאים נוכחיים'],
    inputs: ['הודעת משתמש (מיקום, זמן)'],
    outputs: ['תשובה טקסטואלית'],
    tools: ['callGeminiWithSearch (Google Search grounding)'],
    permissions: ['גישת רשת לחיפוש'],
    memoryAccess: 'אין',
    restrictions: ['לא שומר מידע', 'תוצאות חיפוש בלבד'],
    risk: 'low', mode: 'observer', approval: 'none', autonomy: 20, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'newsAgent',
    name: 'News Agent',
    nameHe: 'סוכן חדשות',
    role: 'חדשות עדכניות',
    mission: 'מחפש חדשות עדכניות עם Google Search grounding. מחזיר תקציר קצר של ידיעות רלוונטיות.',
    prompt: 'ספק חדשות עדכניות על הנושא המבוקש. השתמש במקורות אמינים.',
    responsibilities: ['חיפוש חדשות', 'תקציר ידיעות'],
    inputs: ['הודעת משתמש (נושא)'],
    outputs: ['תשובה טקסטואלית עם ידיעות'],
    tools: ['callGeminiWithSearch'],
    permissions: ['גישת רשת'],
    memoryAccess: 'אין',
    restrictions: ['לא שומר מידע'],
    risk: 'low', mode: 'observer', approval: 'none', autonomy: 20, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'stocksAgent',
    name: 'Stocks Agent',
    nameHe: 'סוכן מניות',
    role: 'מידע פיננסי',
    mission: 'מחזיר מחירי מניות ונתוני שוק עם Google Search grounding.',
    prompt: 'ספק מידע על מניות, מדדים וכלכלה. נתונים עדכניים בלבד.',
    responsibilities: ['מחירי מניות', 'נתוני מדדים'],
    inputs: ['שם מניה / סימול'],
    outputs: ['תשובה עם מחיר ונתונים'],
    tools: ['callGeminiWithSearch'],
    permissions: ['גישת רשת'],
    memoryAccess: 'אין',
    restrictions: ['לא שומר מידע', 'אינו ייעוץ פיננסי'],
    risk: 'low', mode: 'observer', approval: 'none', autonomy: 20, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'translationAgent',
    name: 'Translation Agent',
    nameHe: 'סוכן תרגום',
    role: 'תרגום טקסט',
    mission: 'מתרגם טקסטים בין שפות שונות. מזהה שפת מקור אוטומטית.',
    prompt: 'תרגם את הטקסט הבא. זהה שפת מקור אוטומטית ותרגם לשפה המבוקשת.',
    responsibilities: ['תרגום בין שפות', 'זיהוי שפת מקור'],
    inputs: ['טקסט לתרגום', 'שפת יעד'],
    outputs: ['טקסט מתורגם'],
    tools: ['callGemma4'],
    permissions: [],
    memoryAccess: 'אין',
    restrictions: [],
    risk: 'low', mode: 'observer', approval: 'none', autonomy: 20, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'sportsAgent',
    name: 'Sports Agent',
    nameHe: 'סוכן ספורט',
    role: 'מידע ספורט',
    mission: 'תוצאות משחקים, טבלאות ליגות, מידע ספורטיבי עדכני עם Google Search.',
    prompt: 'ספק מידע ספורטיבי עדכני: תוצאות, טבלאות, עונות.',
    responsibilities: ['תוצאות משחקים', 'טבלאות ליגות', 'מידע שחקנים'],
    inputs: ['שאלה ספורטיבית'],
    outputs: ['תשובה עם נתונים'],
    tools: ['callGeminiWithSearch'],
    permissions: ['גישת רשת'],
    memoryAccess: 'אין',
    restrictions: ['לא שומר מידע'],
    risk: 'low', mode: 'observer', approval: 'none', autonomy: 20, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'shoppingAgent',
    name: 'Shopping Agent',
    nameHe: 'סוכן קניות',
    role: 'ניהול רשימת קניות',
    mission: 'מנהל רשימת קניות ב-Supabase. מוסיף, מסיר ומציג פריטים.',
    prompt: 'נהל את רשימת הקניות. הוסף, הסר, הצג פריטים.',
    responsibilities: ['הוספת פריטים', 'הסרת פריטים', 'הצגת הרשימה'],
    inputs: ['הודעת משתמש'],
    outputs: ['{ answer, action: { type: "shopping_added"|"shopping_removed", ... } }'],
    tools: ['Supabase shopping_items table', 'callGemma4'],
    permissions: ['קריאה/כתיבה ב-shopping_items'],
    memoryAccess: 'אין',
    restrictions: [],
    risk: 'low', mode: 'operator', approval: 'none', autonomy: 40, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'notesAgent',
    name: 'Notes Agent',
    nameHe: 'סוכן פתקים',
    role: 'ניהול פתקים',
    mission: 'יוצר ומנהל פתקים ב-Supabase ובקובץ notes.json מקומי. תומך ב-Obsidian sync.',
    prompt: 'נהל פתקים: צור, ערוך, הצג, מחק.',
    responsibilities: ['יצירת פתקים', 'עריכה/מחיקה', 'Obsidian sync'],
    inputs: ['הודעת משתמש'],
    outputs: ['{ answer, action }'],
    tools: ['Supabase notes', 'notes.json', 'obsidianSync'],
    permissions: ['קריאה/כתיבה ב-notes', 'גישה למערכת קבצים (notes.json, Obsidian)'],
    memoryAccess: 'אין',
    restrictions: [],
    risk: 'low', mode: 'operator', approval: 'none', autonomy: 40, status: 'active',
    connections: [
      { agentId: 'insightAgent', name: 'Insight Agent', nameHe: 'סוכן תובנות', direction: 'incoming', type: 'קריאת פתקים', payload: 'notes table', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
    ],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'musicAgent',
    name: 'Music Agent',
    nameHe: 'סוכן מוזיקה',
    role: 'שליטה במוזיקה',
    mission: 'שולט בנגן מוזיקה (Spotify / YouTube). מנגן, עוצר, דלג, התאם עוצמת קול.',
    prompt: 'שלוט במוזיקה: נגן, עצור, דלג, הגבר/הנמך.',
    responsibilities: ['ניגון שירים', 'שליטה בנגן', 'playlist'],
    inputs: ['פקודת מוזיקה'],
    outputs: ['{ answer, action: { type: "music_play"|"music_stop"|"music_skip", ... } }'],
    tools: ['Spotify API / YouTube (דרך action)'],
    permissions: ['שליטה בנגן מוזיקה'],
    memoryAccess: 'אין',
    restrictions: ['תלוי בהגדרת Spotify בצד הלקוח'],
    risk: 'medium', mode: 'operator', approval: 'none', autonomy: 40, status: 'active',
    connections: [
      { agentId: 'insightAgent', name: 'Insight Agent', nameHe: 'סוכן תובנות', direction: 'incoming', type: 'קריאת נתוני מוזיקה', payload: 'music preferences', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
    ],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'messagingAgent',
    name: 'Messaging Agent',
    nameHe: 'סוכן הודעות',
    role: 'שליחת הודעות',
    mission: 'שולח הודעות WhatsApp, אימייל ו-SMS דרך action objects. ניגש לטבלת contacts ב-Supabase.',
    prompt: 'שלח הודעות ל[איש קשר]. צור action לשליחה דרך WhatsApp/אימייל/SMS.',
    responsibilities: ['שליחת WhatsApp', 'שליחת אימייל', 'ניהול אנשי קשר'],
    inputs: ['הודעת משתמש', 'contacts table'],
    outputs: ['{ answer, action: { type: "send_whatsapp"|"send_email", ... } }'],
    tools: ['Supabase contacts', 'Gmail API', 'WhatsApp deep link'],
    permissions: ['קריאת contacts', 'גישה ל-Gmail', 'שליחת הודעות'],
    memoryAccess: 'אין',
    restrictions: ['דורש אישור משתמש לשליחה'],
    risk: 'high', mode: 'operator', approval: 'high', autonomy: 30, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'draftAgent',
    name: 'Draft Agent',
    nameHe: 'סוכן טיוטות',
    role: 'כתיבת טיוטות',
    mission: 'כותב טיוטות אימייל, מסמכים, הודעות. מחזיר טקסט לעריכה לפני שליחה.',
    prompt: 'כתוב טיוטה ל[סוג מסמך]: [נושא]. כתב מקצועי/פורמלי/חברי לפי הבקשה.',
    responsibilities: ['כתיבת אימיילים', 'כתיבת הודעות', 'עיצוב מסמכים'],
    inputs: ['בקשת טיוטה + הקשר'],
    outputs: ['טיוטה מוכנה לעריכה'],
    tools: ['callGemma4'],
    permissions: [],
    memoryAccess: 'אין',
    restrictions: ['לא שולח בעצמו — מחזיר טיוטה בלבד'],
    risk: 'medium', mode: 'assistant', approval: 'none', autonomy: 40, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'insightAgent',
    name: 'Insight Agent',
    nameHe: 'סוכן תובנות',
    role: 'ניתוח נתונים אישיים',
    mission: 'מנתח נתוני משתמש מ-Supabase (משימות, תזכורות, זיכרונות, פתקים) ומחזיר תובנות ודפוסים.',
    prompt: 'נתח את הנתונים האישיים ותן תובנות. מה הדפוסים? מה מצב המשימות?',
    responsibilities: ['ניתוח דפוסים', 'סיכום פעילות', 'המלצות שיפור'],
    inputs: ['נתונים מ-Supabase: tasks, reminders, memories, notes, music'],
    outputs: ['תובנות ודפוסים בעברית'],
    tools: ['Supabase (multiple tables)', 'callGemma4'],
    permissions: ['קריאה מ-tasks, reminders, memories, notes, shopping_items'],
    memoryAccess: 'קריאה בלבד',
    restrictions: ['לא כותב ל-DB', 'תובנות בלבד'],
    risk: 'medium', mode: 'assistant', approval: 'none', autonomy: 30, status: 'active',
    connections: [
      { agentId: 'taskAgent', name: 'Task Agent', nameHe: 'סוכן משימות', direction: 'outgoing', type: 'קריאת נתונים', payload: 'tasks table', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'reminderAgent', name: 'Reminder Agent', nameHe: 'סוכן תזכורות', direction: 'outgoing', type: 'קריאת נתונים', payload: 'reminders table', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'memoryAgent', name: 'Memory Agent', nameHe: 'סוכן זיכרון', direction: 'outgoing', type: 'קריאת זיכרונות', payload: 'memories table', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'notesAgent', name: 'Notes Agent', nameHe: 'סוכן פתקים', direction: 'outgoing', type: 'קריאת פתקים', payload: 'notes table', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
      { agentId: 'musicAgent', name: 'Music Agent', nameHe: 'סוכן מוזיקה', direction: 'outgoing', type: 'קריאת העדפות', payload: 'music data', trigger: 'כשנבקש insight', risk: 'low', requiresApproval: false, confidence: 'inferred' },
    ],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'securityAgent',
    name: 'Security Agent',
    nameHe: 'סוכן אבטחה',
    role: 'סריקת אבטחה',
    mission: 'סורק קוד מקור של הפרויקט לאיתור חולשות אבטחה. שומר ממצאים ב-e2e_reports ב-Supabase.',
    prompt: 'סרוק את קבצי הקוד הבאים לחולשות אבטחה. זהה: SQL injection, XSS, סודות חשופים, הרשאות שגויות.',
    responsibilities: ['סריקת קוד לחולשות', 'שמירת דוחות', 'המלצות תיקון'],
    inputs: ['קבצי קוד מקור'],
    outputs: ['דוח אבטחה ב-Supabase + תשובה'],
    tools: ['fs (קריאת קבצים)', 'Supabase e2e_reports', 'callGemma4'],
    permissions: ['קריאת מערכת קבצים', 'כתיבה ל-e2e_reports'],
    memoryAccess: 'אין',
    restrictions: ['פועל ב-background (setImmediate)', 'לא מבצע שינויים בקוד'],
    risk: 'high', mode: 'guard', approval: 'high', autonomy: 20, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'codeErrorAgent',
    name: 'Code Error Agent',
    nameHe: 'סוכן שגיאות קוד',
    role: 'ניפוי שגיאות קוד',
    mission: 'מזהה, מסביר ומציע תיקונים לשגיאות קוד. סורק logs ו-stack traces.',
    prompt: 'נתח את השגיאה הבאה: [error]. הסבר את הגורם ותצע תיקון.',
    responsibilities: ['זיהוי שגיאות', 'הסבר stack trace', 'הצעת תיקונים'],
    inputs: ['שגיאה / stack trace / קוד'],
    outputs: ['הסבר + הצעת תיקון + דוח ב-Supabase'],
    tools: ['callGemma4', 'Supabase e2e_reports'],
    permissions: ['קריאת קבצים', 'כתיבה ל-e2e_reports'],
    memoryAccess: 'אין',
    restrictions: ['פועל ב-background', 'לא משנה קוד ישירות'],
    risk: 'high', mode: 'guard', approval: 'high', autonomy: 20, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
  {
    id: 'e2eAgent',
    name: 'E2E Agent',
    nameHe: 'סוכן בדיקות',
    role: 'בדיקות end-to-end',
    mission: 'מריץ בדיקות E2E על כל הסוכנים. בודק שכל endpoint מחזיר תשובה תקינה. שומר דוחות ב-Supabase.',
    prompt: 'הרץ בדיקות E2E. בדוק כל endpoint. שמור ממצאים.',
    responsibilities: ['הרצת בדיקות', 'בדיקת endpoints', 'דוחות ב-Supabase'],
    inputs: ['פקודת הפעלה'],
    outputs: ['דוח בדיקות מפורט ב-Supabase + תשובה'],
    tools: ['HTTP client (בדיקת endpoints)', 'Supabase e2e_reports', 'callGemma4'],
    permissions: ['גישת רשת לכל endpoints', 'כתיבה ל-e2e_reports'],
    memoryAccess: 'אין',
    restrictions: ['פועל ב-background', 'לא מבצע שינויים'],
    risk: 'high', mode: 'guard', approval: 'high', autonomy: 10, status: 'active',
    connections: [],
    dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
  },
];

async function getAgentRegistry() {
  const overrides = await readStatusOverrides();
  const applyOverride = (agent) => {
    const ov = overrides[agent.id];
    if (!ov) return agent;
    const next = { ...agent };
    if (ov.status === 'active' || ov.status === 'disabled') {
      next.status = ov.status;
      next.statusUpdatedAt = ov.updatedAt;
    }
    if (['low', 'medium', 'high'].includes(ov.riskLevel)) {
      next.risk = ov.riskLevel;
    }
    return next;
  };
  const agents = STATIC_AGENTS.map(applyOverride);
  try {
    const raw = await fs.promises.readFile(CUSTOM_REGISTRY_PATH, 'utf8');
    {
      const custom = JSON.parse(raw);
      if (Array.isArray(custom)) {
        custom.forEach(c => {
          const id = c.id || c.name;
          const baseStatus = 'custom';
          const ov = overrides[id];
          agents.push({
          id,
          name: c.name || c.id,
          nameHe: c.nameHe || c.name || c.id,
          role: c.role || 'סוכן מותאם',
          mission: c.description || c.mission || '',
          prompt: c.prompt || '',
          responsibilities: c.responsibilities || [],
          inputs: c.inputs || [],
          outputs: c.outputs || [],
          tools: c.tools || [],
          permissions: c.permissions || [],
          memoryAccess: c.memoryAccess || 'אין',
          restrictions: c.restrictions || [],
          risk: c.risk || 'medium',
          mode: c.mode || 'assistant',
          approval: c.approval || 'none',
          autonomy: c.autonomy || 40,
          status: (ov && (ov.status === 'active' || ov.status === 'disabled')) ? ov.status : baseStatus,
          statusUpdatedAt: ov ? ov.updatedAt : undefined,
          ...(ov && ['low', 'medium', 'high'].includes(ov.riskLevel) ? { risk: ov.riskLevel } : {}),
          connections: c.connections || [],
          dashboard: { tasksHandled: 'unknown', failures: 'unknown', avgLatency: 'unknown', confidence: 'unknown', lastActive: 'unknown' },
          });
        });
      }
    }
  } catch (_) {}
  return agents;
}

// Save a free-text customization note for an agent (up to 10 kept per agent).
async function saveAgentCustomization(agentId, text) {
  if (!agentId || !text) return false;
  const overrides = await readStatusOverrides();
  if (!overrides[agentId]) overrides[agentId] = {};
  if (!Array.isArray(overrides[agentId].customizations)) overrides[agentId].customizations = [];
  overrides[agentId].customizations.push({ text, at: new Date().toISOString() });
  if (overrides[agentId].customizations.length > 10) overrides[agentId].customizations.shift();
  return writeStatusOverrides(overrides);
}

// Return saved customizations for one agent.
async function getAgentCustomizations(agentId) {
  const overrides = await readStatusOverrides();
  return overrides[agentId]?.customizations || [];
}

module.exports = {
  getAgentRegistry,
  setAgentStatus,
  setAgentRisk,
  isProtectedAgent,
  PROTECTED_AGENT_IDS,
  saveAgentCustomization,
  getAgentCustomizations,
};
