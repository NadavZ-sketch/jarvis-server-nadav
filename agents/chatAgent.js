require('dotenv').config();
const { callGemma4, callGeminiVision } = require('./models');

const PERSONALITY_DESC = {
    friendly: (name) => `ידידותי, חם ואמפתי. אתה מדבר עם ${name} כמו חבר טוב שמבין אותו.
התאם את השפה, הטון ואורך התשובה לדרך הדיבור שלו.
כשהוא מצוחצח — היה מצוחצח. כשהוא קצר — היה קצר. כשהוא מפורט — ענה בהרחבה.`,

    formal: (_) => `מקצועי ורשמי. שפה עניינית, מדויקת ומובנית.
השתמש בפסקאות מסודרות, מספר נקודות בעת הצורך.
הימנע מביטויי סלנג ומשפטים לא פורמליים.`,

    concise: (_) => `קצר, ישיר וממוקד בלבד.
תשובה בין משפט אחד לשלושה לכל היותר — ללא הקדמות, ללא סיכומים, ללא מילוי.
אם השאלה פשוטה, תשובה של מילה אחת מקובלת לחלוטין.`,

    humorous: (_) => `ידידותי עם חוש הומור קל ואותנטי — ציניות עדינה, אירוניה חכמה.
שמור תמיד על עזרה אמיתית לצד הנוחות.
אל תגזים בהומור — הוא צריך להרגיש טבעי, לא מאולץ.`,
};

// ─── Follow-up detection ──────────────────────────────────────────────────────

const FOLLOW_UP_WORDS = [
    'מה עוד', 'תמשיך', 'תסביר', 'למה', 'איך', 'ועוד', 'אבל', 'ולמה',
    'ספר עוד', 'המשך', 'עוד על', 'בהמשך', 'אז', 'ואז', 'ומה',
    'תפרט', 'תדגים', 'תן דוגמה', 'מה זה', 'תרחיב',
];
const FOLLOW_UP_STANDALONE = /^(למה|איך|מה|כן|ספר|המשך|עוד|ממה|ומה)\??[.!]?$/i;

function detectFollowUp(userMessage, chatHistory) {
    if (!chatHistory || chatHistory.length === 0) return false;
    const msg = userMessage.trim();

    // Rule 1: standalone question/continuation word
    if (FOLLOW_UP_STANDALONE.test(msg)) return true;

    // Rule 2: short message starting with or containing a follow-up word
    if (msg.length < 25) {
        for (const word of FOLLOW_UP_WORDS) {
            if (msg.startsWith(word) || msg.includes(word)) return true;
        }
    }

    // Rule 3: very short message (≤6 chars) with existing history
    if (msg.length <= 6 && chatHistory.length >= 2) return true;

    return false;
}

// ─── Prompt builder ───────────────────────────────────────────────────────────

function buildSystemPrompt(chatHistory, longTermMemories, settings = {}, followUpContext = null) {
    const now = new Date();
    const currentDate = now.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' });
    const currentDay  = now.toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });
    const currentTime = now.toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit' });

    const name        = settings.assistantName || 'Jarvis';
    const userName    = settings.userName      || 'נדב';
    const gender      = settings.gender        || 'male';
    const personality = settings.personality   || 'friendly';

    const genderInstr = gender === 'female'
        ? 'את עוזרת אישית. השתמשי תמיד בלשון נקבה.'
        : 'אתה עוזר אישי. השתמש תמיד בלשון זכר.';

    const personalityDesc = (PERSONALITY_DESC[personality] || PERSONALITY_DESC.friendly)(userName);

    const historyString = chatHistory
        .map(msg => `${msg.role === 'user' ? userName : name}: ${msg.text}`)
        .join('\n');

    const emotionalIntelligenceBlock = `
--- הנחיות אמפתיה ועומק ---
זהה את הטון הרגשי של ${userName}: אם הוא נשמע מתוסכל, עצוב, לחוץ או מבולבל — פתח עם אמפתיה קצרה לפני שתגיב לתוכן.
אם הוא נרגש, שמח או חגיגי — שקף את זה בחיות.
כשהנושא דורש עומק (הסבר מושג, בעיה מורכבת, החלטה חשובה) — תן תשובה מלאה ומפורטת. אל תקצר שלא לצורך.
כשהנושא פשוט — אל תנפח תשובות. הרלוונטיות גוברת על האורך.
-----------------------------------`;

    const clarificationBlock = `
--- הנחיות בקשות עמומות ---
אם הבקשה חסרת פרטים קריטיים לביצוע (לדוגמה: "שלח הודעה" — למי? "תוסיף" — מה?), שאל שאלה ממוקדת אחת בלבד לפני שתגיב.
שאלת הבירור: קצרה, ישירה, בעברית. לא יותר ממשפט אחד.
לא לשאול כשהכוונה ברורה מן ההקשר — גם אם חסרים פרטים מינוריים.
-----------------------------------`;

    const followUpBlock = followUpContext
        ? `\n--- הקשר להמשך שיחה ---\n${followUpContext}\n-----------------------------------\n`
        : '';

    return `You are ${name}, a personal AI assistant for ${userName}. Respond in Hebrew only.
${genderInstr}
Personality: ${personalityDesc}
CRITICAL: Mirror ${userName}'s own writing style, vocabulary and tone in every response.
${emotionalIntelligenceBlock}
${clarificationBlock}
${followUpBlock}
--- Permanent Memories About ${userName} ---
${longTermMemories}
--------------------------------------

Current DateTime: ${currentDay}, ${currentDate}, ${currentTime}.

--- Recent Conversation History ---
${historyString}
-----------------------------------

Current message from ${userName}: `;
}

