// Keyword-based fast routing — no API call needed
// ORDER MATTERS: reminder must be before memory to avoid תזכיר לי conflict
const fs   = require('fs');
const path = require('path');
const axios = require('axios');

const KEYWORDS = {
    past_conv: /מה דיברנו|בפעם הקודמת|מה אמרת לי|תזכיר לי מה.*אמרת|שוחחנו על|מה שאמרת/i,
    task:      /משימ|הוסף משימ|מחק משימ|רשימת משימ|הראה משימ|כל המשימ|סיימתי|סמן כבוצע|השלמתי|תסווג|סווג מחדש|לקטגורי/i,
    reminder:  /תזכיר לי|הזכר לי|תזכורת|להזכיר לי|הצג תזכורות|מחק תזכורת|בטל תזכורת|כל התזכורות|רשימת תזכורות/i,
    memory:    /זכור ש|תזכור ש|שמור ש|מה אתה יודע|מה את יודעת|מה ידוע לך|יודע עליי|יודעת עליי|מה זכרת|ספר לי עליי|מה שמרת|מחק זיכרון|הסר זיכרון|שכח ש|עדכן זיכרון|שנה זיכרון|תעדכן זיכרון|מה ה\S+\s+שלי|מהם ה\S+\s+שלי|מה אני אוהב|מה אני שונא/i,
    weather:   /מזג\s*אוויר|תחזית|גשם|שלג|חמסין|סופה|מעונן|שמשי|גשום|טמפרטורה|מעלות|לחות|חום בחוץ|קר בחוץ|חם בחוץ/i,
    sports:    /כדורגל|פרמייר|ליג|מאמן|קבוצ|שחקן|גול|ניצחון|הפסד|תוצא|טבלה|דירוג|העברות|ארסנל|צ'לסי|מנצ'סטר|ליברפול|טוטנהאם|אסטון|ניוקאסל|ברייטון|everton|arsenal|chelsea|liverpool|premier league|epl/i,
    project:   /פרויקט|פרוייקט|מיזם|ניהול פרויקט|צור פרויקט|הצג פרויקט|מחק פרויקט|רשימת פרויקטים|הפרויקטים שלי|אבן דרך|אבני דרך|milestone|התקדמות פרויקט|סטטוס פרויקט|ברי+פינג פרויקט|תובנות פרויקט|בריפינג.*פרויקט|פרויקט.*בריפינג/i,
    news:      /חדשות|כותרות|מה קורה|עדכונים|חדשות היום|ידיעות|עיתון|חדשות ספורט|חדשות כלכלה|חדשות פוליטיקה/i,
    shopping:  /רשימת קניות|קניות|סופרמרקט|הוסף.*לרשימה|מה יש ברשימה|רשימה.*קנייה|קנה.*חלב|קנה.*לחם|קנה.*ביצ/i,
    notes:     /תרשום לי|רשום לי|שמור פתק|שמור הערה|הצג הערות|מה כתבת|פתקים|הערות שלי|חפש הערה|מחק הערה/i,
    habit:     /הרגל|הרגלים|מעקב.*הרגל|תעקוב אחרי|הרצף שלי|רצף ימים|התאמנתי היום|עשיתי מדיטציה|בנה הרגל|תוסיף הרגל/i,
    insight:   /תובנות|דוח שימוש|סיכום שבועי|סיכום חודשי|דוח שבועי|דוח חודשי|דוח פרודוקטיביות|איך אני מתפקד|ניתוח שימוש|דוח התקדמות/i,
    music:     /מוזיקה|מוסיקה|פלייליסט|להשמיע|תנגן|תשמיע|ספוטיפיי|spotify/i,
    messaging: /שלח.*ווצאפ|שלח.*וואטסאפ|שלח.*מייל|ווצאפ ל|וואטסאפ ל|שלח מייל ל|שלח הודעה ל|שמור.*קשר|הוסף.*קשר|שמור.*טלפון|שמור.*מספר/i,
    // "כתוב לי" alone is too broad (catches "כתוב לי בדיחה" → chat).
    // Require explicit messaging/document context before routing to draft.
    draft:     /נסח לי|תנסח|עזור לי לנסח|תכין לי.*הודעה|הכן לי.*הודעה|תכין לי.*מייל|הכן לי.*מייל|תעזור לי לכתוב.*הודע|תעזור לי לכתוב.*מייל|נוסח ל|כתוב לי.*הודע|כתוב לי.*מייל|כתוב לי.*מכתב|תכתוב לי.*הודע|תכתוב לי.*מייל|תכתוב לי.*מכתב/i,
    e2e:        /בצע בדיקות קצה|בדיקות קצה לקצה|בדיקות קצה|בדיקת e2e|הרץ בדיקות|דוח בדיקות|end[- ]?to[- ]?end/i,
    code_error: /סרוק שגיאות קוד|מצא שגיאות קוד|בדיקת שגיאות|שגיאות בקוד|code error|error scan|סרוק שגיאות|בדוק שגיאות קוד|code scan errors/i,
    manus:      /manus|מאנוס|מטלה מורכבת|משימה מורכבת|משימה כבדה|מטלה כבדה|סוכן מורכב|אוטונומי|autonomous task|מחקר מעמיק|תחקור לעומק|חקור לעומק|deep research|deep dive|נתח לעומק|סקירת ספרות|מחקר שוק|בנה לי (אפליקציה|אתר|סקריפט|כלי)|בנה פרויקט|תכתוב לי (אפליקציה|סקריפט|כלי|אוטומציה)|צור לי (אפליקציה|סקריפט|כלי)/i,
    security:   /סריקת אבטחה|בדיקת אבטחה|מצא באגים|דוח באגים|דוח אבטחה|סרוק קוד|חפש בעיות|security scan/i,
    stocks:    /מניה|מניות|בורסה|שוק ההון|נסד"ק|nasdaq|s&p|ביטקוין|bitcoin|קריפטו|crypto|דולר|אירו|שקל|מטבע|תל אביב 35|ת"א 35|אפל|גוגל|טסלה|אמזון|מיקרוסופט|מדד|תיק השקעות|ריבית|אינפלציה/i,
    // "מה פירוש / מה המשמעות" removed — too broad, steals philosophical/memory questions.
    // Kept explicit language directives (תרגם, translate, "כתוב באנגלית" etc.)
    translate: /תרגם|תרגום|translate|translation|כתוב.*אנגלית|כתוב.*עברית|תכתוב.*אנגלית|תכתוב.*עברית|בצרפתית|בספרדית|בערבית|בגרמנית|מה פירוש המילה|מה המשמעות של המילה/i,
    settings:  /שנה.*אישיות|שנה.*אופי|דבר.*יותר.*לאט|דבר.*יותר.*מהר|האט|האץ|בטל קול|כבה קול|הפעל קול|אפשר קול|תשובות קצרות|תשובות ארוכות|שנה.*שם.*ל|קרא לי |קרא לעצמך|מה.*הגדרות.*שלי|הגדרות.*נוכחיות|שנה.*הגדרות/i,
    calendar:  /יומן|פגישות.*היום|פגישות.*מחר|מה יש לי.*ביומן|מה ביומן|קבע פגישה|קבע אירוע|הוסף.*ליומן|תקבע.*פגישה|אירועים.*היום|google calendar/i,
    prompt:    /צור פרומפט|תכתוב פרומפט|בנה פרומפט|שפר פרומפט|שדרג פרומפט|הערך פרומפט|נתח פרומפט|שמור פרומפט|רשימת פרומפטים|הצג פרומפטים|פרומפטים שמורים|הפרומפטים שלי|הנדסת פרומפטים|prompt engineering|כתוב.*פרומפט|פרומפט ל[א-ת]/i,
};

