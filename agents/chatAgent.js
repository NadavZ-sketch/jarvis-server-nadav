require('dotenv').config();
const { callGemma4, callGeminiVision } = require('./models');
const pinecone = require('../services/pineconeMemory');

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

    coach: (name) => `מאמן תומך ומניע. אתה עוזר ל-${name} להתקדם ולא עושה את העבודה במקומו.
שאל שאלה מנחה אחת כדי לפתוח חשיבה, ואז הצע כיוון קונקרטי.
הכר בהצלחות, שמור על טון מעודד ומאמין.`,

    casual: (name) => `שפת דיבור יום-יומית וחברית מאוד. מדבר עם ${name} כמו חבר ישן.
משפטים קצרים, ישירים, לפעמים בסלנג ישראלי טבעי. לא פורמלי בכלל.
אל תתחיל ב"בסדר" או "הנה" — קפוץ ישר לעניין.`,
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

// ─── User style analysis ─────────────────────────────────────────────────────

const CASUAL_MARKERS = new Set([
    'אחי','יאללה','בסדר גמור','קלאסי','לגמרי','ממש','וואו','סבבה','נו',
    'אח שלי','חבר','תראה','שמע','מה קורה','מה נשמע',
]);

function analyzeUserStyle(userMessage) {
    const words = userMessage.trim().split(/\s+/);
    const len = words.length;
    const lower = userMessage.toLowerCase();
    const casualCount = words.filter(w => CASUAL_MARKERS.has(w.replace(/[.,!?]/g, ''))).length;
    const register = casualCount >= 1 || len <= 4 ? 'casual' : 'neutral';
    const length = len <= 5 ? 'short' : len <= 20 ? 'medium' : 'long';
    return { length, register };
}

// ─── Relevance-based memory filtering ────────────────────────────────────────

const HE_STOP = new Set([
    'של','את','עם','אני','הוא','היא','אנחנו','הם','הן','זה','זו','אבל',
    'כי','גם','רק','כל','מה','מי','איך','למה','אם','כן','לא','על','אל',
    'בין','לפי','יש','אין','היה','הייתה','הייתי','יהיה','ל','ב','מ','ו',
]);

// Synchronous token-based ranking — used as a fast fallback when embeddings unavailable.
function _tokenRankMemories(lines, userMessage) {
    const msgTokens = new Set(
        userMessage.toLowerCase().split(/[\s,.\-!?:;״׳]+/)
            .filter(t => t.length > 1 && !HE_STOP.has(t))
    );
    if (msgTokens.size === 0) return lines;

    const scored = lines.map(line => {
        const tokens = line.toLowerCase()
            .replace(/^\s*-\s*\[[^\]]+\]\s*/, '')
            .split(/[\s,.\-!?:;״׳]+/)
            .filter(t => t.length > 1 && !HE_STOP.has(t));
        return { line, score: tokens.filter(t => msgTokens.has(t)).length };
    });
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, 10).map(s => s.line);
}

// Cosine similarity for ranking memory lines by embedding proximity to query.
function _cosine(a, b) {
    let dot = 0, na = 0, nb = 0;
    for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
    return na && nb ? dot / Math.sqrt(na * nb) : 0;
}

// Per-line embedding cache so the same memory text isn't re-embedded on every
// turn — memories change rarely, queries change every message. Bounded LRU-ish.
const _embedCache = new Map();
const _EMBED_CACHE_MAX = 500;
async function _cachedEmbed(text) {
    if (_embedCache.has(text)) return _embedCache.get(text);
    const vec = await pinecone.embed(text);
    if (_embedCache.size >= _EMBED_CACHE_MAX) {
        _embedCache.delete(_embedCache.keys().next().value);
    }
    _embedCache.set(text, vec);
    return vec;
}

// Hit-rate telemetry for the semantic-recall path (inspectable in tests/logs).
const memoryRecallStats = { semantic: 0, fallback: 0 };
function getMemoryRecallStats() { return { ..._embedStats() }; }
function _embedStats() {
    const total = memoryRecallStats.semantic + memoryRecallStats.fallback;
    return {
        ...memoryRecallStats,
        total,
        hitRate: total ? +(memoryRecallStats.semantic / total).toFixed(3) : 0,
    };
}