// ─── Local-optimised message builder ─────────────────────────────────────────
// Uses proper system role + alternating user/assistant pairs.
// Shorter prompt — local models have limited context and degrade with long inputs.

function buildLocalMessages(userMessage, chatHistory, longTermMemories, settings = {}, followUpContext = null) {
    const now = new Date();
    const currentDate = now.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' });
    const currentTime = now.toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit' });

    const name     = settings.assistantName || 'Jarvis';
    const userName = settings.userName      || 'נדב';
    const gender   = settings.gender        || 'male';
    const personality = settings.personality || 'friendly';

    const genderInstr = gender === 'female' ? 'השתמשי בלשון נקבה.' : 'השתמש בלשון זכר.';

    const personalityShort = {
        friendly: 'ידידותי וחם, כמו חבר טוב.',
        formal:   'מקצועי ורשמי.',
        concise:  'קצר מאוד — 1-3 משפטים.',
        humorous: 'ידידותי עם הומור קל.',
    };

    const memoriesShort = longTermMemories && longTermMemories.trim() && longTermMemories !== 'אין זיכרונות'
        ? `עובדות על ${userName}: ${longTermMemories.slice(0, 400)}`
        : '';

    const followUp = followUpContext ? `\nהקשר: ${followUpContext}` : '';

    const system = [
        `אתה ${name}, עוזר אישי של ${userName}. ענה תמיד בעברית בלבד.`,
        genderInstr,
        `אופי: ${personalityShort[personality] || personalityShort.friendly}`,
        `תאריך ושעה: ${currentDate} ${currentTime}.`,
        memoriesShort,
        followUp,
    ].filter(Boolean).join('\n');

    // system message
    const messages = [{ role: 'system', content: system }];

    // history — last 10 turns only (avoid context overflow on small models)
    const recentHistory = chatHistory.slice(-10);
    for (const msg of recentHistory) {
        messages.push({
            role:    msg.role === 'user' ? 'user' : 'assistant',
            content: msg.text,
        });
    }

    // current user message
    messages.push({ role: 'user', content: userMessage });

    return messages;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function runChatAgent(userMessage, imageBase64, chatHistory, longTermMemories, settings = {}) {
    try {
        const useLocal = settings.useLocalModel === true;
        let followUpContext = null;

        if (!imageBase64 && detectFollowUp(userMessage, chatHistory)) {
            const lastJarvis = [...chatHistory].reverse().find(m => m.role === 'jarvis');
            if (lastJarvis) {
                const topicHint = lastJarvis.text.slice(0, 120);
                const userName = settings.userName || 'נדב';
                followUpContext = `המשתמש ממשיך את השיחה הקודמת. ההודעה האחרונה שלך הייתה: "${topicHint}..."
המשך את אותו הנושא — אל תתחיל נושא חדש.`;
                console.log(`💬 Follow-up detected: "${userMessage.slice(0, 40)}"`);
            }
        }

        let answer;

        if (imageBase64) {
            // Vision always uses Gemini cloud
            const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings, followUpContext);
            answer = await callGeminiVision(systemPrompt + userMessage, imageBase64);

        } else if (useLocal) {
            // Local: proper system+history message array → Ollama (falls back to Groq)
            const msgs = buildLocalMessages(userMessage, chatHistory, longTermMemories, settings, followUpContext);
            answer = await callGemma4(msgs, true);

        } else {
            // Cloud: rich single-prompt format → Groq/DeepSeek/Gemini
            const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings, followUpContext);
            answer = await callGemma4([{ role: 'user', content: systemPrompt + userMessage }], false);
        }

        return { answer: answer || 'לא הצלחתי לגבש תשובה.' };

    } catch (err) {
        console.error('ChatAgent Error:', err.response ? JSON.stringify(err.response.data, null, 2) : err.message);
    }

    return { answer: 'סליחה, נתקלתי בבעיה. נסה שוב.' };
}

module.exports = { runChatAgent, detectFollowUp };