const REGISTRY_PATH = path.join(__dirname, 'custom', 'registry.json');

let _registryCache = [], _registryAt = 0;
function loadCustomRegistry() {
    if (Date.now() - _registryAt < 30000) return _registryCache;
    try { _registryCache = JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8')); }
    catch { _registryCache = []; }
    _registryAt = Date.now();
    return _registryCache;
}

function invalidateRouterCache() { _registryAt = 0; }

function classifyIntent(userMessage) {
    const msg = userMessage.toLowerCase();

    // Fast path: static keyword match
    for (const [intent, pattern] of Object.entries(KEYWORDS)) {
        if (pattern.test(userMessage)) {
            console.log(`🧭 Router (keyword): "${intent}" ← "${userMessage.slice(0, 50)}"`);
            return intent;
        }
    }

    // Dynamic custom agents (reads registry on every call — file is small)
    const customAgents = loadCustomRegistry();
    for (const agent of customAgents) {
        if (Array.isArray(agent.keywords) && agent.keywords.some(kw => msg.includes(kw.toLowerCase()))) {
            console.log(`🧭 Router (custom): "${agent.name}" ← "${userMessage.slice(0, 50)}"`);
            return agent.name;
        }
    }

    // Default
    console.log(`🧭 Router (default): "chat" ← "${userMessage.slice(0, 50)}"`);
    return 'chat';
}

// ─── Detailed classifier (collision-aware) ────────────────────────────────────
// Returns ALL matching keyword intents, not just the first. When more than one
// intent matches, the decision is "ambiguous" and the caller may escalate to the
// LLM to disambiguate. `intent` is always the best single guess (first match),
// so callers that ignore the extra fields behave exactly like classifyIntent().
function classifyIntentDetailed(userMessage) {
    const msg = userMessage.toLowerCase();

    const matches = [];
    for (const [intent, pattern] of Object.entries(KEYWORDS)) {
        if (pattern.test(userMessage)) matches.push(intent);
    }

    // Custom agents only considered when no built-in keyword matched.
    if (matches.length === 0) {
        const customAgents = loadCustomRegistry();
        for (const agent of customAgents) {
            if (Array.isArray(agent.keywords) && agent.keywords.some(kw => msg.includes(kw.toLowerCase()))) {
                matches.push(agent.name);
            }
        }
    }

    if (matches.length === 0) {
        return { intent: 'chat', matches: [], ambiguous: false };
    }
    if (matches.length === 1) {
        return { intent: matches[0], matches, ambiguous: false };
    }
    // Collision — multiple keyword intents matched the same message.
    console.log(`🧭 Router (ambiguous): [${matches.join(', ')}] ← "${userMessage.slice(0, 50)}"`);
    return { intent: matches[0], matches, ambiguous: true };
}

// ─── LLM fallback classifier ──────────────────────────────────────────────────
// Called only when keyword routing returns 'chat' and the message is long enough.
// Uses a fast Groq model with a 3s timeout and strict JSON output.

const VALID_INTENTS = new Set([
    'task', 'reminder', 'memory', 'weather', 'news', 'shopping', 'notes',
    'music', 'stocks', 'translate', 'sports', 'messaging', 'draft',
    'security', 'code_error', 'e2e', 'manus', 'past_conv', 'calendar', 'prompt', 'settings', 'habit', 'insight', 'chat',
]);

const LLM_CLASSIFY_PROMPT = `You are an intent classifier for a Hebrew personal assistant named Jarvis.
Given a user message, classify it into exactly one of these intents:
task, reminder, memory, weather, news, shopping, notes, music, stocks, translate,
sports, messaging, draft, security, code_error, e2e, past_conv,
calendar, prompt, settings, habit, insight, chat

Rules:
- task: add/delete/list/complete personal tasks or to-dos
- reminder: set/delete/list time-based reminders
- memory: save/recall/delete a personal fact about the user
- weather: current weather or forecast
- news: news headlines or current events
- shopping: shopping list management
- notes: save/retrieve free-form notes or memos
- music: play music or manage playlists
- stocks: stock prices, crypto, currency, financial markets
- translate: translate text between languages (explicit translation request)
- sports: sports results, leagues, teams, players
- messaging: send WhatsApp/email messages or manage contacts
- draft: compose a message, email, or letter for the user to send
- security: code security scan, OWASP vulnerability or bug report
- code_error: scan source code for runtime errors, logic bugs, anti-patterns, missing error handling
- e2e: run autonomous end-to-end self-tests of the assistant (UI, API, code scan, UX)
- manus: heavy/complex autonomous tasks requiring web browsing, multi-step execution, building software/scripts, deep research or market analysis (use Manus AI agent — NOT for simple questions)
- calendar: Google Calendar — view events, create meetings/appointments
- past_conv: asking about previous conversations with Jarvis
- prompt: create, refine, evaluate, save, or list AI prompts (prompt engineering)
- settings: change Jarvis personality, voice speed, response length, or assistant name
- habit: track recurring personal habits and daily streaks (start tracking a habit, log "I did it today", ask about a streak, list habits)
- insight: personal productivity insights, usage analysis, weekly/monthly summary reports
- chat: general conversation, question, or anything that does not fit above

Respond ONLY with valid JSON: {"intent": "NAME"}
Do NOT explain. Do NOT add text outside JSON.

User message: `;

async function classifyIntentWithLLM(userMessage) {
    try {
        const response = await axios.post(
            'https://api.groq.com/openai/v1/chat/completions',
            {
                model: 'llama-3.3-70b-versatile',
                messages: [{ role: 'user', content: LLM_CLASSIFY_PROMPT + userMessage }],
                max_tokens: 20,
                temperature: 0,
            },
            {
                headers: { Authorization: `Bearer ${process.env.GROQ_API_KEY}` },
                timeout: 3000,
            }
        );

        const raw = response.data?.choices?.[0]?.message?.content || '';
        const open = raw.indexOf('{'), close = raw.lastIndexOf('}');
        if (open === -1 || close === -1) return 'chat';

        let parsed;
        try { parsed = JSON.parse(raw.substring(open, close + 1)); } catch { return 'chat'; }

        const intent = (parsed.intent || '').trim().toLowerCase();
        if (!VALID_INTENTS.has(intent)) return 'chat';

        console.log(`🧭 Router (LLM): "${intent}" ← "${userMessage.slice(0, 50)}"`);
        return intent;
    } catch (err) {
        console.warn(`🧭 Router (LLM fallback failed): ${err.message}`);
        return 'chat';
    }
}

// ─── Complexity heuristic for auto-routing to Manus ──────────────────────────
// Returns true only when the message is genuinely multi-step / research-heavy
// AND cannot be handled by a simple one-shot LLM reply. Deliberately strict
// to avoid hijacking normal chat messages.

const COMPLEXITY_MIN_LEN = 180; // chars — short messages stay in chat

const COMPLEXITY_SIGNALS = [
    // Multi-step / sequential
    /\bשלב \d+\b|\bstep \d+\b/i,
    /לאחר מכן|ולאחר מכן|ואז ל|and then|next step/i,
    /\d+\.\s+[א-תa-z]/,  // numbered list items
    // Research / analysis
    /מחקר|research|analysis|analyze|נתח|השווה|compare|סקירה|survey|benchmark/i,
    // Build / create something substantial
    /בנה לי|תבנה|צור לי (אתר|אפליקציה|סקריפט|כלי|מערכת)|build (me |a |an )?[a-z]/i,
    // Report / deep dive
    /תכין דוח|כתוב דוח|prepare report|generate report|דוח מפורט|detailed report/i,
];

function detectComplexTask(userMessage) {
    if (userMessage.length < COMPLEXITY_MIN_LEN) return false;
    return COMPLEXITY_SIGNALS.some(pat => pat.test(userMessage));
}

module.exports = { classifyIntent, classifyIntentDetailed, classifyIntentWithLLM, invalidateRouterCache, loadCustomRegistry, detectComplexTask };