// Async embedding-based ranking. Pinecone is the primary path; token ranking is
// the last-resort fallback (Pinecone unavailable or embedding error).
// Used by the chat agent before assembling system prompt.
async function filterRelevantMemoriesAsync(memoriesText, userMessage, topK = 8) {
    if (!memoriesText || memoriesText === 'אין עדיין זיכרונות שמורים.') return memoriesText;
    const lines = memoriesText.split('\n').filter(l => l.trim());
    if (lines.length <= topK) return memoriesText;

    if (!pinecone.isReady()) {
        memoryRecallStats.fallback++;
        return _tokenRankMemories(lines, userMessage).join('\n');
    }
    try {
        // Query is always fresh; memory lines are served from the embed cache.
        const queryVec = await pinecone.embed(userMessage);
        const lineVecs = await Promise.all(
            lines.map(l => _cachedEmbed(l.replace(/^\s*-\s*/, ''))),
        );
        const scored = lines.map((line, i) => ({ line, score: _cosine(queryVec, lineVecs[i]) }));
        scored.sort((a, b) => b.score - a.score);
        memoryRecallStats.semantic++;
        return scored.slice(0, topK).map(s => s.line).join('\n');
    } catch (err) {
        console.warn('⚠️ filterRelevantMemoriesAsync embedding failed, using token fallback:', err.message);
        memoryRecallStats.fallback++;
        return _tokenRankMemories(lines, userMessage).join('\n');
    }
}

// Legacy sync export (kept for backward compatibility with existing call sites/tests).
function filterRelevantMemories(memoriesText, userMessage) {
    if (!memoriesText || memoriesText === 'אין עדיין זיכרונות שמורים.') return memoriesText;
    const lines = memoriesText.split('\n').filter(l => l.trim());
    if (lines.length <= 8) return memoriesText;
    return _tokenRankMemories(lines, userMessage).join('\n');
}

// ─── Prompt builder ───────────────────────────────────────────────────────────

function buildSystemPrompt(chatHistory, longTermMemories, settings = {}, followUpContext = null, userMessage = '') {
    const now = new Date();
    const currentDate = now.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' });
    const currentDay  = now.toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });
    const currentTime = now.toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit' });

    const name        = settings.assistantName || 'Jarvis';
    const userName    = settings.userName      || 'נדב';
    const gender      = settings.gender        || 'male';
    const personality = settings.personality   || 'friendly';
    const voiceMode   = settings.voiceMode     === true;

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

    const voiceModeBlock = voiceMode ? `
--- מצב שיחה קולית ---
אנחנו בשיחה קולית. כללים קשיחים:
- ענה ב-1 עד 2 משפטים מדוברים בלבד (עד 25 מילים), אלא אם נשאלת שאלה מורכבת שדורשת הרחבה.
- שפה מדוברת לחלוטין — כאילו אתה מדבר, לא כותב. זרימה טבעית של דיבור.
- ללא markdown בכלל: ללא *, **, #, -, bullets, קוד בלוקים, מספרים, סמלים מיוחדים.
- אל תפתח ב-"בסדר", "הנה", "בטח", "כמובן" — קפוץ ישר לתשובה.
- אל תשאל שאלה בחזרה אלא אם חיוני להבנת הבקשה.
- אם נתת תשובה מלאה — תפסיק. אל תוסיף "יש לך עוד שאלות?" ואל תסכם.
-----------------------------------` : '';

    const profile = settings.userProfile || null;
    const profileBlock = profile ? `
--- User Profile (Personalization) ---
טון דיבור מועדף: ${profile.speaking_tone || 'friendly'}
שעות מועדפות: ${(profile.preferred_hours || []).join(', ') || 'לא הוגדר'}
תחומי עניין: ${(profile.interests || []).join(', ') || 'לא הוגדר'}
משימות חוזרות: ${(profile.recurring_tasks || []).join(', ') || 'לא הוגדר'}
השתמש במידע הזה כדי להתאים את הסגנון ולהציע צעדים הבאים רלוונטיים.
-----------------------------------` : '';

    const chatSummary = (settings.chatSummary || '').trim();
    const summaryBlock = chatSummary ? `
--- סיכום השיחה עד כה ---
${chatSummary}
-----------------------------------` : '';

    const styleHint = userMessage && !voiceMode ? (() => {
        const { length, register } = analyzeUserStyle(userMessage);
        return `\nStyle hint: mirror length=${length}, register=${register}.`;
    })() : '';

    return `You are ${name}, a personal AI assistant for ${userName}. Respond in Hebrew only.
${genderInstr}
Personality: ${personalityDesc}
CRITICAL: Mirror ${userName}'s own writing style, vocabulary and tone in every response.${styleHint}
CRITICAL: Never claim you have performed an action (added a task, set a reminder, saved a note, etc.) unless you have tools to actually do it. If the user asks you to DO something actionable, say you'll try OR redirect them — but NEVER say "הוספתי", "שמרתי", "הגדרתי" if you haven't actually executed it.
${voiceModeBlock}
${emotionalIntelligenceBlock}
${clarificationBlock}
${profileBlock}
${followUpBlock}${summaryBlock}
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

function buildLocalMessages(userMessage, chatHistory, longTermMemories, settings = {}, followUpContext = null, chatSummary = '') {
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
    const summaryHint = chatSummary ? `\nסיכום שיחה: ${chatSummary.slice(0, 300)}` : '';
    const profile = settings.userProfile || null;
    const profileShort = profile
        ? `פרופיל משתמש: טון=${profile.speaking_tone || 'friendly'}; תחומי עניין=${(profile.interests || []).slice(0, 5).join(', ') || 'לא הוגדר'}; משימות חוזרות=${(profile.recurring_tasks || []).slice(0, 5).join(', ') || 'לא הוגדר'}`
        : '';

    const system = [
        `אתה ${name}, עוזר אישי של ${userName}. ענה תמיד בעברית בלבד.`,
        genderInstr,
        `אופי: ${personalityShort[personality] || personalityShort.friendly}`,
        `תאריך ושעה: ${currentDate} ${currentTime}.`,
        memoriesShort,
        profileShort,
        summaryHint,
        followUp,
    ].filter(Boolean).join('\n');

    // system message
    const messages = [{ role: 'system', content: system }];

    // history — recent turns. The caller (loadChatHistory) already trims to a
    // token budget; keep a generous local cap to avoid overflow on small models.
    const recentHistory = chatHistory.slice(-24);
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
        const useLocal  = settings.useLocalModel === true;
        const voiceMode = settings.voiceMode === true;
        const maxTokens = voiceMode ? 200 : 800;
        const chatSummary = (settings.chatSummary || '').trim();
        let followUpContext = null;

        if (!imageBase64 && detectFollowUp(userMessage, chatHistory)) {
            const lastJarvis = [...chatHistory].reverse().find(m => m.role === 'jarvis');
            if (lastJarvis) {
                const topicHint = lastJarvis.text.slice(0, 120);
                followUpContext = `המשתמש ממשיך את השיחה הקודמת. ההודעה האחרונה שלך הייתה: "${topicHint}..."
