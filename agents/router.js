// Keyword-based fast routing — no API call needed
// ORDER MATTERS: reminder must be before memory to avoid תזכיר לי conflict
const fs   = require('fs');
const path = require('path');
const axios = require('axios');

const KEYWORDS = {
    past_conv: /מה דיברנו|בפעם הקודמת|מה אמרת לי|תזכיר לי מה.*אמרת|שוחחנו על|מה שאמרת/i,
    task:      /משימ|הוסף משימ|מחק משימ|רשימת משימ|הראה משימ|כל המשימ|סיימתי|סמן כבוצע|השלמתי/i,
    reminder:  /תזכיר לי|הזכר לי|תזכורת|להזכיר לי|הצג תזכורות|מחק תזכורת|בטל תזכורת|כל התזכורות|רשימת תזכורות/i,
    memory:    /זכור ש|תזכור ש|שמור ש|מה אתה יודע|מה זכרת|ספר לי עליי|מה שמרת|מחק זיכרון|הסר זיכרון|שכח ש/i,
    weather:   /מזג\s*אוויר|תחזית|גשם|שלג|חמסין|סופה|מעונן|שמשי|גשום|טמפרטורה|מעלות|לחות|חום בחוץ|קר בחוץ|חם בחוץ/i,
    sports:    /כדורגל|פרמייר|ליג|מאמן|קבוצ|שחקן|גול|ניצחון|הפסד|תוצא|טבלה|דירוג|העברות|ארסנל|צ'לסי|מנצ'סטר|ליברפול|טוטנהאם|אסטון|ניוקאסל|ברייטון|everton|arsenal|chelsea|liverpool|premier league|epl/i,
    news:      /חדשות|כותרות|מה קורה|עדכונים|חדשות היום|ידיעות|עיתון|חדשות ספורט|חדשות כלכלה|חדשות פוליטיקה/i,
    shopping:  /רשימת קניות|קניות|סופרמרקט|הוסף.*לרשימה|מה יש ברשימה|רשימה.*קנייה|קנה.*חלב|קנה.*לחם|קנה.*ביצ/i,
    notes:     /תרשום לי|רשום לי|שמור פתק|שמור הערה|הצג הערות|מה כתבת|פתקים|הערות שלי|חפש הערה|מחק הערה/i,
    music:     /מוזיקה|מוסיקה|פלייליסט|להשמיע|תנגן|תשמיע|ספוטיפיי|spotify/i,
    messaging: /שלח.*ווצאפ|שלח.*וואטסאפ|שלח.*מייל|ווצאפ ל|וואטסאפ ל|מייל ל|שלח הודעה ל|שמור.*קשר|הוסף.*קשר|שמור.*טלפון|שמור.*מספר/i,
    draft:     /נסח לי|תנסח|עזור לי לנסח|כתוב לי|תכתוב לי|תכין לי|הכן לי.*הודעה|תעזור לי לכתוב|נוסח ל/i,
    insight:   /תן לי טיפים|מה אפשר לשפר|ניתוח שלי|דוח שימוש|עצות לשיפור|התייעלות|תובנות|איך אני משתמש/i,
    security:  /סריקת אבטחה|בדיקת אבטחה|מצא באגים|דוח באגים|דוח אבטחה|סרוק קוד|חפש בעיות|security scan/i,
    stocks:    /מניה|מניות|בורסה|שוק ההון|נסד"ק|nasdaq|s&p|ביטקוין|bitcoin|קריפטו|crypto|דולר|אירו|שקל|מטבע|תל אביב 35|ת"א 35|אפל|גוגל|טסלה|אמזון|מיקרוסופט|מדד|תיק השקעות|ריבית|אינפלציה/i,
    translate: /תרגם|תרגום|translate|translation|כתוב.*אנגלית|כתוב.*עברית|בעברית|באנגלית|בצרפתית|בספרדית|בערבית|בגרמנית|מה פירוש|מה המשמעות/i,
    factory:   /צור אייג'נט|יצור אייג'נט|בנה אייג'נט|הוסף אייג'נט|תייצר אייג'נט|תבנה אייג'נט|רשימת אייג'נטים|הצג אייג'נטים|מחק אייג'נט|הסר אייג'נט/i,
};

const REGISTRY_PATH = path.join(__dirname, 'custom', 'registry.json');
const PENDING_PATH  = path.join(__dirname, 'custom', 'pending.json');

let _pendingCache = false, _pendingAt = 0;
function hasPendingAgent() {
    if (Date.now() - _pendingAt < 5000) return _pendingCache;
    try { _pendingCache = !!JSON.parse(fs.readFileSync(PENDING_PATH, 'utf8')); }
    catch { _pendingCache = false; }
    _pendingAt = Date.now();
    return _pendingCache;
}

let _registryCache = [], _registryAt = 0;
function loadCustomRegistry() {
    if (Date.now() - _registryAt < 30000) return _registryCache;
    try { _registryCache = JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8')); }
    catch { _registryCache = []; }
    _registryAt = Date.now();
    return _registryCache;
}

function invalidateRouterCache() { _pendingAt = 0; _registryAt = 0; }

function classifyIntent(userMessage) {
    const msg = userMessage.toLowerCase();

    // Pending agent confirmation/cancellation takes priority
    if (/^(כן|אשר|yes|approve|אוקי|בסדר|שלב|לא|בטל|cancel|no|ביטול|אל תשלב)$/i.test(userMessage.trim())) {
        if (hasPendingAgent()) {
            console.log(`🧭 Router (pending): "factory" ← "${userMessage.trim()}"`);
            return 'factory';
        }
    }

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

// ─── LLM fallback classifier ──────────────────────────────────────────────────
// Called only when keyword routing returns 'chat' and the message is long enough.
// Uses a fast Groq model with a 3s timeout and strict JSON output.

const VALID_INTENTS = new Set([
    'task', 'reminder', 'memory', 'weather', 'news', 'shopping', 'notes',
    'music', 'stocks', 'translate', 'sports', 'messaging', 'draft',
    'insight', 'security', 'factory', 'past_conv', 'chat',
]);

const LLM_CLASSIFY_PROMPT = `You are an intent classifier for a Hebrew personal assistant named Jarvis.
Given a user message, classify it into exactly one of these intents:
task, reminder, memory, weather, news, shopping, notes, music, stocks, translate,
sports, messaging, draft, insight, security, factory, past_conv, chat

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
- translate: translate text between languages
- sports: sports results, leagues, teams, players
- messaging: send WhatsApp/email messages or manage contacts
- draft: compose a message/email/text for the user
- insight: analyze the user's habits or provide usage tips
- security: code security scan or bug report
- factory: create/manage/delete custom agents
- past_conv: asking about previous conversations with Jarvis
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
        const open = raw.lastIndexOf('{'), close = raw.lastIndexOf('}');
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

module.exports = { classifyIntent, classifyIntentWithLLM, invalidateRouterCache };