המשך את אותו הנושא — אל תתחיל נושא חדש.`;
                console.log(`💬 Follow-up detected: "${userMessage.slice(0, 40)}"`);
            }
        }

        let answer;

        if (imageBase64) {
            // Vision always uses Gemini cloud
            const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings, followUpContext, userMessage);
            answer = await callGeminiVision(systemPrompt + userMessage, imageBase64);

        } else if (useLocal) {
            // Local: proper system+history message array → Ollama (falls back to Groq)
            const msgs = buildLocalMessages(userMessage, chatHistory, longTermMemories, settings, followUpContext, chatSummary);
            answer = await callGemma4(msgs, true, maxTokens);

        } else {
            // Cloud: rich single-prompt format → Groq/DeepSeek/Gemini
            const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings, followUpContext, userMessage);
            answer = await callGemma4([{ role: 'user', content: systemPrompt + userMessage }], false, maxTokens);
        }

        const finalAnswer = answer || 'לא הצלחתי לגבש תשובה.';

        // Generate 2-3 follow-up suggestions (skipped in voice mode to keep latency low)
        let suggestions = [];
        if (!voiceMode && !imageBase64 && finalAnswer.length > 20) {
            try {
                const sugPrompt = `בהתבסס על השיחה הבאה, הצע 2-3 שאלות המשך קצרות בעברית שהמשתמש עשוי לרצות לשאול. החזר JSON בלבד: {"suggestions":["...","..."]}
שאלת המשתמש: "${userMessage.slice(0, 100)}"
תשובת ג'רוויס: "${finalAnswer.slice(0, 150)}"`;
                const raw = await Promise.race([
                    callGemma4([{ role: 'user', content: sugPrompt }], useLocal, 80),
                    new Promise(resolve => setTimeout(() => resolve(null), 1500)),
                ]);
                if (raw) {
                    const match = raw.match(/\{[\s\S]*\}/);
                    if (match) suggestions = JSON.parse(match[0]).suggestions || [];
                }
            } catch (_) { /* never block on suggestions */ }
        }

        return { answer: finalAnswer, ...(suggestions.length ? { suggestions } : {}) };

    } catch (err) {
        console.error('ChatAgent Error:', err.response ? JSON.stringify(err.response.data, null, 2) : err.message);
    }

    return { answer: 'סליחה, נתקלתי בבעיה. נסה שוב.' };
}

module.exports = { runChatAgent, detectFollowUp, filterRelevantMemories, filterRelevantMemoriesAsync, getMemoryRecallStats, analyzeUserStyle, buildSystemPrompt };
