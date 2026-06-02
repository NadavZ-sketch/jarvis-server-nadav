require('dotenv').config();
const express    = require('express');
const cors       = require('cors');
const path       = require('path');
const cron       = require('node-cron');
const nodemailer = require('nodemailer');
const fs         = require('fs');
const { createClient } = require('@supabase/supabase-js');
const googleTTS  = require('google-tts-api');
const { OpenAI, toFile } = require('openai');

const groqWhisper = new OpenAI({
    apiKey: process.env.GROQ_API_KEY,
    baseURL: 'https://api.groq.com/openai/v1',
});

// ─── Email transporter ────────────────────────────────────────────────────────
const mailTransporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
        user: process.env.GMAIL_USER,
        pass: process.env.GMAIL_APP_PASSWORD,
    },
});

async function sendEmail(to, body) {
    await mailTransporter.sendMail({
        from: `"Jarvis" <${process.env.GMAIL_USER}>`,
        to,
        subject: 'הודעה מג\'רביס',
        text: body,
    });
    console.log(`📧 Email sent to ${to}`);
}

const { classifyIntent, classifyIntentDetailed, classifyIntentWithLLM, loadCustomRegistry } = require('./agents/router');
const routeTracker = require('./services/routeTracker');
const { runTaskAgent }        = require('./agents/taskAgent');
const { runReminderAgent }    = require('./agents/reminderAgent');
const { runMemoryAgent, autoExtractMemory, setMemoryCacheInvalidator } = require('./agents/memoryAgent');
const { cleanupExpiredMemories } = require('./services/memoryCleanup');
const { getAgentRegistry } = require('./services/agentRegistryService');
const agentMetrics = require('./services/agentMetrics');
const { runChatAgent, detectFollowUp, filterRelevantMemories, filterRelevantMemoriesAsync, buildSystemPrompt } = require('./agents/chatAgent');
const conversationSummary = require('./services/conversationSummary');
const { runSportsAgent }      = require('./agents/sportsAgent');
const { runMessagingAgent }   = require('./agents/messagingAgent');
const { runDraftAgent }       = require('./agents/draftAgent');
const { runSecurityAgent }    = require('./agents/securityAgent');
const { runCodeErrorAgent }   = require('./agents/codeErrorAgent');
const { runE2EAgent, buildClaudePrompt, countsBySeverity, computeScore } = require('./agents/e2eAgent');
const { runManusAgent, isManusConfigured } = require('./agents/manusAgent');
const { analyzePatterns, optimizeDayPlan } = require('./agents/insightAgent');
const priorityEngine          = require('./services/priorityEngine');
const { runWeatherAgent }     = require('./agents/weatherAgent');
const { runNewsAgent }        = require('./agents/newsAgent');
const { runShoppingAgent }    = require('./agents/shoppingAgent');
const { runNotesAgent }       = require('./agents/notesAgent');
const { runStocksAgent }      = require('./agents/stocksAgent');
const { runTranslationAgent } = require('./agents/translationAgent');
const { runMusicAgent }       = require('./agents/musicAgent');
const { detectCapabilityGap, savePendingGap, handleConfirmation } = require('./agents/devTaskAgent');
const { runOrchestratorAgent } = require('./agents/orchestratorAgent');
const contextResolver = require('./services/contextResolver');
const proactiveEngine = require('./services/proactiveEngine');
const profileLearner  = require('./services/profileLearner');
const styleLearner    = require('./services/styleLearner');
const feedbackStore   = require('./services/feedbackStore');
const { selectByTokenBudget } = require('./services/contextWindow');
const documentParser = require('./services/documentParser');
const { runCalendarAgent, buildAuthUrl, getAccessToken } = require('./agents/calendarAgent');
const { runPromptAgent }      = require('./agents/promptAgent');
const { runSettingsAgent }    = require('./agents/settingsAgent');
const { runProjectAgent, buildProjectsBriefing } = require('./agents/projectAgent');
const dispatcher              = require('./agents/dispatcher');

// Single AGENTS map passed into the dispatcher so intent→agent wiring lives in
// one place (agents/dispatcher.js) instead of duplicated if/else chains.
const AGENTS = {
    runTaskAgent, runReminderAgent, runMemoryAgent, runWeatherAgent, runNewsAgent,
    runShoppingAgent, runNotesAgent, runStocksAgent, runTranslationAgent, runMusicAgent,
    runSportsAgent, runMessagingAgent, runDraftAgent,
    runCalendarAgent, runPromptAgent, runSettingsAgent, runProjectAgent,
    runSecurityAgent, runCodeErrorAgent, runE2EAgent, runManusAgent,
};

const pinecone                = require('./services/pineconeMemory');
const { createTasksRouter } = require('./routes/tasks');
const { createRemindersRouter } = require('./routes/reminders');
const { createRemindersController } = require('./controllers/remindersController');
const { createChatRouter } = require('./routes/chat');
const { isAllowedByRolePlan, isBlockedAction } = require('./services/policyEngine');

const helmet    = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
// Render (and most reverse proxies) sit in front of the Node process.
// Without trust proxy, express-rate-limit can't identify callers correctly.
app.set('trust proxy', 1);

// ─── Task auto-reminder pending ───────────────────────────────────────────────
const TASK_REMINDER_PENDING = path.join(__dirname, 'task_reminder_pending.json');

async function saveTaskReminderPending(data) {
    await fs.promises.writeFile(TASK_REMINDER_PENDING, JSON.stringify(data, null, 2));
}
async function loadTaskReminderPending() {
    try { return JSON.parse(await fs.promises.readFile(TASK_REMINDER_PENDING, 'utf8')); } catch { return null; }
}
async function clearTaskReminderPending() {
    try { await fs.promises.unlink(TASK_REMINDER_PENDING); } catch { /* ok */ }
}

const TASK_REM_YES = /^(כן|אשר|בסדר|אוקי|יאללה|כן בבקשה|תזכיר|כן תזכיר)/i;
const TASK_REM_NO  = /^(לא|לא צריך|לא עכשיו|דלג)/i;

async function handleTaskReminderConfirmation(userMessage) {
    const pending = await loadTaskReminderPending();
    if (!pending) return null;

    if (TASK_REM_YES.test(userMessage.trim())) {
        const { taskContent, dueDate } = pending;
        const reminderDate = new Date(dueDate);
        reminderDate.setDate(reminderDate.getDate() - 1);
        reminderDate.setHours(9, 0, 0, 0); // 09:00 one day before

        const pad = n => String(n).padStart(2, '0');
        const isoReminder = `${reminderDate.getFullYear()}-${pad(reminderDate.getMonth()+1)}-${pad(reminderDate.getDate())}T09:00:00+03:00`;

        try {
            await supabase.from('reminders').insert([{ text: `לסיים משימה: ${taskContent}`, scheduled_time: isoReminder }]);
        } catch { /* ignore */ }

        await clearTaskReminderPending();
        const dateStr = reminderDate.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem', weekday: 'long', day: 'numeric', month: 'long' });
        return { answer: `✅ הגדרתי תזכורת ל${dateStr} בשעה 09:00 לסיים את: "${taskContent}"` };
    }

    if (TASK_REM_NO.test(userMessage.trim())) {
        await clearTaskReminderPending();
        return { answer: 'בסדר, לא הגדרתי תזכורת.' };
    }

    return null;
}

const policyAuditTrail = [];
const consentLedger = new Map(); // userId:domain -> { approvedAt }

function getActor(req) {
    return {
        userId: String(req.headers['x-user-id'] || req.body?.userId || 'anonymous'),
        role: String(req.headers['x-user-role'] || 'member').toLowerCase(),
        plan: String(req.headers['x-user-plan'] || 'free').toLowerCase(),
    };
}

function auditPolicy({ userId, actionType, result }) {
    const entry = { userId, actionType, timestamp: new Date().toISOString(), result };
    policyAuditTrail.push(entry);
    if (policyAuditTrail.length > 500) policyAuditTrail.shift();
    console.log('[audit]', entry);
}

function actionDomain(actionType) {
    if (String(actionType).startsWith('contacts.')) return 'contacts';
    if (String(actionType).startsWith('reminders.')) return 'reminders';
    if (String(actionType).startsWith('messaging.')) return 'messaging';
    return actionType;
}

function hasStoredConsent(userId, actionType) {
    return consentLedger.has(`${userId}:${actionDomain(actionType)}`);
}

function storeConsent(userId, actionType) {
    consentLedger.set(`${userId}:${actionDomain(actionType)}`, { approvedAt: new Date().toISOString() });
}

function requirePolicy(actionType, options = {}) {
    const { sensitive = false, irreversible = false } = options;
    return (req, res, next) => {
        if (process.env.NODE_ENV === 'test') return next();
        const actor = getActor(req);
        if (isBlockedAction(actionType)) {
            auditPolicy({ userId: actor.userId, actionType, result: 'blocked' });
            return res.status(403).json({ ok: false, code: 'ACTION_BLOCKED', message: 'This action is blocked by policy.' });
        }
        if (!isAllowedByRolePlan({ actionType, role: actor.role, plan: actor.plan })) {
            auditPolicy({ userId: actor.userId, actionType, result: 'denied_not_allowed' });
            return res.status(403).json({ ok: false, code: 'INSUFFICIENT_PERMISSION', message: 'Your role/plan is not allowed to perform this action.' });
        }
        if (sensitive) {
            const explicitConsentNow = req.body?.consent === true || String(req.headers['x-user-consent'] || '').toLowerCase() === 'true';
            const consentAlreadyGranted = hasStoredConsent(actor.userId, actionType);
            if (!explicitConsentNow && !consentAlreadyGranted) {
                auditPolicy({ userId: actor.userId, actionType, result: 'denied_no_consent' });
                return res.status(403).json({ ok: false, code: 'CONSENT_REQUIRED', message: 'Explicit consent is required for sensitive actions.' });
            }
            if (explicitConsentNow) storeConsent(actor.userId, actionType);
        }
        if (irreversible) {
            const confirmed = req.body?.confirm === true || String(req.headers['x-confirm-action'] || '').toLowerCase() === 'yes';
            if (!confirmed) {
                auditPolicy({ userId: actor.userId, actionType, result: 'denied_missing_confirmation' });
                return res.status(409).json({ ok: false, code: 'CONFIRMATION_REQUIRED', message: 'Are you sure? confirmation is required for irreversible action.' });
            }
        }
        auditPolicy({ userId: actor.userId, actionType, result: 'allowed' });
        next();
    };
}
app.use(helmet({
    crossOriginResourcePolicy: { policy: 'cross-origin' },
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc:  ["'self'", 'unpkg.com', 'cdn.jsdelivr.net'],
            styleSrc:   ["'self'", 'unpkg.com', 'cdn.jsdelivr.net'],
            connectSrc: ["'self'"],
            imgSrc:     ["'self'", 'data:'],
        },
    },
}));
const _corsOrigins = process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',').map(o => o.trim())
    : null;
if (!_corsOrigins) {
    console.warn('⚠️  CORS: ALLOWED_ORIGINS not set — allowing all origins. Set ALLOWED_ORIGINS in production.');
}
app.use(cors({
    origin: _corsOrigins || '*',
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key', 'X-User-Id', 'X-User-Role', 'X-User-Plan', 'X-User-Consent', 'X-Confirm-Action'],
}));

app.use(express.json({ limit: '10mb' }));

const _rl = (max, windowMs = 60_000) => rateLimit({ windowMs, max, standardHeaders: true, legacyHeaders: false });
app.use('/ask-jarvis',    _rl(30));
app.use('/send-email',    _rl(5));
app.use('/stream-jarvis', _rl(20));
app.use('/tasks',         _rl(60));
app.use('/notes',         _rl(60));
app.use('/reminders',     _rl(60));
app.use('/memories',      _rl(60));
app.use('/contacts',      _rl(60));
app.use('/shopping',      _rl(60));

const isTestEnv = process.env.NODE_ENV === 'test';
const SUPABASE_URL = process.env.SUPABASE_URL || (isTestEnv ? 'http://127.0.0.1:54321' : undefined);
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_KEY || (isTestEnv ? 'test-anon-key' : undefined);
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_KEY || (isTestEnv ? 'test-service-key' : undefined);

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error('Missing Supabase env vars. Required: SUPABASE_URL, SUPABASE_ANON_KEY (or SUPABASE_KEY), SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_KEY)');
}

const supabasePublic = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const supabaseAdmin = (SUPABASE_SERVICE_ROLE_KEY === SUPABASE_ANON_KEY)
    ? supabasePublic
    : createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
const supabase = supabaseAdmin;

// Persist per-agent latency/intent metrics to Supabase (degrades to in-memory).
agentMetrics.init(supabase);

// Intent → registry agent id (e.g. 'task' → 'taskAgent'). Core agents are never
// disablable, so they are exempt from the disabled check below.
const EXEMPT_FROM_DISABLE = new Set(['chat', 'router', 'draft', 'memory', 'past_conv']);
function isAgentDisabled(agentName) {
    if (!agentName || EXEMPT_FROM_DISABLE.has(agentName)) return false;
    try {
        const id = `${agentName}Agent`;
        const rec = getAgentRegistry().find(a => a.id === id);
        return !!(rec && rec.status === 'disabled');
    } catch (_) {
        return false;
    }
}
const AGENT_DISABLED_REPLY = { answer: 'הסוכן הזה כבוי כרגע במרכז השליטה. אפשר להפעיל אותו שם מחדש.', skipTts: true };

app.use('/tasks', createTasksRouter({ supabase }));
app.use('/reminders', createRemindersRouter({ supabase, pinecone, requirePolicy }));
app.use('/', createChatRouter({ supabase, askJarvisHandler, streamJarvisHandler }));
const remindersController = createRemindersController({ supabase, pinecone });
app.get('/check-reminders', remindersController.check);
const LOCAL_PROFILE_FILE = path.join(__dirname, 'notes', 'user_profile_fallback.json');

function readLocalProfile() {
    try {
        if (!fs.existsSync(LOCAL_PROFILE_FILE)) return null;
        return JSON.parse(fs.readFileSync(LOCAL_PROFILE_FILE, 'utf8'));
    } catch (_) {
        return null;
    }
}

function writeLocalProfile(profile) {
    try {
        fs.mkdirSync(path.dirname(LOCAL_PROFILE_FILE), { recursive: true });
        fs.writeFileSync(LOCAL_PROFILE_FILE, JSON.stringify(profile, null, 2), 'utf8');
    } catch (_) {}
}

function deleteLocalProfile() {
    try {
        if (fs.existsSync(LOCAL_PROFILE_FILE)) fs.unlinkSync(LOCAL_PROFILE_FILE);
    } catch (_) {}
}

// ─── In-memory TTL Cache ──────────────────────────────────────────────────────

const _cache = new Map(); // key → { value, expiresAt }
const _sessionState = new Map(); // chatId-scoped ephemeral state (mood, counters)

function cacheGet(key) {
    const entry = _cache.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) { _cache.delete(key); return undefined; }
    return entry.value;
}

const _CACHE_MAX = 1000;
function cacheSet(key, value, ttlMs) {
    _cache.set(key, { value, expiresAt: Date.now() + ttlMs });
    if (_cache.size > _CACHE_MAX) {
        const now = Date.now();
        for (const [k, v] of _cache) {
            if (now > v.expiresAt) _cache.delete(k);
            if (_cache.size <= _CACHE_MAX) break;
        }
    }
}

function cacheInvalidate(key) { _cache.delete(key); }

// Allow agents/memoryAgent to bust the memories cache after a successful save,
// so the next fetchLongTermMemories sees the new row immediately. Guarded so
// integration test mocks that omit this export don't fail at module load.
if (typeof setMemoryCacheInvalidator === 'function') {
    setMemoryCacheInvalidator(() => cacheInvalidate('memories'));
}

const TTL_MEMORIES     = 30 * 1000;       // 30 sec — short, so newly-saved memories are immediately visible
const TTL_CHAT_HISTORY = 30 * 1000;       // 30 sec
const TTL_USER_PROFILE = 60 * 1000;       // 60 sec — profile changes rarely; invalidated on write

// ─── Past-conversation detection ──────────────────────────────────────────────

const PAST_CONV_PATTERN = /מה דיברנו|בפעם הקודמת|מה אמרת לי|תזכיר לי מה|שוחחנו על|מה שאמרת/i;

const HE_STOP_SEARCH = new Set([
    'של','את','עם','אני','הוא','היא','אנחנו','הם','הן','זה','זו','אבל',
    'כי','גם','רק','כל','מה','מי','איך','למה','אם','כן','לא','על','אל',
    'בין','לפי','יש','אין','היה','הייתה','הייתי','יהיה','ל','ב','מ','ו',
    'דיברנו','הקודמת','בפעם','אמרת','שוחחנו',
]);

// ─── Chat History ─────────────────────────────────────────────────────────────

let chatMemoryFallback = [];

async function loadChatHistory(chatId = 'default-session') {
    const cacheKey = `chatHistory:${chatId}`;
    const cached = cacheGet(cacheKey);
    if (cached) return cached;

    try {
        // Fetch a generous tail, then trim to a token budget so short messages
        // give more continuity and long ones don't blow the prompt budget.
        const { data, error } = await supabase
            .from('chat_history')
            .select('role, text')
            .eq('chat_id', chatId)
            .order('created_at', { ascending: false })
            .limit(60);

        if (error) throw error;
        const ordered = (data || []).reverse();
        const result = selectByTokenBudget(ordered, { maxTokens: 3500, maxMessages: 40 });
        cacheSet(cacheKey, result, TTL_CHAT_HISTORY);
        return result;
    } catch (err) {
        console.error('⚠️ loadChatHistory fallback:', err.message);
        return selectByTokenBudget(chatMemoryFallback, { maxTokens: 3500, maxMessages: 40 });
    }
}

async function saveChatMessage(role, text, chatId = 'default-session') {
    try {
        const { error } = await supabase.from('chat_history').insert([{ role, text, chat_id: chatId }]);
        if (error) throw error;
    } catch (err) {
        console.error('⚠️ saveChatMessage fallback:', err.message);
    }
    chatMemoryFallback.push({ role, text });
    if (chatMemoryFallback.length > 60) chatMemoryFallback = chatMemoryFallback.slice(-60);
}

// ─── Memories ─────────────────────────────────────────────────────────────────

async function fetchLongTermMemories(query = null) {
    // Semantic search via Pinecone when a query is provided and Pinecone is ready
    if (query && pinecone.isReady()) {
        try {
            const hits = await pinecone.searchMemories(query, 12);
            if (hits !== null) {
                return hits.length === 0
                    ? 'אין עדיין זיכרונות שמורים.'
                    : hits.map(c => `- ${c}`).join('\n');
            }
        } catch { /* fall through to keyword search */ }
    }

    // Keyword fallback — use TTL cache
    const cached = cacheGet('memories');
    if (cached) return cached;

    const { data } = await supabase.from('memories').select('content');
    const result = (!data || data.length === 0)
        ? 'אין עדיין זיכרונות שמורים.'
        : data.map(m => `- ${m.content}`).join('\n');
    cacheSet('memories', result, TTL_MEMORIES);
    return result;
}

// ─── Full history search ──────────────────────────────────────────────────────

async function searchFullHistory(userMessage, supabaseClient) {
    try {
        const { data, error } = await supabaseClient
            .from('chat_history')
            .select('role, text, created_at')
            .order('created_at', { ascending: false })
            .limit(200);

        if (error || !data || data.length === 0) return null;

        const topicTokens = new Set(
            userMessage.toLowerCase().split(/[\s,.\-!?:;״׳]+/)
                .filter(t => t.length > 2 && !HE_STOP_SEARCH.has(t))
        );
        if (topicTokens.size === 0) return null;

        const relevant = data
            .map(row => {
                const tokens = (row.text || '').toLowerCase().split(/[\s,.\-!?:;״׳]+/)
                    .filter(t => t.length > 2 && !HE_STOP_SEARCH.has(t));
                return { ...row, score: tokens.filter(t => topicTokens.has(t)).length };
            })
            .filter(r => r.score > 0)
            .sort((a, b) => b.score - a.score)
            .slice(0, 5);

        if (relevant.length === 0) return null;

        const snippets = relevant.map(r => {
            const speaker = r.role === 'user' ? 'אתה' : 'Jarvis';
            const date = r.created_at
                ? new Date(r.created_at).toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' })
                : '';
            return `[${date}] ${speaker}: ${(r.text || '').slice(0, 150)}`;
        }).join('\n');

        return `--- שיחות קודמות רלוונטיות ---\n${snippets}\n-----------------------------------`;
    } catch (err) {
        console.error('searchFullHistory error:', err.message);
        return null;
    }
}

// ─── TTS ──────────────────────────────────────────────────────────────────────

function stripMarkdownForTTS(text) {
    return text
        .replace(/\*\*([^*]+)\*\*/g, '$1')
        .replace(/\*([^*]+)\*/g, '$1')
        .replace(/`([^`]+)`/g, '$1')
        .replace(/#{1,6}\s+/g, '')
        .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
        .replace(/^[-•*]\s+/gm, '')
        // Strip emoji — Unicode ranges for emoticons, symbols, and supplemental symbols.
        // eslint-disable-next-line no-misleading-character-class
        .replace(/[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}]/gu, '')
        .replace(/\n{2,}/g, '. ')
        .replace(/\n/g, ' ')
        .replace(/\s{2,}/g, ' ')
        .trim();
}

async function generateSpeech(text) {
    try {
        const cleaned = stripMarkdownForTTS(text);
        const results = await googleTTS.getAllAudioBase64(cleaned, {
            lang: 'iw',
            slow: false,
            host: 'https://translate.google.com',
            splitPunct: ',.?!:'
        });
        const buffers = results.map(res => Buffer.from(res.base64, 'base64'));
        return Buffer.concat(buffers).toString('base64');
    } catch (err) {
        console.error('❌ TTS Error:', err.message);
        return null;
    }
}

// ─── Whisper STT ──────────────────────────────────────────────────────────────

app.post('/transcribe', _rl(60), async (req, res) => {
    try {
        const { audio, format = 'wav' } = req.body;
        if (!audio) return res.status(400).json({ text: '', error: 'No audio provided' });

        const buffer = Buffer.from(audio, 'base64');
        const file = await toFile(buffer, `audio.${format}`, { type: `audio/${format}` });

        const transcription = await groqWhisper.audio.transcriptions.create({
            file,
            model: 'whisper-large-v3-turbo',
            language: 'he',
            response_format: 'json',
        });

        const text = (transcription.text || '').trim();
        console.log(`🎙️ Whisper: "${text.slice(0, 80)}"`);
        res.json({ text });
    } catch (err) {
        console.error('❌ Transcribe error:', err.message);
        res.status(500).json({ text: '', error: 'Transcription failed' });
    }
});

// ─── Custom Agent Loader ──────────────────────────────────────────────────────

const CUSTOM_REGISTRY = path.join(__dirname, 'agents', 'custom', 'registry.json');
const CUSTOM_AGENTS_DIR = path.resolve(__dirname, 'agents', 'custom');

async function tryCustomAgent(agentName, userMessage, supabase, useLocal, settings) {
    try {
        const registry = loadCustomRegistry(); // reuses router's 30 s in-memory cache
        const entry = registry.find(r => r.name === agentName);
        if (!entry) return null;

        const agentPath = path.resolve(entry.filePath);
        if (!agentPath.startsWith(CUSTOM_AGENTS_DIR + path.sep)) {
            console.error(`🚨 Path traversal blocked for agent "${agentName}": ${entry.filePath}`);
            return null;
        }
        // Clear require cache so hot-reload works after factory creates/updates an agent
        delete require.cache[agentPath];
        const mod = require(agentPath);

        const fnName = `run${agentName.charAt(0).toUpperCase() + agentName.slice(1)}`;
        if (typeof mod[fnName] !== 'function') {
            console.warn(`⚠️ Custom agent "${agentName}" missing export "${fnName}"`);
            return null;
        }

        console.log(`🤖 Custom agent: ${agentName}`);
        return await mod[fnName](userMessage, supabase, useLocal, settings);
    } catch (err) {
        console.error(`Custom agent "${agentName}" error:`, err.message);
        return null;
    }
}

// ─── Health check (for local connectivity testing) ───────────────────────────

app.get('/health', (req, res) => {
    res.json({ ok: true, version: 'multi-agent-v3', ts: Date.now(), pinecone: pinecone.isReady() });
});

// Diagnostic: probe each LLM/Search provider with a tiny live request and
// report which API keys are present and actually working. Open in a browser:
//   https://<server>/health/providers
// Each entry is one of: "ok" | "missing key" | "<error detail>".
app.get('/health/providers', async (req, res) => {
    const axios = require('axios');
    const out = {};

    const probe = async (name, present, fn) => {
        if (!present) { out[name] = 'missing key'; return; }
        try { await fn(); out[name] = 'ok'; }
        catch (e) {
            const status = e.response?.status;
            const detail = e.response?.data?.error?.message
                || e.response?.data?.error
                || e.message;
            out[name] = status ? `error ${status}: ${String(detail).slice(0, 120)}`
                               : String(detail).slice(0, 120);
        }
    };

    const tiny = [{ role: 'user', content: 'ping' }];

    await Promise.all([
        probe('groq', !!process.env.GROQ_API_KEY, () =>
            axios.post('https://api.groq.com/openai/v1/chat/completions',
                { model: 'llama-3.3-70b-versatile', messages: tiny, max_tokens: 1 },
                { headers: { Authorization: `Bearer ${process.env.GROQ_API_KEY}` }, timeout: 8000 })),
        probe('deepseek', !!process.env.DEEPSEEK_API_KEY, () =>
            axios.post('https://api.deepseek.com/chat/completions',
                { model: 'deepseek-chat', messages: tiny, max_tokens: 1 },
                { headers: { Authorization: `Bearer ${process.env.DEEPSEEK_API_KEY}` }, timeout: 10000 })),
        probe('gemini_google', !!process.env.GOOGLE_API_KEY, () =>
            axios.post(
                `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${process.env.GOOGLE_API_KEY}`,
                { contents: [{ role: 'user', parts: [{ text: 'ping' }] }], generationConfig: { maxOutputTokens: 1 } },
                { timeout: 12000 })),
    ]);

    // Manus: lightweight authenticated list request (avoids creating a real task)
    const manusBase = process.env.MANUS_BASE || 'https://api.manus.ai/v1';
    const manusAuthHeader = process.env.MANUS_AUTH_HEADER || 'API_KEY';
    await probe('manus', !!process.env.MANUS_API_KEY, () =>
        axios.get(`${manusBase}/tasks?limit=1`, {
            headers: { [manusAuthHeader]: process.env.MANUS_API_KEY },
            timeout: 8000,
        }));

    out.ollama = (process.env.OLLAMA_URL ? 'configured (local)' : 'not configured');
    res.json({ ts: Date.now(), providers: out });
});


async function getUserProfile() {
    const cached = cacheGet('userProfile');
    if (cached !== undefined) return cached;

    const { data, error } = await supabase
        .from('user_profiles')
        .select('*')
        .order('updated_at', { ascending: false })
        .limit(1);
    if (error) {
        console.error('user_profiles fetch error:', error.message);
        return readLocalProfile(); // don't cache transient DB errors
    }
    const dbProfile = Array.isArray(data) && data.length > 0 ? data[0] : null;
    const profile = dbProfile || readLocalProfile();
    cacheSet('userProfile', profile, TTL_USER_PROFILE);
    return profile;
}

// ─── Route ────────────────────────────────────────────────────────────────────

async function askJarvisHandler(req, res) {
    try {
        const originalMessage = req.body.command || '';
        let userMessage = originalMessage; // may be rewritten by reference resolution
        const imageBase64 = req.body.image;
        // Extract chat_id from request, or generate one if not provided
        const chatId = req.body.chatId || req.body.chat_id || `session-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

        if (userMessage.length > 5000) {
            return res.status(400).json({ answer: 'ההודעה ארוכה מדי. נסה בקצר יותר.', chatId });
        }

        console.log(`\n--- Incoming: "${userMessage.slice(0, 60)}" | Image: ${!!imageBase64} | Chat: ${chatId.slice(0, 20)} ---`);
        const t0 = Date.now();

        const settings  = req.body.settings || {};
        const userProfile = await getUserProfile();
        settings.userProfile = userProfile;
        const useLocal  = settings.useLocalModel === true;

        // ── Optional PDF/document context ─────────────────────────────────────
        // When a PDF is attached, extract its text and fold it into the message
        // sent to the agent (history still stores only the user's typed text).
        let documentContext = '';
        const pdfBase64 = req.body.pdf || req.body.document;
        if (pdfBase64) {
            const doc = await documentParser.extractPdfText(pdfBase64);
            if (doc.ok) {
                documentContext = doc.text;
                const truncNote = doc.truncated ? ' (קוצר מפאת אורך)' : '';
                const ask = userMessage.trim() || 'סכם את המסמך בנקודות עיקריות.';
                userMessage = `המשתמש צירף מסמך PDF${truncNote}. תוכן המסמך:\n"""\n${doc.text}\n"""\n\nבהתבסס על המסמך בלבד, ${ask}`;
                console.log(`📄 PDF attached: ${doc.pages || '?'} pages, ${doc.text.length} chars${truncNote}`);
                feedbackStore.recordEvent(supabase, {
                    eventName: 'document_query',
                    value: 1,
                    metadata: { chatId: String(chatId), chars: doc.text.length, pages: doc.pages },
                }).catch(() => {});
            } else {
                return res.json({
                    answer: 'לא הצלחתי לקרוא את המסמך. ודא שמדובר בקובץ PDF תקין שאינו מוגן בסיסמה.',
                    audio: null, action: null, chatId,
                });
            }
        }

        // ── Confirmation checks (before routing) ──────────────────────────────
        for (const confirmFn of [handleConfirmation, handleTaskReminderConfirmation]) {
            const confirmResult = await confirmFn(userMessage);
            if (confirmResult) {
                const answer = confirmResult.answer;
                await Promise.all([
                    saveChatMessage('user', userMessage, chatId),
                    saveChatMessage('jarvis', answer, chatId),
                ]);
                cacheInvalidate(`chatHistory:${chatId}`);
                return res.json({ answer, audio: null, action: null, chatId });
            }
        }

        // ── Contextual reference resolution (cheap sync gate first) ───────────
        // Rewrite short follow-ups with anaphora ("תזכיר לי על זה") into a
        // self-contained message so specialist agents can act on them. The
        // ORIGINAL message is still what gets saved to history (see below).
        if (!imageBase64 && !documentContext && contextResolver.shouldResolve(userMessage)) {
            const [resHistory, resSummary] = await Promise.all([
                loadChatHistory(chatId),
                conversationSummary.getSummary(chatId, supabase),
            ]);
            const { resolved, didResolve } = await contextResolver.resolveReferences(userMessage, resHistory, resSummary);
            if (didResolve) {
                userMessage = resolved;
                console.log(`🧩 Resolved: "${originalMessage.slice(0, 30)}" → "${userMessage.slice(0, 40)}"`);
            }
        }

        // ── Routing ───────────────────────────────────────────────────────────
        // Clients may force a specific intent to skip keyword/LLM classification
        // (e.g. the home-screen "insight" card asks an open question that must
        // be treated as plain chat, not routed to the analytics insight agent).
        const FORCEABLE_INTENTS = ['chat', 'weather', 'news', 'stocks', 'sports', 'translate'];
        const forcedIntent = typeof req.body.intent === 'string' ? req.body.intent.trim() : '';

        let intentMode = 'fast';
        let agentName;
        if (FORCEABLE_INTENTS.includes(forcedIntent)) {
            agentName = forcedIntent;
            intentMode = 'forced';
        } else if (imageBase64 || documentContext) {
            agentName = 'chat';
        } else {
            const routed = classifyIntentDetailed(userMessage);
            agentName = routed.intent;

            if (routed.ambiguous) {
                // Collision: several keyword intents matched. Disambiguate with
                // the LLM, but only trust it if it picks one of the candidates —
                // otherwise keep the first keyword match as the best guess.
                const llmIntent = await classifyIntentWithLLM(userMessage);
                if (routed.matches.includes(llmIntent)) agentName = llmIntent;
                intentMode = 'llm';

                // Telemetry: record only ambiguous routing decisions.
                feedbackStore.recordEvent(supabase, {
                    eventName: 'route_ambiguous',
                    value: 1,
                    metadata: {
                        chatId: String(chatId),
                        snippet: String(userMessage).slice(0, 200),
                        candidates: routed.matches,
                        llm: llmIntent,
                        chosen: agentName,
                    },
                }).catch(() => {});
            } else if (agentName === 'chat' && userMessage.trim().length > 12) {
                agentName = await classifyIntentWithLLM(userMessage);
                intentMode = 'llm';
            }
        }

        // Guard: if LLM or keyword classified as manus but Manus is not configured, fall back to chat
        if (agentName === 'manus' && !isManusConfigured()) {
            console.log('⚠️ Manus intent but MANUS_API_KEY not set — falling back to chat');
            agentName = 'chat';
        }

        // Follow-up override: if the user is continuing a previous conversation,
        // route to chat even if keywords matched a specialized agent.
        // Actionable agents (task/reminder/notes) are intentionally excluded:
        // "הוסף משימה" must always execute, never get re-routed to chat where
        // it would only be discussed instead of performed.
        const CONTEXT_OVERRIDE_AGENTS = ['sports', 'weather', 'news', 'security', 'e2e'];
        if (CONTEXT_OVERRIDE_AGENTS.includes(agentName)) {
            const tempHistory = await loadChatHistory(chatId); // uses TTL cache — cheap
            if (detectFollowUp(userMessage, tempHistory)) {
                console.log(`🔄 Follow-up override: "${agentName}" → "chat"`);
                agentName = 'chat';
            }
        }

        // ── past_conv → remap to chat (history injection handled below) ─────
        if (agentName === 'past_conv') {
            agentName = 'chat';
            console.log('🔍 Past-conv: remapped to chat');
        }

        // Remember the resolved route so explicit feedback can be linked to it.
        routeTracker.setLastRoute(chatId, { intent: agentName, mode: intentMode });

        // ── Mid-session mood adaptation: 3+ consecutive short replies → concise ─
        // "Short" = under 10 chars. Resets when user sends a long message.
        if (!settings.voiceMode && agentName === 'chat') {
            const _shortMsgKey = `shortMsgCount:${chatId}`;
            let shortCount = (_sessionState.get(_shortMsgKey) || 0);
            if (userMessage.trim().length < 10) {
                shortCount++;
            } else {
                shortCount = 0;
            }
            _sessionState.set(_shortMsgKey, shortCount);
            if (shortCount >= 3 && settings.responseLength !== 'short') {
                settings.responseLength = 'short';
                console.log(`⚡ Mood adapt: ${shortCount} short msgs → concise mode`);
            }
        }

        console.log(`🎯 Dispatching to: ${agentName} (+${Date.now() - t0}ms)`);
        const tRoute = Date.now();

        // ── Lazy DB load: history only for chat/draft; memories always (cached) ─
        const needsHistory = ['chat', 'draft'].includes(agentName);
        let chatHistory = [], longTermMemories = '';
        if (needsHistory) {
            [chatHistory, longTermMemories] = await Promise.all([
                loadChatHistory(chatId),
                // Pass userMessage for Pinecone semantic search; falls back to keyword filter
                fetchLongTermMemories(userMessage)
            ]);
            // When Pinecone returned the top-K relevant memories, keep as-is.
            // Otherwise rank with embeddings if available, fall back to token ranking.
            if (!pinecone.isReady()) {
                longTermMemories = filterRelevantMemories(longTermMemories, userMessage);
            } else {
                longTermMemories = await filterRelevantMemoriesAsync(longTermMemories, userMessage);
            }
            // Inject rolling conversation summary so agent remembers context beyond 20 msgs.
            // Cap at 1500 chars (~500 tokens) so a long summary can't flood the context.
            if (agentName === 'chat') {
                const raw = await conversationSummary.getSummary(chatId, supabase);
                settings.chatSummary = raw && raw.length > 1500 ? raw.slice(0, 1500) + '…' : raw;
            }
        } else {
            // All other agents get raw memories (TTL-cached — cheap)
            longTermMemories = await fetchLongTermMemories();
        }

        // Inject user context so every agent can personalize its response
        settings.userMemories = longTermMemories
            ? longTermMemories.slice(0, 500)
            : '';
        const tDb = Date.now();

        // ── Past-conv: inject relevant history snippets beyond last 20 msgs ──
        if (agentName === 'chat' && PAST_CONV_PATTERN.test(userMessage)) {
            const historySnippet = await searchFullHistory(userMessage, supabase);
            if (historySnippet) {
                longTermMemories = longTermMemories + '\n\n' + historySnippet;
                console.log('🔍 Past-conv context injected');
            }
        }

        // ── Dispatch ──────────────────────────────────────────────────────────
        // Wrap the dispatch in a provider-tracking context so models.js can
        // record which LLM (groq/deepseek/openrouter/gemini/ollama) actually
        // answered AND so per-request opts (cloudProvider, temperature, local
        // url/model from the mobile app's settings) propagate to all ~44
        // callGemma4 sites without editing any agent file. Read back via
        // getCurrentProvider() and surface to the client.
        let result;
        let llmProvider = null;
        const providerOpts = {
            cloudProvider:   settings.cloudProvider,
            openrouterModel: settings.openrouterModel,
            temperature:     settings.temperature,
            localServerUrl:  settings.localServerUrl,
            localModelName:  settings.localModelName,
        };
        await providerContext.run({ opts: providerOpts }, async () => {
        // Build the per-request context once. The dispatcher's per-entry
        // adapters destructure what each agent actually needs.
        const ctx = {
            userMessage, supabase, useLocal, settings,
            chatHistory, longTermMemories, imageBase64,
            sendEmail, chatId,
        };
        const entry = dispatcher.getEntry(agentName);

        if (isAgentDisabled(agentName)) {
            console.log(`⛔ Agent "${agentName}" is disabled — skipping dispatch`);
            result = { ...AGENT_DISABLED_REPLY };
        } else if (entry && entry.mode === 'background') {
            // Background entries (code_error, e2e): return placeholder immediately,
            // run the real agent via setImmediate, persist its answer to chat history
            // when done. Keep the closure-over-chatId pattern explicit here.
            const bgChatId = chatId;
            const label = agentName;
            setImmediate(async () => {
                try {
                    const r = await entry.invoke(ctx, AGENTS);
                    await saveChatMessage('jarvis', r.answer, bgChatId);
                    cacheInvalidate(`chatHistory:${bgChatId}`);
                    console.log(`🪐 background ${label} saved to chat history`);
                } catch (err) {
                    console.error(`🪐 background ${label} failed:`, err.message);
                    await saveChatMessage('jarvis', `❌ ${label} נכשל: ${err.message}`, bgChatId).catch(() => {});
                    cacheInvalidate(`chatHistory:${bgChatId}`);
                }
            });
            result = { answer: entry.placeholder, skipTts: true };
        } else if (entry) {
            // Sync entry — single line replaces the old per-intent if/else.
            result = await dispatcher.dispatch(agentName, ctx, AGENTS);
            if (entry.cacheBust) cacheInvalidate(entry.cacheBust);
        } else {
            // ── Orchestrator: handle multi-intent requests before chat fallback ─
            if (!imageBase64 && userMessage.length > 15) {
                try {
                    const orchResult = await runOrchestratorAgent(userMessage, supabase, useLocal, settings, chatHistory, longTermMemories);
                    if (orchResult) {
                        result = orchResult;
                        console.log('🎭 Orchestrator handled multi-intent request');
                    }
                } catch (orchErr) {
                    console.error('⚠️ Orchestrator error:', orchErr.message);
                }
            }

            if (!result) {
                // Try a dynamically-created custom agent, fall back to chat
                result = await tryCustomAgent(agentName, userMessage, supabase, useLocal, settings)
                      || await runChatAgent(userMessage, imageBase64, chatHistory, longTermMemories, settings);
            }

            // ── Capability gap detection (chat fallback only) ─────────────────
            if (!imageBase64) {
                try {
                    const gap = await detectCapabilityGap(userMessage, result.answer);
                    if (gap.isGap) {
                        await savePendingGap({ userRequest: userMessage, gapDetails: gap });
                        result = {
                            ...result,
                            answer: result.answer + '\n\nהאם תרצה שאוסיף זאת כמשימת פיתוח? (כן / לא)',
                        };
                        console.log(`🔧 Capability gap detected: "${gap.capabilityTitle}"`);
                    }
                } catch (gapErr) {
                    console.error('⚠️ Capability gap detection error:', gapErr.message);
                }
            }
        }
        });
        llmProvider = getCurrentProvider();
        const tAgent = Date.now();
        agentMetrics.record(agentName, tAgent - tRoute, intentMode);

        // ── Task auto-reminder: save pending state when task has due date ──────
        if (agentName === 'task' && result.pendingAction?.type === 'auto_reminder') {
            await saveTaskReminderPending(result.pendingAction).catch(() => {});
        }

        let answer = result.answer || 'לא הצלחתי לגבש תשובה.';
        const action = result.action || null;
        const suggestions = Array.isArray(result.suggestions) ? result.suggestions : [];

        // ── Proactive inline nudge (text chat only, hard-throttled) ───────────
        // Skip in voice mode (markdown/emoji would be spoken), when the user is
        // mid-flow (action/pendingAction), or when the reply ends in a question.
        if (agentName === 'chat' && !imageBase64 && !settings.voiceMode && !action
            && !result.pendingAction && !/[?？]\s*$/.test(answer)
            && proactiveEngine.shouldNudgeInline(chatId)) {
            let nudgeTimer;
            try {
                const sug = await Promise.race([
                    proactiveEngine.computeProactiveSuggestion(supabase),
                    new Promise(resolve => { nudgeTimer = setTimeout(() => resolve(null), 400); }),
                ]);
                if (sug) {
                    answer += `\n\n💡 ${sug.message}`;
                    proactiveEngine.markNudged(chatId);
                }
            } catch (_) { /* never block the reply on a nudge */ }
            finally { clearTimeout(nudgeTimer); }
        }

        // ── Parallel: save history + TTS ──────────────────────────────────────
        // Long-running agents (e.g. e2e in background) set skipTts to short-circuit
        // the response and avoid the client-side timeout.
        const ttsEnabled = settings.ttsEnabled !== false && !result.skipTts;
        const [,, audioBase64] = await Promise.all([
            saveChatMessage('user', originalMessage, chatId),
            saveChatMessage('jarvis', answer, chatId),
            ttsEnabled ? generateSpeech(answer) : Promise.resolve(null),
        ]);
        cacheInvalidate(`chatHistory:${chatId}`); // history just updated
        const tDone = Date.now();

        console.log(
            `⏱️ total=${tDone - t0}ms` +
            ` | route=${tRoute - t0}ms` +
            (needsHistory ? ` | db=${tDb - tRoute}ms` : ' | db=skipped') +
            ` | agent=${tAgent - tDb}ms` +
            ` | save+tts=${tDone - tAgent}ms` +
            ` | agent=${agentName}`
        );

        // For WhatsApp — pass action to Flutter to open deep link
        // Return chatId so client can use it for subsequent messages
        res.json({ answer, audio: audioBase64, action, chatId, suggestions, provider: llmProvider });

        // ── Fire-and-forget: passive memory extraction + summary update ────────
        if (agentName === 'chat' && !imageBase64) {
            setImmediate(() => {
                autoExtractMemory(originalMessage, answer, supabase, settings).catch(() => {});
                // Reload fresh history (cache was just invalidated) for summary
                loadChatHistory(chatId).then(freshHistory => {
                    conversationSummary.updateSummaryIfNeeded(chatId, freshHistory, supabase, settings).catch(() => {});
                }).catch(() => {});
            });
        }

    } catch (err) {
        if (err instanceof LocalModelError) {
            // Strict-local mode: the user enabled "מודל מקומי" but it's not
            // reachable. Show a clear Hebrew message instead of hanging.
            console.warn('🔌 Local model unavailable:', err.url, err.model, err.message);
            return res.status(200).json({
                answer: `⚠️ המודל המקומי (${err.model || 'לא ידוע'}) לא זמין בכתובת ${err.url || 'לא מוגדרת'}. ודא ש-Ollama רץ ונגיש מהטלפון, או כבה "מודל מקומי" בהגדרות.`,
                skipTts: true,
                provider: 'ollama',
            });
        }
        console.error('Route Error:', err.message);
        const isRateLimit = err.response?.status === 429 || /429|rate.limit|quota/i.test(err.message);
        res.status(200).json({
            answer: isRateLimit
                ? '⏳ כל ספקי ה-AI עמוסים כרגע (מגבלת קצב). נסה שוב בעוד כמה דקות.'
                : 'שגיאת מערכת פנימית.',
            skipTts: true,
        });
    }
}

// ─── Send Email (called after user confirms in Flutter) ───────────────────────

app.post('/send-email', requirePolicy('messaging.send', { sensitive: true, irreversible: true }), async (req, res) => {
    const { to, message } = req.body;
    if (!to || !message) return res.status(400).json({ ok: false, error: 'Missing to/message' });
    try {
        await sendEmail(to, message);
        res.json({ ok: true });
    } catch (err) {
        console.error('📧 Email send error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
    }
});

// ─── Delete chat history for a conversation ───────────────────────────────────
app.delete('/chat-history/:chatId', async (req, res) => {
    try {
        const { chatId } = req.params;
        if (!chatId) return res.status(400).json({ error: 'chatId required' });

        const { error } = await supabase
            .from('chat_history')
            .delete()
            .eq('chat_id', chatId);

        if (error) throw error;
        cacheInvalidate(`chatHistory:${chatId}`);
        res.json({ success: true, deletedChatId: chatId });
    } catch (err) {
        console.error('⚠️ DELETE /chat-history error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── User Profile (Learning) ───────────────────────────────────────────────
app.get('/user-profile', async (_req, res) => {
    try {
        const profile = await getUserProfile();
        res.json({ profile });
    } catch (err) {
        res.status(500).json({ error: 'Internal server error', profile: null });
    }
});

app.post('/user-profile', async (req, res) => {
    try {
        const rawBody = req.body || {};

        const sanitizeList = (v, max = 20) => Array.isArray(v)
            ? v.map(x => String(x).trim()).filter(Boolean).slice(0, max)
            : [];

        const existing = await getUserProfile();

        // Track which fields the user explicitly set, so auto-learning never
        // overwrites them. Accumulated across saves (a field stays user-owned
        // once touched).
        const existingAuto = (existing && typeof existing.auto_learned === 'object' && existing.auto_learned) || {};
        const userOverridden = new Set(Array.isArray(existingAuto.user_overridden) ? existingAuto.user_overridden : []);

        // Only update fields that are explicitly present in the request body
        // (partial update). This lets settings_screen sync only identity fields
        // without wiping the learned profile fields, and vice-versa.
        const payload = { updated_at: new Date().toISOString() };

        if ('speaking_tone' in rawBody) {
            const v = String(rawBody.speaking_tone || 'friendly').trim();
            if (v) userOverridden.add('speaking_tone');
            payload.speaking_tone = v.slice(0, 40) || 'friendly';
        }
        if ('preferred_hours' in rawBody) {
            if (Array.isArray(rawBody.preferred_hours) && rawBody.preferred_hours.length > 0) userOverridden.add('preferred_hours');
            payload.preferred_hours = sanitizeList(rawBody.preferred_hours, 8);
        }
        if ('interests' in rawBody) {
            if (Array.isArray(rawBody.interests) && rawBody.interests.length > 0) userOverridden.add('interests');
            payload.interests = sanitizeList(rawBody.interests, 20);
        }
        if ('recurring_tasks' in rawBody) {
            if (Array.isArray(rawBody.recurring_tasks) && rawBody.recurring_tasks.length > 0) userOverridden.add('recurring_tasks');
            payload.recurring_tasks = sanitizeList(rawBody.recurring_tasks, 20);
        }

        // Identity fields — synced from the mobile settings screen so they
        // survive device reinstalls and device switches.
        const VALID_GENDERS      = ['male', 'female'];
        const VALID_PERSONALITIES = ['friendly', 'formal', 'concise', 'humorous'];
        if ('user_name' in rawBody && rawBody.user_name) {
            payload.user_name = String(rawBody.user_name).trim().slice(0, 50);
            userOverridden.add('user_name');
        }
        if ('assistant_name' in rawBody && rawBody.assistant_name) {
            payload.assistant_name = String(rawBody.assistant_name).trim().slice(0, 50);
            userOverridden.add('assistant_name');
        }
        if ('gender' in rawBody && VALID_GENDERS.includes(rawBody.gender)) {
            payload.gender = rawBody.gender;
            userOverridden.add('gender');
        }
        if ('personality' in rawBody && VALID_PERSONALITIES.includes(rawBody.personality)) {
            payload.personality = rawBody.personality;
            userOverridden.add('personality');
        }

        payload.auto_learned = { ...existingAuto, user_overridden: Array.from(userOverridden) };

        let result;
        if (existing?.id) {
            result = await supabase
                .from('user_profiles')
                .update(payload)
                .eq('id', existing.id)
                .select()
                .single();
        } else {
            result = await supabase
                .from('user_profiles')
                .insert([payload])
                .select()
                .single();
        }
        if (result.error) {
            console.error('user_profiles save error:', result.error.message);
            const localProfile = { id: 'local-fallback', ...payload };
            writeLocalProfile(localProfile);
            cacheInvalidate('userProfile');
            return res.json({ success: true, profile: localProfile, fallback: true });
        }
        writeLocalProfile(result.data);
        cacheInvalidate('userProfile');
        res.json({ success: true, profile: result.data });
    } catch (err) {
        const msg = String(err.message || '');
        if (msg.includes('relation') && msg.includes('user_profiles')) {
            return res.status(500).json({
                error: 'טבלת user_profiles חסרה. יש להריץ migration ואז לנסות שוב.',
            });
        }
        res.status(500).json({ error: msg });
    }
});

app.delete('/user-profile', async (_req, res) => {
    try {
        const existing = await getUserProfile();
        if (!existing?.id || existing.id === 'local-fallback') {
            deleteLocalProfile();
            cacheInvalidate('userProfile');
            return res.json({ success: true, deleted: true, fallback: true });
        }
        const { error } = await supabase.from('user_profiles').delete().eq('id', existing.id);
        if (error) {
            console.error('user_profiles delete error:', error.message);
            deleteLocalProfile();
            cacheInvalidate('userProfile');
            return res.json({ success: true, deleted: true, fallback: true });
        }
        deleteLocalProfile();
        cacheInvalidate('userProfile');
        res.json({ success: true, deleted: true });
    } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Live DB Stats ────────────────────────────────────────────────────────

app.get('/stats', async (_req, res) => {
    const todayStart = new Date();
    todayStart.setUTCHours(0, 0, 0, 0);
    const todayISO = todayStart.toISOString();

    const [
        chatTotal, chatToday,
        tasksTotal, tasksDone,
        remindersTotal, remindersActive,
        memoriesTotal,
        notesTotal,
        shoppingTotal, shoppingChecked,
        pendingCategories,
    ] = await Promise.allSettled([
        supabase.from('chat_history').select('id', { count: 'exact', head: true }),
        supabase.from('chat_history').select('id', { count: 'exact', head: true }).gte('created_at', todayISO),
        supabase.from('tasks').select('id', { count: 'exact', head: true }),
        supabase.from('tasks').select('id', { count: 'exact', head: true }).eq('done', true),
        supabase.from('reminders').select('id', { count: 'exact', head: true }),
        supabase.from('reminders').select('id', { count: 'exact', head: true }).eq('fired', false),
        supabase.from('memories').select('id', { count: 'exact', head: true }),
        supabase.from('notes').select('id', { count: 'exact', head: true }),
        supabase.from('shopping_items').select('id', { count: 'exact', head: true }),
        supabase.from('shopping_items').select('id', { count: 'exact', head: true }).eq('checked', true),
        supabase.from('tasks').select('category').eq('done', false),
    ]);

    const getCount = (result) => {
        if (result.status === 'fulfilled' && !result.value.error) return result.value.count ?? 0;
        return 0;
    };

    // Pending-task breakdown by category (counted in JS; gracefully empty if the
    // `category` column doesn't exist or the query failed).
    const byCategory = { work: 0, personal: 0, financial: 0, project: 0, general: 0 };
    if (pendingCategories.status === 'fulfilled' && !pendingCategories.value.error) {
        for (const row of pendingCategories.value.data || []) {
            const c = byCategory[row.category] !== undefined ? row.category : 'general';
            byCategory[c]++;
        }
    }

    res.json({
        chat:      { total: getCount(chatTotal),      today:   getCount(chatToday) },
        tasks:     { total: getCount(tasksTotal),     done:    getCount(tasksDone),    pending: getCount(tasksTotal) - getCount(tasksDone), byCategory },
        reminders: { total: getCount(remindersTotal), active:  getCount(remindersActive) },
        memories:  { total: getCount(memoriesTotal) },
        notes:     { total: getCount(notesTotal) },
        shopping:  { total: getCount(shoppingTotal),  checked: getCount(shoppingChecked) },
    });
});

// ─── GET /day-plan — Smart Day Engine: scored, prioritized, load-aware plan ──
app.get('/day-plan', async (req, res) => {
    try {
        const now = new Date();
        const settings = { userName: req.query.userName || 'נדב' };

        // 1. Fetch pending tasks (all, so undated backlog is scored too),
        //    active reminders, and recent chat timestamps for peak detection.
        const [tasksRes, remindersRes, chatsRes] = await Promise.all([
            supabase.from('tasks')
                .select('id, content, done, due_date, priority, created_at')
                .eq('done', false),
            supabase.from('reminders')
                .select('id, text, scheduled_time, fired, recurrence')
                .eq('fired', false),
            supabase.from('chat_history')
                .select('role, text, created_at')
                .order('created_at', { ascending: false })
                .limit(200),
        ]);

        // 2. Normalize into engine items.
        const taskItems = (tasksRes.data || []).map(t => ({
            id: `task-${t.id}`, sourceId: t.id, type: 'task',
            title: t.content, priority: t.priority || 'medium',
            due_date: t.due_date, created_at: t.created_at,
        }));
        const reminderItems = (remindersRes.data || []).map(r => ({
            id: `reminder-${r.id}`, sourceId: r.id, type: 'reminder',
            title: r.text, scheduled_time: r.scheduled_time, recurrence: r.recurrence,
        }));
        const items = [...taskItems, ...reminderItems];

        // 3. Deterministic scoring + load + conflicts (priorityEngine).
        const plan = priorityEngine.buildDayPlan(items, now);

        // 4. On-the-fly pattern analysis → AI narrative (graceful degrade).
        const patterns = analyzePatterns({
            chats:     chatsRes.data || [],
            tasks:     tasksRes.data || [],
            memories:  [],
            reminders: remindersRes.data || [],
            contacts:  [],
        });
        const ai = await optimizeDayPlan(plan.items, patterns, plan.load, settings);

        res.json({
            generated_at: now.toISOString(),
            peak_window:  ai.peak_window,
            load:         plan.load,
            quadrants:    plan.quadrants,
            items:        plan.items,
            conflicts:    plan.conflicts,
            narrative:    ai.narrative,
            ai_available: ai.ai_available,
        });
    } catch (err) {
        console.error('GET /day-plan error:', err.message);
        res.status(500).json({
            generated_at: new Date().toISOString(),
            peak_window: null,
            load: { ratio: 0, status: 'empty', mustDoMinutes: 0, capacityMinutes: 0 },
            quadrants: { now: [], plan: [], quick: [], later: [] },
            items: [], conflicts: [], narrative: '', ai_available: false,
        });
    }
});

// ─── POST /insight-card — proactive home-screen insight, server-cached ────────
// The home screen used to drive this through /ask-jarvis (full chat agent, which
// also injects 20 history messages + memories) on a 60s timer — burning tokens.
// This dedicated endpoint calls the model directly with the self-contained prompt
// and caches the result per user+mode, so repeat loads are free. `fresh:true`
// bypasses the cache for an explicit manual refresh.
const TTL_INSIGHT_CARD = 3 * 60 * 60 * 1000; // 3 h — insight only meaningfully changes every few hours
app.post('/insight-card', _rl(30), async (req, res) => {
    try {
        const { prompt, mode, fresh, userId } = req.body || {};
        if (!prompt || typeof prompt !== 'string') {
            return res.status(400).json({ error: 'prompt required' });
        }

        const cacheKey = `insight:${userId || 'default'}:${mode || 'auto'}`;
        if (!fresh) {
            const cached = cacheGet(cacheKey);
            if (cached) return res.json({ answer: cached, cached: true });
        }

        const { callGemma4 } = require('./agents/models');
        const answer = ((await callGemma4(prompt, false, 500)) || '').trim();
        if (answer) cacheSet(cacheKey, answer, TTL_INSIGHT_CARD);
        res.json({ answer, cached: false });
    } catch (err) {
        console.error('POST /insight-card error:', err.message);
        res.status(500).json({ error: 'insight failed' });
    }
});

// ─── Feedback & Telemetry — foundation of the self-improvement loop ──────────
// Records explicit user feedback (👍/👎 + optional correction) and arbitrary
// telemetry events into `smart_telemetry_events`. These signals are aggregated
// deterministically by the daily profile learner (later phase) — no per-message
// LLM cost. An in-memory dedup guard prevents repeated taps from multi-counting.

const _feedbackDedup = new Map(); // `${chatId}:${hash}` → expiresAt
const FEEDBACK_DEDUP_TTL = 10_000;
function _feedbackSeenRecently(key) {
    const now = Date.now();
    const exp = _feedbackDedup.get(key);
    if (exp && now < exp) return true;
    _feedbackDedup.set(key, now + FEEDBACK_DEDUP_TTL);
    if (_feedbackDedup.size > 500) {
        for (const [k, e] of _feedbackDedup) { if (now > e) _feedbackDedup.delete(k); }
    }
    return false;
}

app.post('/feedback', _rl(30), async (req, res) => {
    try {
        const { chatId = 'default-session', messageText = '', signal, correction, source = 'chat', userId } = req.body || {};
        if (signal !== 'up' && signal !== 'down') {
            return res.status(400).json({ error: "signal must be 'up' or 'down'" });
        }
        const snippet = String(messageText).slice(0, 300);
        const dedupKey = `${chatId}:${signal}:${snippet.slice(0, 80)}`;
        if (_feedbackSeenRecently(dedupKey)) return res.json({ ok: true, deduped: true });

        const metadata = { chatId: String(chatId), snippet, source };
        if (typeof correction === 'string' && correction.trim()) metadata.correction = correction.trim().slice(0, 300);
        // Link the feedback to the intent that produced the reply, so systematic
        // mis-routes become visible in analysis (null if the route has expired).
        const lastRoute = routeTracker.getLastRoute(chatId);
        if (lastRoute && lastRoute.intent) metadata.routedIntent = lastRoute.intent;

        feedbackStore.recordEvent(supabase, {
            userId: userId || 'default',
            eventName: signal === 'up' ? 'feedback_up' : 'feedback_down',
            value: feedbackStore.SIGNAL_VALUE[signal],
            metadata,
        }).catch(() => {});
        // A correction is a strong learning signal — log it separately too.
        if (metadata.correction) {
            feedbackStore.recordEvent(supabase, {
                userId: userId || 'default',
                eventName: 'feedback_correction',
                value: -1,
                metadata,
            }).catch(() => {});
        }
        res.json({ ok: true });
    } catch (err) {
        console.error('POST /feedback error:', err.message);
        res.status(500).json({ error: 'feedback failed' });
    }
});

// Generic telemetry sink the Flutter app already calls (was previously a silent
// 404). POST records an event; GET returns deterministic aggregates.
app.post('/dashboard/smart-telemetry', _rl(60), async (req, res) => {
    try {
        const { event_type, event_name, payload, value, user_id } = req.body || {};
        const name = event_name || event_type;
        if (!name) return res.status(400).json({ error: 'event_type required' });
        const r = await feedbackStore.recordEvent(supabase, {
            userId: user_id || 'default',
            eventName: name,
            value: Number.isFinite(value) ? value : 1,
            metadata: (payload && typeof payload === 'object') ? payload : {},
        });
        res.json({ ok: r.ok });
    } catch (err) {
        console.error('POST /dashboard/smart-telemetry error:', err.message);
        res.status(500).json({ error: 'telemetry failed' });
    }
});

app.get('/dashboard/smart-telemetry', _rl(60), async (req, res) => {
    const r = await feedbackStore.aggregateEvents(supabase, {
        userId: req.query.user_id || 'default',
        sinceDays: Math.min(Number(req.query.days) || 30, 90),
    });
    res.json({ counts: r.counts, total: r.total });
});

// ─── Today Message — personalized AI morning/motivation card ──────────────────

app.get('/today-message', async (_req, res) => {
    try {
        const now = new Date();
        const todayStart     = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
        const yesterdayStart = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);

        const [pendingRes, doneYesterdayRes, totalYesterdayRes, remindersRes] = await Promise.all([
            supabase.from('tasks').select('id', { count: 'exact', head: true }).eq('done', false),
            supabase.from('tasks').select('id', { count: 'exact', head: true })
                .eq('done', true)
                .gte('created_at', yesterdayStart.toISOString())
                .lt('created_at', todayStart.toISOString()),
            supabase.from('tasks').select('id', { count: 'exact', head: true })
                .gte('created_at', yesterdayStart.toISOString())
                .lt('created_at', todayStart.toISOString()),
            supabase.from('reminders').select('id', { count: 'exact', head: true }).eq('fired', false),
        ]);

        const pending        = pendingRes.count       ?? 0;
        const doneYesterday  = doneYesterdayRes.count ?? 0;
        const totalYesterday = totalYesterdayRes.count ?? 0;
        const reminders      = remindersRes.count     ?? 0;
        const yesterdayPct   = totalYesterday > 0 ? Math.round(doneYesterday / totalYesterday * 100) : null;

        const hour = (now.getUTCHours() + 3) % 24; // Jerusalem time
        const timeOfDay = hour >= 5 && hour < 12 ? 'בוקר טוב'
                        : hour >= 12 && hour < 17 ? 'צהריים טובים'
                        : hour >= 17 && hour < 21 ? 'ערב טוב'
                        : 'לילה טוב';

        const yesterdayNote = yesterdayPct !== null
            ? ` אתמול השלמת ${yesterdayPct}% מהמשימות — ${yesterdayPct >= 70 ? 'כל הכבוד' : 'אל תתייאש'}!`
            : '';

        const prompt = `אתה ג'ארביס, עוזר אישי חם ומעודד. כתוב הודעה קצרה ואישית (2 משפטים) בעברית.
זמן: ${timeOfDay}. יש ${pending} משימות ממתינות ו-${reminders} תזכורות פעילות.${yesterdayNote}
החזר JSON בלבד: {"message":"הטקסט כאן","emoji":"אמוג'י אחד מתאים"}`;

        const raw = await callGemma4(prompt, false, 200);

        let message = `${timeOfDay}! יש לך ${pending} משימות ממתינות היום.`;
        let emoji   = '☀️';

        try {
            const start = raw.indexOf('{');
            const end   = raw.lastIndexOf('}');
            if (start !== -1 && end !== -1) {
                const parsed = JSON.parse(raw.substring(start, end + 1));
                if (parsed.message) message = parsed.message;
                if (parsed.emoji)   emoji   = parsed.emoji;
            }
        } catch (_) {}

        res.json({ message, emoji });
    } catch (err) {
        console.error('GET /today-message error:', err.message);
        res.json({ message: 'שלום! יש לך משימות ממתינות היום.', emoji: '☀️' });
    }
});

// ─── Check Reminders (polled by Flutter) ──────────────────────────────────────

// ─── Morning Briefing endpoint ────────────────────────────────────────────────
app.get('/morning-briefing', async (_req, res) => {
    try {
        const nowJer = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
        const todayISO = `${nowJer.getFullYear()}-${String(nowJer.getMonth()+1).padStart(2,'0')}-${String(nowJer.getDate()).padStart(2,'0')}`;

        // Try cached briefing first
        try {
            const { data } = await supabase.from('daily_briefings').select('content').eq('date', todayISO).single();
            if (data?.content) return res.json({ briefing: data.content, cached: true, date: todayISO });
        } catch { /* table may not exist or no row */ }

        // Generate fresh
        const briefing = await buildMorningBriefing();
        res.json({ briefing, cached: false, date: todayISO });
    } catch (err) {
        console.error('GET /morning-briefing error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Dashboard Context ────────────────────────────────────────────────────────

const TTL_DASHBOARD_WEATHER = 2 * 60 * 60 * 1000; // 2 h — weather changes slowly; long TTL cuts LLM calls
const TTL_DASHBOARD_NEWS    = 60 * 60 * 1000;     // 1 h — headlines stay relevant for an hour
const TTL_DASHBOARD_HERO    =  5 * 60 * 1000;     // 5 min

function _getDashboardTimeSlot(dateJer) {
    const h = dateJer.getHours();
    if (h >= 6  && h < 9)  return 'morning';
    if (h >= 9  && h < 12) return 'late_morning';
    if (h >= 12 && h < 14) return 'noon';
    if (h >= 14 && h < 18) return 'afternoon';
    if (h >= 18 && h < 21) return 'evening';
    return 'night';
}

const _SLOT_LABELS = {
    morning:      'בוקר',
    late_morning: 'בוקר מאוחר',
    noon:         'צהריים',
    afternoon:    'אחרי הצהריים',
    evening:      'ערב',
    night:        'לילה',
};

async function _buildHeroCard(slot, tasks, reminders, memories, settings, useLocal) {
    const { callGemma4 } = require('./agents/models');
    const userName = settings?.userName || settings?.userProfile?.name || 'שלי';
    const memorySummary = Array.isArray(memories) && memories.length > 0
        ? memories.slice(0, 3).map(m => `- ${m}`).join('\n')
        : '';

    const taskLines = (tasks || []).slice(0, 3).map(t =>
        `- ${t.content}${t.priority === 'high' ? ' (דחוף)' : ''}`
    ).join('\n');

    const reminderLines = (reminders || []).slice(0, 3).map(r => {
        const timeStr = new Date(r.scheduled_time).toLocaleTimeString('he-IL', {
            timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit',
        });
        return `- ${r.text} ב-${timeStr}`;
    }).join('\n');

    const slotLabel = _SLOT_LABELS[slot] || slot;

    const prompt = [
        { role: 'system', content: 'אתה ג\'רוויס, עוזר אישי בעברית. כתוב תגובה קצרה ובהירה (עד 2 משפטים) המתאימה לשעה ביום ולמצב המשתמש. ללא כותרות וללא תבליטים.' },
        { role: 'user', content: `שעת יום: ${slotLabel}\nמשתמש: ${userName}\n${taskLines ? `משימות פתוחות:\n${taskLines}\n` : ''}${reminderLines ? `תזכורות קרובות:\n${reminderLines}\n` : ''}${memorySummary ? `פרטים רלוונטיים על המשתמש:\n${memorySummary}\n` : ''}כתוב ברכה/סיכום קצר מתאים לשעה.` },
    ];

    try {
        const text = await callGemma4(prompt, useLocal, 150);
        return { text: typeof text === 'string' ? text.trim() : text, confidence: memorySummary ? 0.8 : 0.5 };
    } catch {
        const fallbacks = {
            morning: `בוקר טוב, ${userName}! מוכן ליום?`,
            late_morning: `שלום ${userName}, כיצד מתקדם הבוקר?`,
            noon: `שלום ${userName}, איך מתקדם היום?`,
            afternoon: `שלום ${userName}, מה הלאה?`,
            evening: `ערב טוב, ${userName}! איך היה היום?`,
            night: `לילה טוב, ${userName}! כדאי לסיים ולנוח.`,
        };
        return { text: fallbacks[slot] || `שלום, ${userName}!`, confidence: 0.0 };
    }
}

app.get('/dashboard-context', _rl(30), async (req, res) => {
    try {
        const settings = {};
        try {
            const profile = await getUserProfile();
            if (profile) {
                settings.userName = profile.name || profile.userName;
                settings.userProfile = profile;
            }
        } catch { /* non-fatal */ }

        const useLocal = String(req.headers['x-use-local'] || '').toLowerCase() === 'true';
        const nowJer = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
        const slot = _getDashboardTimeSlot(nowJer);

        // ── Parallel data fetch ──────────────────────────────────────────────
        const threeHoursLater = new Date(nowJer.getTime() + 3 * 60 * 60 * 1000).toISOString();

        const [tasksRes, remindersRes, memoriesRaw, weatherData, newsData] = await Promise.all([
            supabase.from('tasks').select('id,content,priority').eq('done', false)
                .order('priority', { ascending: false }).limit(6),
            supabase.from('reminders').select('id,text,scheduled_time').eq('fired', false)
                .lte('scheduled_time', threeHoursLater)
                .order('scheduled_time', { ascending: true }).limit(6),
            (async () => {
                try {
                    if (pinecone.isReady()) {
                        const hits = await pinecone.searchMemories(`שגרה ${_SLOT_LABELS[slot]}`, 3);
                        if (hits) return hits;
                    }
                } catch { /* fall through */ }
                const { data } = await supabase.from('memories').select('content').limit(5);
                return (data || []).map(m => m.content);
            })(),
            (async () => {
                const cacheKey = 'dashboard:weather';
                const cached = cacheGet(cacheKey);
                if (cached) return cached;
                try {
                    const { runWeatherAgent } = require('./agents/weatherAgent');
                    const result = await runWeatherAgent('מה מזג האוויר עכשיו', supabase, useLocal, settings);
                    const data = { summary: result.answer };
                    cacheSet(cacheKey, data, TTL_DASHBOARD_WEATHER);
                    return data;
                } catch { return null; }
            })(),
            (async () => {
                const cacheKey = 'dashboard:news';
                const cached = cacheGet(cacheKey);
                if (cached) return cached;
                try {
                    const { runNewsAgent } = require('./agents/newsAgent');
                    const result = await runNewsAgent('חדשות עדכניות קצרות', supabase, useLocal, settings);
                    const data = { summary: result.answer };
                    cacheSet(cacheKey, data, TTL_DASHBOARD_NEWS);
                    return data;
                } catch { return null; }
            })(),
        ]);

        const tasks     = tasksRes.data     || [];
        const reminders = remindersRes.data  || [];
        const memories  = memoriesRaw        || [];

        // ── Hero card (cached per slot) ──────────────────────────────────────
        const heroCacheKey = `dashboard:hero:${slot}`;
        let heroCard = cacheGet(heroCacheKey);
        if (!heroCard) {
            const { text, confidence } = await _buildHeroCard(slot, tasks, reminders, memories, settings, useLocal);
            heroCard = { text, confidence, slot };
            cacheSet(heroCacheKey, heroCard, TTL_DASHBOARD_HERO);
        }

        // ── Build widget list ─────────────────────────────────────────────────
        const widgets = [];

        widgets.push({
            type: 'tasks',
            data: tasks.slice(0, 3),
            badge: Math.max(0, tasks.length - 3),
        });

        const urgentReminders  = reminders.filter(r => (new Date(r.scheduled_time) - nowJer) < 30 * 60 * 1000);
        const normalReminders  = reminders.filter(r => (new Date(r.scheduled_time) - nowJer) >= 30 * 60 * 1000);
        const visibleReminders = [...urgentReminders, ...normalReminders].slice(0, 3);
        widgets.push({
            type: 'reminders',
            data: visibleReminders,
            badge: Math.max(0, reminders.length - 3),
        });

        if (weatherData) widgets.push({ type: 'weather', data: weatherData });
        if (newsData)    widgets.push({ type: 'news',    data: newsData });

        res.json({
            heroCard,
            widgets,
            slot,
            timestamp: new Date().toISOString(),
        });
    } catch (err) {
        console.error('GET /dashboard-context error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Google Calendar OAuth ────────────────────────────────────────────────────
// Short-lived nonces for CSRF protection on the OAuth flow (TTL: 10 min).
const _oauthNonces = new Map(); // nonce -> expiresAt
const _OAUTH_NONCE_TTL = 10 * 60 * 1000;

app.get('/auth/google/start', (_req, res) => {
    if (!process.env.GOOGLE_CLIENT_ID || !process.env.GOOGLE_CLIENT_SECRET) {
        return res.status(400).json({ error: 'GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET not configured' });
    }
    const state = require('crypto').randomBytes(32).toString('hex');
    _oauthNonces.set(state, Date.now() + _OAUTH_NONCE_TTL);
    const redirectUri = `${process.env.SERVER_URL || `http://localhost:${process.env.PORT || 3000}`}/auth/google/callback`;
    const authUrl = buildAuthUrl(redirectUri, state);
    res.redirect(authUrl);
});

app.get('/auth/google/callback', async (req, res) => {
    const { code, error, state } = req.query;
    if (error) return res.status(400).send('OAuth error');
    if (!code) return res.status(400).send('No code received');

    const nonceExpiry = _oauthNonces.get(state);
    if (!nonceExpiry || Date.now() > nonceExpiry) {
        return res.status(400).send('Invalid or expired OAuth state');
    }
    _oauthNonces.delete(state);

    try {
        const redirectUri = `${process.env.SERVER_URL || `http://localhost:${process.env.PORT || 3000}`}/auth/google/callback`;
        const tokenRes = await require('axios').post('https://oauth2.googleapis.com/token', {
            client_id: process.env.GOOGLE_CLIENT_ID,
            client_secret: process.env.GOOGLE_CLIENT_SECRET,
            code,
            grant_type: 'authorization_code',
            redirect_uri: redirectUri,
        });
        const tokenData = tokenRes.data;
        // Store refresh token in user_profiles
        await supabase.from('user_profiles').upsert([{ id: 'default', google_calendar_token: JSON.stringify(tokenData) }], { onConflict: 'id' });
        cacheInvalidate('userProfile');
        res.send('<h2>✅ יומן Google חובר בהצלחה! אפשר לסגור את החלון.</h2>');
    } catch (err) {
        console.error('Google OAuth callback error:', err.message);
        res.status(500).send('OAuth failed');
    }
});

// ─── Contacts REST ────────────────────────────────────────────────────────────

app.get('/contacts', requirePolicy('contacts.read', {}), async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('contacts')
            .select('*')
            .order('name', { ascending: true });
        if (error) throw error;
        res.json({ contacts: data || [] });
    } catch (err) {
        console.error('GET /contacts error:', err.message);
        res.status(500).json({ contacts: [] });
    }
});

app.delete('/contacts/:id', requirePolicy('contacts.delete', { sensitive: true, irreversible: true }), async (req, res) => {
    try {
        const { error } = await supabase.from('contacts').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /contacts/:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
    }
});

// ─── PUT /notes/:id — update note ─────────────────────────────────────────────
app.put('/notes/:id', async (req, res) => {
    try {
        const { title, content } = req.body;
        const updates = {};
        if (title   !== undefined) updates.title   = title;
        if (content !== undefined) updates.content = content;
        if (Object.keys(updates).length === 0)
            return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await supabase
            .from('notes').update(updates).eq('id', req.params.id).select().single();
        if (error) throw error;
        res.json({ note: data });
    } catch (err) {
        console.error('PUT /notes/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── POST /tasks — add task from app ──────────────────────────────────────────
app.post('/tasks', async (req, res) => {
    try {
        const { content } = req.body;
        if (!content) return res.status(400).json({ error: 'content required' });
        const { data, error } = await supabase.from('tasks').insert([{ content }]).select().single();
        if (error) throw error;
        res.json({ task: data });
    } catch (err) {
        console.error('POST /tasks error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Shopping ─────────────────────────────────────────────────────────────────
app.get('/shopping', async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('shopping_items')
            .select('*')
            .order('created_at', { ascending: true });
        if (error) throw error;
        res.json({ items: data || [] });
    } catch (err) {
        console.error('GET /shopping error:', err.message);
        res.status(500).json({ items: [] });
    }
});

app.post('/shopping', async (req, res) => {
    try {
        const { item } = req.body;
        if (!item) return res.status(400).json({ error: 'item required' });
        const { data, error } = await supabase
            .from('shopping_items')
            .insert([{ item }])
            .select().single();
        if (error) throw error;
        res.json({ item: data });
    } catch (err) {
        console.error('POST /shopping error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/shopping/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('shopping_items').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /shopping:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
    }
});

// ─── Notes ────────────────────────────────────────────────────────────────────
app.get('/notes', async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('notes')
            .select('*')
            .order('created_at', { ascending: false });
        if (error) throw error;
        res.json({ notes: data || [] });
    } catch (err) {
        console.error('GET /notes error:', err.message);
        res.status(500).json({ notes: [] });
    }
});

app.post('/notes', async (req, res) => {
    try {
        const { title, content } = req.body;
        if (!content) return res.status(400).json({ error: 'content required' });
        const { data, error } = await supabase
            .from('notes')
            .insert([{ title: title || '', content }])
            .select().single();
        if (error) throw error;
        res.json({ note: data });
    } catch (err) {
        console.error('POST /notes error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/notes/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('notes').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /notes:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
    }
});

// ─── Projects REST API ────────────────────────────────────────────────────────

app.get('/projects', async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('projects')
            .select('*')
            .order('created_at', { ascending: false });
        if (error) {
            console.error('GET /projects DB error:', error.message);
            return res.json({ projects: [] });
        }
        const projects = data || [];

        // Enrich each project with aggregate task/milestone counts + progress.
        // Single-user app: 3 queries total (projects + tasks + milestones), no N+1.
        const ids = projects.map(p => p.id);
        if (ids.length > 0) {
            const [{ data: tasks }, { data: milestones }] = await Promise.all([
                supabase.from('tasks').select('project_id, done').in('project_id', ids),
                supabase.from('project_milestones').select('project_id, completed').in('project_id', ids),
            ]);

            const stats = {}; // projectId -> { open, total, done, mTotal, mDone }
            for (const id of ids) stats[id] = { open: 0, total: 0, done: 0, mTotal: 0, mDone: 0 };
            for (const t of tasks || []) {
                const s = stats[t.project_id];
                if (!s) continue;
                s.total++;
                if (t.done) s.done++; else s.open++;
            }
            for (const m of milestones || []) {
                const s = stats[m.project_id];
                if (!s) continue;
                s.mTotal++;
                if (m.completed) s.mDone++;
            }
            for (const p of projects) {
                const s = stats[p.id] || { open: 0, total: 0, done: 0, mTotal: 0, mDone: 0 };
                const totalItems = s.total + s.mTotal;
                const doneItems = s.done + s.mDone;
                p.open_tasks = s.open;
                p.total_tasks = s.total;
                p.done_count = doneItems;
                p.milestones_total = s.mTotal;
                p.milestones_done = s.mDone;
                p.progress = totalItems > 0 ? doneItems / totalItems : 0;
            }
        }

        res.json({ projects });
    } catch (err) {
        console.error('GET /projects error:', err.message);
        res.json({ projects: [] });
    }
});

app.post('/projects', async (req, res) => {
    try {
        const { name, description, status, priority, start_date, due_date, color, methodology, method_config } = req.body;
        if (!name) return res.status(400).json({ error: 'name is required' });
        const validStatuses = ['active', 'planning', 'paused', 'completed', 'archived'];
        const safeStatus = validStatuses.includes(status) ? status : 'active';
        const { data, error } = await supabase
            .from('projects')
            .insert([{
                name, description,
                status: safeStatus,
                priority: priority || 'medium',
                start_date, due_date,
                color: color || '#6366f1',
                methodology: methodology || 'kanban',
                method_config: method_config || {},
            }])
            .select()
            .single();
        if (error) throw error;
        res.json({ project: data });
    } catch (err) {
        console.error('POST /projects error:', err.message, err.details || '');
        res.status(500).json({ error: err.message || 'Internal server error' });
    }
});

// Deterministic weekly briefing (zero LLM tokens). Must be registered before
// GET /projects/:id so the ":id" param doesn't capture "briefing".
app.get('/projects/briefing', async (req, res) => {
    try {
        const userName = req.query.userName || 'נדב';
        const result = await buildProjectsBriefing(supabase, userName);
        res.json(result);
    } catch (err) {
        console.error('GET /projects/briefing error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.get('/projects/:id', async (req, res) => {
    try {
        const { data: project, error } = await supabase
            .from('projects')
            .select('*')
            .eq('id', req.params.id)
            .single();
        if (error || !project) return res.status(404).json({ error: 'Not found' });

        const [{ data: milestones }, { data: tasks }, { data: reminders }, { data: notes }, { data: sprints }] = await Promise.all([
            supabase.from('project_milestones').select('*').eq('project_id', project.id).order('due_date'),
            (async () => {
                let r = await supabase.from('tasks').select('*, subtasks(id, content, done, created_at)').eq('project_id', project.id).order('created_at');
                if (r.error) r = await supabase.from('tasks').select('*').eq('project_id', project.id).order('created_at');
                return r;
            })(),
            supabase.from('reminders').select('*').eq('project_id', project.id).order('scheduled_time'),
            supabase.from('notes').select('*').eq('project_id', project.id).order('created_at'),
            supabase.from('project_sprints').select('*').eq('project_id', project.id).order('start_date', { ascending: false }),
        ]);

        res.json({ project, milestones: milestones || [], tasks: tasks || [], reminders: reminders || [], notes: notes || [], sprints: sprints || [] });
    } catch (err) {
        console.error('GET /projects/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.put('/projects/:id', async (req, res) => {
    try {
        const updates = { ...req.body, updated_at: new Date().toISOString() };
        delete updates.id;
        const { data, error } = await supabase
            .from('projects')
            .update(updates)
            .eq('id', req.params.id)
            .select()
            .single();
        if (error) throw error;
        res.json({ project: data });
    } catch (err) {
        console.error('PUT /projects/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/projects/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('projects').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /projects/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.get('/projects/:id/milestones', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('project_milestones')
            .select('*')
            .eq('project_id', req.params.id)
            .order('due_date');
        if (error) throw error;
        res.json({ milestones: data || [] });
    } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.post('/projects/:id/milestones', async (req, res) => {
    try {
        const { title, due_date } = req.body;
        if (!title) return res.status(400).json({ error: 'title is required' });
        const { data, error } = await supabase
            .from('project_milestones')
            .insert([{ project_id: req.params.id, title, due_date: due_date || null }])
            .select()
            .single();
        if (error) throw error;
        res.json({ milestone: data });
    } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.put('/projects/:id/milestones/:mId', async (req, res) => {
    try {
        const updates = { ...req.body };
        if (updates.completed && !updates.completed_at) updates.completed_at = new Date().toISOString();
        if (!updates.completed) updates.completed_at = null;
        const { data, error } = await supabase
            .from('project_milestones')
            .update(updates)
            .eq('id', req.params.mId)
            .eq('project_id', req.params.id)
            .select()
            .single();
        if (error) throw error;
        res.json({ milestone: data });
    } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/projects/:id/milestones/:mId', async (req, res) => {
    try {
        const { error } = await supabase
            .from('project_milestones')
            .delete()
            .eq('id', req.params.mId)
            .eq('project_id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Project Sprints (Scrum) ──────────────────────────────────────────────────

app.get('/projects/:id/sprints', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('project_sprints')
            .select('*')
            .eq('project_id', req.params.id)
            .order('start_date', { ascending: false });
        if (error) throw error;
        res.json({ sprints: data || [] });
    } catch (err) {
        console.error('GET /projects/:id/sprints error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.post('/projects/:id/sprints', async (req, res) => {
    try {
        const { name, goal, start_date, end_date, capacity_points } = req.body;
        if (!name || !start_date || !end_date) {
            return res.status(400).json({ error: 'name, start_date ו-end_date נדרשים' });
        }
        const { data, error } = await supabase
            .from('project_sprints')
            .insert([{ project_id: req.params.id, name, goal, start_date, end_date, capacity_points: capacity_points || 0 }])
            .select()
            .single();
        if (error) throw error;
        res.json({ sprint: data });
    } catch (err) {
        console.error('POST /projects/:id/sprints error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.put('/projects/:id/sprints/:sId', async (req, res) => {
    try {
        const updates = { ...req.body, updated_at: new Date().toISOString() };
        delete updates.id;
        delete updates.project_id;
        const { data, error } = await supabase
            .from('project_sprints')
            .update(updates)
            .eq('id', req.params.sId)
            .eq('project_id', req.params.id)
            .select()
            .single();
        if (error) throw error;
        res.json({ sprint: data });
    } catch (err) {
        console.error('PUT /projects/:id/sprints/:sId error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/projects/:id/sprints/:sId', async (req, res) => {
    try {
        const { error } = await supabase
            .from('project_sprints')
            .delete()
            .eq('id', req.params.sId)
            .eq('project_id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /projects/:id/sprints/:sId error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.post('/projects/:id/sprints/:sId/start', async (req, res) => {
    try {
        const { data: existing } = await supabase
            .from('project_sprints')
            .select('id')
            .eq('project_id', req.params.id)
            .eq('status', 'active')
            .neq('id', req.params.sId);
        if (existing && existing.length > 0) {
            return res.status(409).json({ error: 'כבר קיים ספרינט פעיל לפרויקט זה' });
        }
        const { data, error } = await supabase
            .from('project_sprints')
            .update({ status: 'active', updated_at: new Date().toISOString() })
            .eq('id', req.params.sId)
            .eq('project_id', req.params.id)
            .select()
            .single();
        if (error) throw error;
        res.json({ sprint: data });
    } catch (err) {
        if (err.status === 409) return res.status(409).json({ error: err.message });
        console.error('POST .../start error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.post('/projects/:id/sprints/:sId/complete', async (req, res) => {
    try {
        await supabase
            .from('tasks')
            .update({ sprint_id: null })
            .eq('sprint_id', req.params.sId)
            .eq('done', false);
        const { data, error } = await supabase
            .from('project_sprints')
            .update({ status: 'completed', updated_at: new Date().toISOString() })
            .eq('id', req.params.sId)
            .eq('project_id', req.params.id)
            .select()
            .single();
        if (error) throw error;
        res.json({ sprint: data });
    } catch (err) {
        console.error('POST .../complete error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Methodology recommendation (cached) ──────────────────────────────────────

const _methodRecCache = new Map(); // key: name::description, value: {data, ts}

app.post('/projects/recommend-methodology', async (req, res) => {
    try {
        const { name = '', description = '' } = req.body || {};
        const key = `${name}::${description}`.slice(0, 300);
        const cached = _methodRecCache.get(key);
        if (cached && (Date.now() - cached.ts) < 30 * 60 * 1000) {
            return res.json({ ...cached.data, cached: true });
        }
        const prompt = `הפרויקט: ${name}. ${description}. איזו שיטת עבודה תמליץ: kanban/scrum/eisenhower/gantt? הסבר בקצרה. החזר JSON: {"methodology":"...","reason":"..."} בלבד.`;
        const raw = await callGemma4(prompt, false, 150);
        const match = raw.match(/\{[\s\S]*\}/);
        let data = { methodology: '', reason: '' };
        if (match) {
            try {
                const p = JSON.parse(match[0]);
                data = {
                    methodology: (p.methodology || '').toLowerCase(),
                    reason: p.reason || '',
                };
            } catch (_) {}
        }
        _methodRecCache.set(key, { data, ts: Date.now() });
        res.json({ ...data, cached: false });
    } catch (err) {
        console.error('POST /projects/recommend-methodology error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Project AI Insights ──────────────────────────────────────────────────────

const _projectInsightsCache = new Map(); // key: `${projectId}:${methodology}`, value: {text, ts}

app.post('/projects/:id/ai-insights', async (req, res) => {
    try {
        const { methodology } = req.body || {};
        const cacheKey = `${req.params.id}:${methodology || 'general'}`;
        const cached = _projectInsightsCache.get(cacheKey);
        if (cached && (Date.now() - cached.ts) < 30 * 60 * 1000) {
            return res.json({ insights: cached.text, cached: true });
        }

        const { data: project } = await supabase.from('projects').select('*').eq('id', req.params.id).single();
        if (!project) return res.status(404).json({ error: 'פרויקט לא נמצא' });

        const [{ data: tasks }, { data: milestones }, { data: sprints }] = await Promise.all([
            supabase.from('tasks').select('content,done,story_points,kanban_column,eisenhower_quad,sprint_id').eq('project_id', req.params.id),
            supabase.from('project_milestones').select('title,completed').eq('project_id', req.params.id),
            supabase.from('project_sprints').select('*').eq('project_id', req.params.id),
        ]);

        const openTasks = (tasks || []).filter(t => !t.done).length;
        const doneTasks = (tasks || []).filter(t => t.done).length;
        const activeSprint = (sprints || []).find(s => s.status === 'active');

        let contextLines = [
            `פרויקט: "${project.name}". מתודולוגיה: ${methodology || project.methodology || 'kanban'}.`,
            `משימות פתוחות: ${openTasks}, הושלמו: ${doneTasks}.`,
        ];
        if (methodology === 'scrum' || project.methodology === 'scrum') {
            if (activeSprint) {
                const sprintDone = (tasks || []).filter(t => t.done && t.sprint_id === activeSprint.id).reduce((s, t) => s + (t.story_points || 1), 0);
                const sprintTotal = (tasks || []).filter(t => t.sprint_id === activeSprint.id).reduce((s, t) => s + (t.story_points || 1), 0);
                contextLines.push(`ספרינט פעיל: "${activeSprint.name}", נקודות שהושלמו: ${sprintDone}/${sprintTotal}.`);
            } else {
                contextLines.push('אין ספרינט פעיל כרגע.');
            }
        } else if (methodology === 'kanban' || project.methodology === 'kanban') {
            const cols = { todo: 0, in_progress: 0, review: 0, done: 0 };
            (tasks || []).forEach(t => { if (cols[t.kanban_column] !== undefined) cols[t.kanban_column]++; });
            contextLines.push(`עמודות Kanban: לביצוע=${cols.todo}, בתהליך=${cols.in_progress}, בבדיקה=${cols.review}, הושלם=${cols.done}.`);
        } else if (methodology === 'eisenhower' || project.methodology === 'eisenhower') {
            const quads = { q1: 0, q2: 0, q3: 0, q4: 0, null: 0 };
            (tasks || []).forEach(t => { const k = t.eisenhower_quad || 'null'; if (quads[k] !== undefined) quads[k]++; });
            contextLines.push(`מטריצה: Q1(דחוף+חשוב)=${quads.q1}, Q2(חשוב)=${quads.q2}, Q3(דחוף)=${quads.q3}, Q4(שאר)=${quads.q4}, לא מסווג=${quads.null}.`);
        }

        const prompt = contextLines.join('\n') + '\nתן 3 תובנות קצרות בעברית על מצב הפרויקט ומה כדאי לשפר. החזר JSON: {"insights":["...","...","..."]}';
        const raw = await callGemma4(prompt, false, 300);
        const match = raw.match(/\{[\s\S]*\}/);
        let insights = [];
        if (match) {
            try { insights = JSON.parse(match[0]).insights || []; } catch (_) {}
        }
        if (!insights.length) insights = [raw.trim()];

        _projectInsightsCache.set(cacheKey, { text: insights, ts: Date.now() });
        res.json({ insights, cached: false });
    } catch (err) {
        console.error('POST /projects/:id/ai-insights error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── E2E Reports — list / detail / delete ────────────────────────────────────

app.get('/e2e-reports', async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('e2e_reports')
            .select('*')
            .order('created_at', { ascending: false })
            .limit(2000);
        if (error) throw error;

        // Group by run_id and compute summary per run
        const byRun = new Map();
        for (const row of data || []) {
            if (!byRun.has(row.run_id)) {
                byRun.set(row.run_id, {
                    run_id: row.run_id,
                    created_at: row.created_at,
                    count: 0,
                    critical: 0, high: 0, medium: 0, low: 0,
                    done: 0,
                });
            }
            const g = byRun.get(row.run_id);
            if (row.created_at > g.created_at) g.created_at = row.created_at;
            if (row.status === 'done') { g.done++; continue; }
            g.count++;
            if (g[row.severity] !== undefined) g[row.severity]++;
        }
        const reports = Array.from(byRun.values())
            .map(r => {
                const w = { critical: 25, high: 10, medium: 4, low: 1 };
                const penalty = r.critical * w.critical + r.high * w.high + r.medium * w.medium + r.low * w.low;
                r.score = Math.max(0, 100 - penalty);
                return r;
            })
            .sort((a, b) => b.created_at.localeCompare(a.created_at));
        res.json({ reports });
    } catch (err) {
        console.error('GET /e2e-reports error:', err.message);
        res.status(500).json({ reports: [], error: 'Internal server error' });
    }
});

app.get('/e2e-reports/:runId', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('e2e_reports')
            .select('*')
            .eq('run_id', req.params.runId)
            .order('severity', { ascending: true });
        if (error) throw error;
        const findings = data || [];

        const counts = countsBySeverity(findings);
        const score  = computeScore(findings);
        const claudePrompt = buildClaudePrompt({ runId: req.params.runId, findings, score, counts });
        res.json({
            run_id:  req.params.runId,
            findings,
            counts,
            score,
            claudePrompt,
        });
    } catch (err) {
        console.error('GET /e2e-reports/:id error:', err.message);
        res.status(500).json({ findings: [], error: 'Internal server error' });
    }
});

app.delete('/e2e-reports/:runId', async (req, res) => {
    try {
        const { error } = await supabase
            .from('e2e_reports')
            .delete()
            .eq('run_id', req.params.runId);
        if (error) throw error;
        cacheInvalidate('chatHistory'); // not strictly needed but cheap
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /e2e-reports/:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
    }
});

// ─── POST /e2e-reports/:runId/prompt — generate Claude prompt for selected findings
app.post('/e2e-reports/:runId/prompt', async (req, res) => {
    try {
        const { fingerprints } = req.body || {};
        if (!Array.isArray(fingerprints) || !fingerprints.length) {
            return res.status(400).json({ error: 'fingerprints array required' });
        }
        const { data, error } = await supabase
            .from('e2e_reports')
            .select('*')
            .eq('run_id', req.params.runId)
            .in('fingerprint', fingerprints);
        if (error) throw error;
        const findings = data || [];
        const counts   = countsBySeverity(findings);
        const score    = computeScore(findings);
        const claudePrompt = buildClaudePrompt({ runId: req.params.runId, findings, score, counts });
        res.json({ claudePrompt });
    } catch (err) {
        console.error('POST /e2e-reports/:id/prompt error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── POST /e2e-reports/:runId/mark-done — mark specific findings as done
app.post('/e2e-reports/:runId/mark-done', async (req, res) => {
    try {
        const { fingerprints } = req.body || {};
        if (!Array.isArray(fingerprints) || !fingerprints.length) {
            return res.status(400).json({ error: 'fingerprints array required' });
        }
        const { error } = await supabase
            .from('e2e_reports')
            .update({ status: 'done' })
            .eq('run_id', req.params.runId)
            .in('fingerprint', fingerprints);
        if (error) throw error;
        res.json({ ok: true, updated: fingerprints.length });
    } catch (err) {
        console.error('POST /e2e-reports/:id/mark-done error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
    }
});

// ─── GET /scan/errors — run code error scanner and return JSON report ─────────
app.get('/scan/errors', _rl(5), async (_req, res) => {
    try {
        const { runCodeErrorScanner } = require('./agents/e2e/codeErrorScanner');
        const result = await runCodeErrorScanner({});
        res.json(result);
    } catch (err) {
        console.error('❌ /scan/errors:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── POST /e2e/trigger — fire-and-forget e2e run ─────────────────────────────
// Used by the mobile control center "run e2e now" quick action and by the
// re-trigger automation when the last report's score drops sharply.
app.post('/e2e/trigger', _rl(3), async (_req, res) => {
    try {
        const { runE2EAgent } = require('./agents/e2eAgent');
        // Fire-and-forget so the HTTP response is fast — the agent persists
        // its report when it finishes, which the next /control-center/events
        // poll will surface as a new badge.
        setImmediate(() => {
            try { runE2EAgent('הרץ סקירת קצה', supabase, false, {}); }
            catch (e) { console.error('e2e trigger run error:', e.message); }
        });
        res.json({ triggered: true, startedAt: new Date().toISOString() });
    } catch (err) {
        console.error('❌ /e2e/trigger:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── GET /control-center/events ──────────────────────────────────────────────
// Aggregates live alerts + per-tab unread badge counts for the mobile control
// center polling loop. Designed to be cheap (no LLM) so adaptive polling
// can hit it every 15–60s without thrashing the server.
//
// Query params:
//   since   ISO timestamp — alerts strictly newer than this are flagged "new"
//   userName  Optional, used for the survey-reminder heuristic
app.get('/control-center/events', async (req, res) => {
    try {
        const since = req.query.since ? new Date(req.query.since) : null;
        const sinceMs = since && !isNaN(since.getTime()) ? since.getTime() : 0;
        const userName = (req.query.userName || '').toString().trim();

        const alerts = [];
        const badges = { overview: 0, development: 0, agents: 0, insights: 0, surveys: 0 };

        // 1) New e2e reports → insights tab badge + alert on score drop.
        try {
            const { data: reports } = await supabase
                .from('e2e_reports')
                .select('run_id, score, critical, high, created_at')
                .order('created_at', { ascending: false })
                .limit(5);
            const rows = reports || [];
            if (rows.length > 0) {
                const latest = rows[0];
                const latestTs = new Date(latest.created_at).getTime();
                if (latestTs > sinceMs) {
                    badges.insights += 1;
                    const sev = (latest.critical || 0) > 0 ? 'urgent'
                              : (latest.score || 100) < 60 ? 'warning' : 'info';
                    alerts.push({
                        id: `e2e:${latest.run_id}`,
                        type: 'e2e_new_report',
                        severity: sev,
                        title: 'דוח בדיקות חדש',
                        message: `Score ${latest.score ?? '?'} · 🔴 ${latest.critical || 0} · 🟠 ${latest.high || 0}`,
                        tabHint: 'insights',
                        actionHint: 'open_e2e_report',
                        actionPayload: { runId: latest.run_id },
                        createdAt: latest.created_at,
                    });
                }
                // Score-drop automation: if newest score is >=15 below
                // previous, suggest a re-run as an inline action.
                if (rows.length >= 2) {
                    const prev = rows[1];
                    const drop = (prev.score || 0) - (latest.score || 0);
                    if (drop >= 15) {
                        alerts.push({
                            id: `e2e_drop:${latest.run_id}`,
                            type: 'e2e_score_drop',
                            severity: 'warning',
                            title: 'ירידה חדה ב-Score',
                            message: `Score ירד מ-${prev.score} ל-${latest.score}. כדאי להריץ סקירה חוזרת.`,
                            tabHint: 'insights',
                            actionHint: 'rerun_e2e',
                            createdAt: latest.created_at,
                        });
                    }
                }
            }
        } catch (e) {
            console.error('control-center events: e2e error:', e.message);
        }

        // 2) Quick-win proposals needing a draft — development tab.
        try {
            const backlogPath = require('path').join(__dirname, 'backlog.json');
            const fs = require('fs');
            if (fs.existsSync(backlogPath)) {
                const data = JSON.parse(fs.readFileSync(backlogPath, 'utf8'));
                const proposals = Array.isArray(data.proposals) ? data.proposals : [];
                const quickWins = proposals
                    .filter(p => p && p.status === 'proposal')
                    .filter(p => (p.impact || 0) >= 7 && (p.effort || 99) <= 4)
                    .slice(0, 3);
                if (quickWins.length > 0) {
                    badges.development += quickWins.length;
                    quickWins.forEach(p => {
                        alerts.push({
                            id: `quickwin:${p.id}`,
                            type: 'high_quickwin',
                            severity: 'info',
                            title: 'הצעת Quick-Win זמינה',
                            message: `"${(p.title || '').slice(0, 60)}" — מומלץ לקדם לתכנון`,
                            tabHint: 'development',
                            actionHint: 'promote_proposal',
                            actionPayload: { proposalId: p.id },
                            createdAt: p.createdAt || new Date().toISOString(),
                        });
                    });
                }
            }
        } catch (e) {
            console.error('control-center events: backlog error:', e.message);
        }

        // 3) Agent idle alert — heuristic: if today's chat count is 0
        // by mid-day Jerusalem time, surface a nudge on the agents tab.
        try {
            const now = new Date();
            const hourJlm = (now.getUTCHours() + 2) % 24; // rough JLM offset
            const todayStart = new Date();
            todayStart.setUTCHours(0, 0, 0, 0);
            const { count } = await supabase
                .from('chat_history')
                .select('id', { count: 'exact', head: true })
                .gte('timestamp', todayStart.toISOString());
            if ((count || 0) === 0 && hourJlm >= 12) {
                badges.agents += 1;
                alerts.push({
                    id: `idle:${todayStart.toISOString().slice(0, 10)}`,
                    type: 'agent_idle',
                    severity: 'info',
                    title: 'שקט מוחלט היום',
                    message: 'הסוכנים לא טופלו שום משימה היום. רוצה לפתוח שיחה?',
                    tabHint: 'agents',
                    actionHint: 'open_chat',
                    createdAt: new Date().toISOString(),
                });
            }
        } catch (e) {
            console.error('control-center events: idle error:', e.message);
        }

        // 4) Survey reminder — last survey > 7 days ago.
        try {
            if (userName) {
                const { data } = await supabase
                    .from('user_surveys')
                    .select('created_at')
                    .eq('user_name', userName)
                    .order('created_at', { ascending: false })
                    .limit(1);
                const lastSurvey = data && data.length ? new Date(data[0].created_at).getTime() : 0;
                const weekMs = 7 * 24 * 60 * 60 * 1000;
                if (lastSurvey === 0 || Date.now() - lastSurvey > weekMs) {
                    badges.surveys += 1;
                    alerts.push({
                        id: `survey:${userName}:${Math.floor(Date.now() / weekMs)}`,
                        type: 'survey_reminder',
                        severity: 'info',
                        title: lastSurvey === 0 ? 'אין סקרים עדיין' : 'עבר שבוע מהסקר האחרון',
                        message: 'סקר קצר עוזר לי להבין אותך טוב יותר.',
                        tabHint: 'surveys',
                        actionHint: 'start_survey',
                        createdAt: new Date().toISOString(),
                    });
                }
            }
        } catch (e) {
            console.error('control-center events: survey error:', e.message);
        }

        // 5) Disabled agents → development/agents tab info.
        try {
            const { getAgentRegistry } = require('./services/agentRegistryService');
            const disabled = getAgentRegistry().filter(a => a.status === 'disabled');
            if (disabled.length > 0) {
                badges.agents += disabled.length;
            }
        } catch (_) {}

        res.json({
            generatedAt: new Date().toISOString(),
            alerts,
            badges,
        });
    } catch (err) {
        console.error('❌ /control-center/events:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── PUT /reminders/:id — update text and/or scheduled_time ──────────────────
// ─── POST /contacts — add contact from app ───────────────────────────────────
app.post('/contacts', requirePolicy('contacts.create', {}), async (req, res) => {
    try {
        const { name, phone, email } = req.body;
        if (!name) return res.status(400).json({ error: 'name required' });
        const row = { name };
        if (phone) row.phone = phone;
        if (email) row.email = email;
        const { data, error } = await supabase
            .from('contacts').insert([row]).select().single();
        if (error) throw error;
        res.json({ contact: data });
    } catch (err) {
        console.error('POST /contacts error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── PUT /contacts/:id — update contact ───────────────────────────────────────
app.put('/contacts/:id', requirePolicy('contacts.update', {}), async (req, res) => {
    try {
        const { name, phone, email } = req.body;
        const updates = {};
        if (name  !== undefined) updates.name  = name;
        if (phone !== undefined) updates.phone = phone;
        if (email !== undefined) updates.email = email;
        if (Object.keys(updates).length === 0)
            return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await supabase
            .from('contacts').update(updates).eq('id', req.params.id).select().single();
        if (error) throw error;
        res.json({ contact: data });
    } catch (err) {
        console.error('PUT /contacts/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── PATCH /shopping/:id — toggle done flag ──────────────────────────────────
app.patch('/shopping/:id', async (req, res) => {
    try {
        const { done, item } = req.body;
        const updates = {};
        if (done !== undefined) updates.done = done;
        if (item !== undefined) updates.item = item;
        if (Object.keys(updates).length === 0)
            return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await supabase
            .from('shopping_items').update(updates).eq('id', req.params.id).select().single();
        if (error) throw error;
        res.json({ item: data });
    } catch (err) {
        console.error('PATCH /shopping/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Streaming endpoint (SSE) ─────────────────────────────────────────────────

const { callGemma4Stream, callGemma4, providerContext, getCurrentProvider, LocalModelError } = require('./agents/models');

async function streamJarvisHandler(req, res) {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    const send = (data) => { if (!res.destroyed) res.write(`data: ${JSON.stringify(data)}\n\n`); };

    const controller = new AbortController();
    req.on('close', () => controller.abort());

    try {
        const originalMessage = req.body.command || '';
        let userMessage = originalMessage; // may be rewritten by reference resolution
        const chatId = req.body.chatId || req.body.chat_id || `session-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const settings    = req.body.settings || {};
        const useLocal    = settings.useLocalModel === true;

        if (userMessage.length > 5000) {
            send({ error: 'ההודעה ארוכה מדי.', chatId });
            return res.end();
        }

        // Contextual reference resolution (cheap sync gate first) — mirrors /ask-jarvis.
        if (contextResolver.shouldResolve(userMessage)) {
            const [resHistory, resSummary] = await Promise.all([
                loadChatHistory(chatId),
                conversationSummary.getSummary(chatId, supabase),
            ]);
            const { resolved, didResolve } = await contextResolver.resolveReferences(userMessage, resHistory, resSummary);
            if (didResolve) userMessage = resolved;
        }

        // Per-request opts: cloudProvider, temperature, local url/model from the
        // mobile app's settings. AsyncLocalStorage propagates these to all
        // callGemma4* sites without touching individual agents.
        const providerOpts = {
            cloudProvider:   settings.cloudProvider,
            openrouterModel: settings.openrouterModel,
            temperature:     settings.temperature,
            localServerUrl:  settings.localServerUrl,
            localModelName:  settings.localModelName,
        };

        // Wrap the whole dispatch in providerContext.run so provider tracking
        // (telemetry / provider badge) works for streaming too, and so opts
        // propagate to all callGemma4* calls inside agents.
        return await providerContext.run({ opts: providerOpts }, async () => {

        const _routed = classifyIntentDetailed(userMessage);
        let agentName = _routed.intent;
        if (_routed.ambiguous) {
            // Collision: disambiguate with the LLM, trusting it only if it picks
            // one of the matched candidates; otherwise keep the best keyword guess.
            const _llmIntent = await classifyIntentWithLLM(userMessage);
            if (_routed.matches.includes(_llmIntent)) agentName = _llmIntent;
            feedbackStore.recordEvent(supabase, {
                eventName: 'route_ambiguous',
                value: 1,
                metadata: {
                    chatId: String(chatId),
                    snippet: String(userMessage).slice(0, 200),
                    candidates: _routed.matches,
                    llm: _llmIntent,
                    chosen: agentName,
                    source: 'stream',
                },
            }).catch(() => {});
        }
        routeTracker.setLastRoute(chatId, { intent: agentName, mode: _routed.ambiguous ? 'llm' : 'fast' });

        // Disabled-agent guard: respect the on/off toggle from the Control Center.
        if (isAgentDisabled(agentName)) {
            console.log(`⛔ Agent "${agentName}" is disabled — skipping stream dispatch`);
            send({ chunk: AGENT_DISABLED_REPLY.answer, done: true, chatId });
            await Promise.all([
                saveChatMessage('user', originalMessage, chatId),
                saveChatMessage('jarvis', AGENT_DISABLED_REPLY.answer, chatId),
            ]);
            return res.end();
        }

        // Background agents: respond immediately and run in background via setImmediate
        // Background agents (e2e, code_error, security): in streaming mode
        // security also runs in background (parity preserved via getEntryForMode).
        const bgEntry = dispatcher.getEntryForMode(agentName, { forceBackground: true });
        if (bgEntry && bgEntry.mode === 'background') {
            const placeholder = bgEntry.placeholder;
            send({ chunk: placeholder, done: true, chatId });
            await Promise.all([
                saveChatMessage('user', originalMessage, chatId),
                saveChatMessage('jarvis', placeholder, chatId),
            ]);
            res.end();
            const bgChatId = chatId;
            const bgCtx = { userMessage, supabase, useLocal, settings, sendEmail, chatId };
            setImmediate(async () => {
                try {
                    const r = await bgEntry.invoke(bgCtx, AGENTS);
                    await saveChatMessage('jarvis', r.answer, bgChatId);
                    cacheInvalidate(`chatHistory:${bgChatId}`);
                } catch (err) {
                    await saveChatMessage('jarvis', `❌ ${err.message}`, bgChatId).catch(() => {});
                    cacheInvalidate(`chatHistory:${bgChatId}`);
                }
            });
            return;
        }

        // Only chat/draft agents stream token-by-token. Everything else runs to
        // completion and is sent as a single chunk — including the actionable
        // agents (task/reminder/notes/...), which MUST execute here too. Before,
        // any agent without an explicit branch fell through to runChatAgent, so
        // "הוסף משימה" got discussed by the chat model instead of being created.
        if (!['chat', 'draft'].includes(agentName)) {
            // Inject recent history into settings so agents have conversation context
            const recentHistory = await loadChatHistory(chatId).catch(() => []);
            settings.recentHistory = recentHistory.slice(-6);

            const syncEntry = dispatcher.getEntry(agentName);
            let result;
            if (syncEntry && syncEntry.mode === 'sync') {
                const ctx = { userMessage, supabase, useLocal, settings, sendEmail, chatId };
                result = await dispatcher.dispatch(agentName, ctx, AGENTS);
                if (syncEntry.cacheBust) cacheInvalidate(syncEntry.cacheBust);
            } else {
                const [chatHistory, longTermMemories] = await Promise.all([
                    loadChatHistory(chatId), fetchLongTermMemories()
                ]);
                result = await runChatAgent(userMessage, null, chatHistory, longTermMemories, settings);
            }
            const answer = result.answer || '';

            // Task auto-reminder: persist pending state (mirrors /ask-jarvis).
            if (agentName === 'task' && result.pendingAction?.type === 'auto_reminder') {
                await saveTaskReminderPending(result.pendingAction).catch(() => {});
            }

            send({ chunk: answer, done: true, chatId, action: result.action || null });
            await Promise.all([
                saveChatMessage('user', originalMessage, chatId),
                saveChatMessage('jarvis', answer, chatId),
            ]);
            cacheInvalidate(`chatHistory:${chatId}`);
            return res.end();
        }

        // Chat streaming via Groq — same quality as /ask-jarvis
        const [chatHistory, longTermMemories, chatSummary] = await Promise.all([
            loadChatHistory(chatId),
            fetchLongTermMemories(userMessage),
            conversationSummary.getSummary(chatId, supabase),
        ]);

        settings.chatSummary = chatSummary && chatSummary.length > 1500
            ? chatSummary.slice(0, 1500) + '…'
            : chatSummary;
        const voiceMode = settings.voiceMode === true;
        const maxTokens = voiceMode ? 200 : 800;

        const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings, null, userMessage);
        const msgs = [
            { role: 'system', content: systemPrompt },
            ...chatHistory.map(m => ({ role: m.role === 'jarvis' ? 'assistant' : 'user', content: m.text })),
            { role: 'user', content: userMessage },
        ];

        let fullAnswer = '';
        await callGemma4Stream(msgs, useLocal, (chunk) => {
            fullAnswer += chunk;
            send({ chunk });
        }, controller.signal, maxTokens);

        // Proactive inline nudge (text chat only; skipped in voice mode) — mirrors /ask-jarvis.
        if (agentName === 'chat' && !voiceMode && !/[?？]\s*$/.test(fullAnswer)
            && proactiveEngine.shouldNudgeInline(chatId)) {
            let nudgeTimer;
            try {
                const sug = await Promise.race([
                    proactiveEngine.computeProactiveSuggestion(supabase),
                    new Promise(resolve => { nudgeTimer = setTimeout(() => resolve(null), 400); }),
                ]);
                if (sug) {
                    const extra = `\n\n💡 ${sug.message}`;
                    send({ chunk: extra });
                    fullAnswer += extra;
                    proactiveEngine.markNudged(chatId);
                }
            } catch (_) { /* never block on a nudge */ }
            finally { clearTimeout(nudgeTimer); }
        }

        // In voice mode flutter_tts is the sole audio engine — tell the client
        // not to play the server-side Google TTS audio for this response.
        send({ done: true, chatId, skipAudio: voiceMode });

        await Promise.all([
            saveChatMessage('user', originalMessage, chatId),
            saveChatMessage('jarvis', fullAnswer, chatId),
        ]);
        cacheInvalidate(`chatHistory:${chatId}`);

        // Voice telemetry: record session activity (fire-and-forget, never throws).
        if (voiceMode) {
            feedbackStore.recordEvent(supabase, {
                eventName: 'voice_turn',
                value: 1,
                metadata: { chatId: String(chatId), chars: fullAnswer.length },
            }).catch(() => {});
        }

        // Update rolling summary + passive memory extraction (fire-and-forget)
        setImmediate(() => {
            autoExtractMemory(originalMessage, fullAnswer, supabase, settings).catch(() => {});
            loadChatHistory(chatId).then(fresh => {
                conversationSummary.updateSummaryIfNeeded(chatId, fresh, supabase, settings).catch(() => {});
            }).catch(() => {});
        });
        }); // end providerContext.run
    } catch (err) {
        if (err instanceof LocalModelError) {
            console.warn('🔌 Local model unavailable (stream):', err.url, err.model);
            send({
                chunk: `⚠️ המודל המקומי (${err.model || 'לא ידוע'}) לא זמין בכתובת ${err.url || 'לא מוגדרת'}. ודא ש-Ollama רץ ונגיש מהטלפון, או כבה "מודל מקומי" בהגדרות.`,
                done: true,
                provider: 'ollama',
            });
            return res.end();
        }
        console.error('SSE error:', err.message);
        const isRateLimit = err.response?.status === 429 || /429|rate.limit|quota/i.test(err.message);
        const userMsg = isRateLimit
            ? '⏳ כל ספקי ה-AI עמוסים כרגע (מגבלת קצב). נסה שוב בעוד כמה דקות.'
            : 'שגיאת מערכת.';
        send({ chunk: userMsg, done: true });
    } finally {
        res.end();
    }
}

// ─── Reminder Cron (every minute) ─────────────────────────────────────────────

function computeNextOccurrence(scheduledTimeISO, recurrence) {
    const d = new Date(scheduledTimeISO);
    if (recurrence === 'daily')   d.setDate(d.getDate() + 1);
    else if (recurrence === 'weekly')  d.setDate(d.getDate() + 7);
    else if (recurrence === 'monthly') d.setMonth(d.getMonth() + 1);
    else return null;
    return d;
}

if (!isTestEnv) cron.schedule('* * * * *', async () => {
    try {
        const now = new Date().toISOString();
        const { data: due, error } = await supabase
            .from('reminders')
            .select('id, text, scheduled_time, recurrence')
            .eq('fired', false)
            .lte('scheduled_time', now);

        if (error) { console.error('⏰ Cron error:', error.message); return; }
        if (!due || due.length === 0) return;

        due.forEach(r => console.log(`🔔 REMINDER: ${r.text} [${r.scheduled_time}]${r.recurrence ? ` 🔁 ${r.recurrence}` : ''}`));

        for (const r of due) {
            const next = r.recurrence ? computeNextOccurrence(r.scheduled_time, r.recurrence) : null;
            if (next) {
                // Recurring: reschedule to next occurrence
                await supabase.from('reminders')
                    .update({ scheduled_time: next.toISOString(), fired: false })
                    .eq('id', r.id);
                console.log(`🔁 Rescheduled "${r.text}" → ${next.toISOString()}`);
            } else {
                // One-time: mark as fired
                await supabase.from('reminders').update({ fired: true }).eq('id', r.id);
            }
        }
    } catch (err) {
        console.error('⏰ Cron unexpected error:', err.message);
    }
});

// Hourly cleanup of expired session/recent memories (24h / 7d TTLs).
if (!isTestEnv) cron.schedule('17 * * * *', async () => {
    try {
        const res = await cleanupExpiredMemories(supabase);
        if (res.deleted > 0) cacheInvalidate('memories');
        if (res.errors?.length) console.warn('🧹 memoryCleanup errors:', res.errors);
    } catch (err) {
        console.error('🧹 memoryCleanup unexpected error:', err.message);
    }
});

// ─── Proactive Notification Helpers ──────────────────────────────────────────

async function enqueueNotification(text) {
    await supabase.from('reminders').insert([{
        text,
        scheduled_time: new Date().toISOString(),
        fired: true,
    }]);
}

// ─── Morning briefing builder ─────────────────────────────────────────────────

async function buildMorningBriefing() {
    const nowJer = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
    const todayISO = `${nowJer.getFullYear()}-${String(nowJer.getMonth()+1).padStart(2,'0')}-${String(nowJer.getDate()).padStart(2,'0')}`;
    const dayName = nowJer.toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });

    const dayStart = new Date(nowJer); dayStart.setHours(0, 0, 0, 0);
    const dayEnd   = new Date(nowJer); dayEnd.setHours(23, 59, 59, 999);

    const [{ data: pendingTasks }, { data: todayReminders }, { data: dueTodayTasks }] = await Promise.all([
        supabase.from('tasks').select('id, content, priority').eq('done', false).order('created_at', { ascending: true }).limit(10),
        supabase.from('reminders').select('text, scheduled_time').eq('fired', false)
            .gte('scheduled_time', dayStart.toISOString())
            .lt('scheduled_time', dayEnd.toISOString())
            .order('scheduled_time', { ascending: true }),
        supabase.from('tasks').select('content, priority, due_date').eq('done', false).eq('due_date', todayISO),
    ]);

    let briefing = `🌅 *בוקר טוב! ${dayName}*\n`;

    if (dueTodayTasks?.length > 0) {
        briefing += `\n📅 *משימות ליום זה (${dueTodayTasks.length}):*\n`;
        dueTodayTasks.forEach((t, i) => {
            const prio = t.priority === 'high' ? ' 🔴' : '';
            briefing += `${i + 1}. ${t.content}${prio}\n`;
        });
    } else if (pendingTasks?.length > 0) {
        briefing += `\n📋 יש לך ${pendingTasks.length} משימות פתוחות.`;
        const high = pendingTasks.filter(t => t.priority === 'high');
        if (high.length > 0) briefing += ` ${high.length} דחופות 🔴`;
    } else {
        briefing += `\n✅ אין משימות פתוחות — יום נקי!`;
    }

    if (todayReminders?.length > 0) {
        briefing += `\n\n⏰ *תזכורות להיום (${todayReminders.length}):*\n`;
        todayReminders.slice(0, 5).forEach(r => {
            const timeStr = new Date(r.scheduled_time).toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit' });
            briefing += `• ${r.text} — ${timeStr}\n`;
        });
    }

    // Store in Supabase daily_briefings table (best-effort)
    try {
        await supabase.from('daily_briefings').upsert([{ date: todayISO, content: briefing }], { onConflict: 'date' });
    } catch { /* table may not exist yet */ }

    return briefing;
}

// Morning briefing — 7:00 AM Jerusalem
if (!isTestEnv) cron.schedule('0 7 * * *', async () => {
    try {
        const briefingText = await buildMorningBriefing();
        await enqueueNotification(briefingText);
        console.log('🌅 Morning briefing queued');
    } catch (err) {
        console.error('Morning briefing error:', err.message);
    }
}, { timezone: 'Asia/Jerusalem' });

// Evening nudge — 21:00 Jerusalem (only when tasks remain open)
if (!isTestEnv) cron.schedule('0 21 * * *', async () => {
    try {
        const { data: tasks } = await supabase.from('tasks').select('id');
        if (!tasks || tasks.length === 0) return;

        await enqueueNotification(`יש לך ${tasks.length} משימות פתוחות. לילה טוב ✨`);
        console.log('🌙 Evening nudge queued');
    } catch (err) {
        console.error('Evening nudge error:', err.message);
    }
}, { timezone: 'Asia/Jerusalem' });

// Proactive midday push — 13:00 Jerusalem. Fires at most once/day and only on
// high-signal task states (overdue / stale high-priority), so it complements
// the morning briefing and evening nudge without nagging.
let _lastProactivePushDate = null;
if (!isTestEnv) cron.schedule('0 13 * * *', async () => {
    try {
        const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' });
        if (_lastProactivePushDate === today) return;
        const sug = await proactiveEngine.computeProactiveSuggestion(supabase);
        if (sug && (sug.type === 'overdue' || sug.type === 'stale_high')) {
            await enqueueNotification(`💡 ${sug.message}`);
            _lastProactivePushDate = today;
            console.log('💡 Proactive push queued:', sug.type);
        }
    } catch (err) {
        console.error('Proactive push error:', err.message);
    }
}, { timezone: 'Asia/Jerusalem' });

// P2: Daily cron — 09:00 Jerusalem — flag agents inactive for 7+ days
if (!isTestEnv) cron.schedule('0 9 * * *', async () => {
    try {
        const snap = await agentMetrics.snapshot();
        const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString();
        const inactive = snap.latency.filter(r =>
            r.lastCalledAt && r.lastCalledAt < sevenDaysAgo && r.count > 0);
        if (inactive.length === 0) return;
        const names = inactive.map(r => r.agent).join(', ');
        console.log(`⚠️ Inactive agents (7+ days): ${names}`);
        await supabase.from('agent_metrics_alerts').upsert(
            inactive.map(r => ({
                agent: r.agent,
                alert_type: 'inactive',
                last_called_at: r.lastCalledAt,
                checked_at: new Date().toISOString(),
            })),
            { onConflict: 'agent' }
        ).catch(() => {}); // table may not exist; best-effort
    } catch (err) {
        console.error('Inactive agent cron error:', err.message);
    }
}, { timezone: 'Asia/Jerusalem' });

// Daily cleanup: remove ephemeral memories past their TTL.
// 'session' scope: 7 days; 'recent' scope: 24 hours.
if (!isTestEnv) cron.schedule('30 3 * * *', async () => {
    try {
        const now = new Date();
        const sevenDaysAgo = new Date(now - 7 * 24 * 60 * 60 * 1000).toISOString();
        const oneDayAgo    = new Date(now - 24 * 60 * 60 * 1000).toISOString();
        const { count: c1 } = await supabase.from('memories')
            .delete({ count: 'exact' })
            .eq('scope', 'session')
            .lt('created_at', sevenDaysAgo);
        const { count: c2 } = await supabase.from('memories')
            .delete({ count: 'exact' })
            .eq('scope', 'recent')
            .lt('created_at', oneDayAgo);
        if ((c1 || 0) + (c2 || 0) > 0) {
            console.log(`🧹 Memory cleanup: removed ${c1 || 0} session + ${c2 || 0} recent memories`);
        }
    } catch (err) {
        console.error('Memory cleanup cron error:', err.message);
    }
});

// Daily user-profile learning — 03:45 Jerusalem (after the 03:30 memory cleanup).
// Derives preferred hours / interests / recurring tasks from behaviour and
// writes them into the profile without clobbering fields the user set manually.
if (!isTestEnv) cron.schedule('45 3 * * *', async () => {
    try {
        const r = await profileLearner.learnUserProfile(supabase, { getProfile: getUserProfile });
        if (r.updated) console.log('🧠 User profile auto-learned from behaviour');
        // Refresh the cache so the style learner reads the row profileLearner just
        // wrote and merges into it rather than clobbering its auto_learned keys.
        if (r.updated) cacheInvalidate('userProfile');
        // Style preferences learned from explicit feedback (Phase 2 of the loop).
        const s = await styleLearner.learnStyle(supabase, {
            getProfile: getUserProfile,
            onUpdate: () => cacheInvalidate('userProfile'),
        });
        if (s.updated) console.log('🎯 Style prefs learned from feedback:', JSON.stringify(s.learned));
    } catch (err) {
        console.error('Profile learning cron error:', err.message);
    }
}, { timezone: 'Asia/Jerusalem' });

app.get('/chart.js', (_req, res) => {
    res.sendFile(path.join(__dirname, 'node_modules/chart.js/dist/chart.umd.min.js'),
        err => { if (err && !res.headersSent) res.status(404).send('Not found'); });
});

const { createAgentCenterRouter } = require('./routes/agentCenter');
app.use('/progress-map', _rl(20), createAgentCenterRouter({ callGemma4, agentMetrics }));
app.get('/agent-center', (_req, res) => res.redirect(301, '/progress-map'));

app.get('/projects-dashboard', (_req, res) => {
    res.setHeader(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:",
    );
    res.sendFile(path.join(__dirname, 'project-dashboard.html'),
        err => { if (err && !res.headersSent) res.status(404).send('project-dashboard.html not found'); });
});

app.get('/notes.json', (_req, res) => {
    res.sendFile(path.join(__dirname, 'notes.json'),
        err => { if (err && !res.headersSent) res.status(404).json({ notes: [], lastUpdated: null }); });
});

// ─── Calendar events ─────────────────────────────────────────────────────────
app.get('/calendar-events', async (_req, res) => {
    try {
        const [tasksRes, remindersRes] = await Promise.all([
            supabase.from('tasks')
                .select('id, content, due_date, done')
                .not('due_date', 'is', null)
                .order('due_date', { ascending: true }),
            supabase.from('reminders')
                .select('id, text, scheduled_time, fired')
                .order('scheduled_time', { ascending: true }),
        ]);

        const formatDate = (dateStr) => {
            if (!dateStr) return null;
            try {
                const d = new Date(dateStr);
                return d.toISOString();
            } catch {
                return null;
            }
        };

        const tasks = (tasksRes.data || [])
            .filter(t => formatDate(t.due_date))
            .map(t => ({
                id:    `task-${t.id}`,
                type:  'task',
                title: t.content || 'משימה ללא כותרת',
                date:  formatDate(t.due_date),
                done:  t.done === true,
            }));

        const reminders = (remindersRes.data || [])
            .filter(r => formatDate(r.scheduled_time))
            .map(r => ({
                id:    `reminder-${r.id}`,
                type:  'reminder',
                title: r.text || 'תזכורת ללא טקסט',
                date:  formatDate(r.scheduled_time),
                done:  r.fired === true,
            }));

        const events = [...tasks, ...reminders];
        console.log(`📅 Calendar: returning ${events.length} events (${tasks.length} tasks, ${reminders.length} reminders)`);
        res.json({ events });
    } catch (err) {
        console.error('GET /calendar-events error:', err.message);
        res.status(500).json({ events: [] });
    }
});

// ─── Upcoming tasks/reminders (for proactive suggestions) ───────────────────
app.get('/upcoming-items', async (_req, res) => {
    try {
        const now = new Date();
        const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);

        const [tasksRes, remindersRes] = await Promise.all([
            supabase.from('tasks')
                .select('id, content, due_date, done')
                .not('due_date', 'is', null)
                .eq('done', false)
                .lte('due_date', tomorrow.toISOString())
                .gte('due_date', now.toISOString())
                .order('due_date', { ascending: true })
                .limit(5),
            supabase.from('reminders')
                .select('id, text, scheduled_time, fired')
                .eq('fired', false)
                .lte('scheduled_time', tomorrow.toISOString())
                .gte('scheduled_time', now.toISOString())
                .order('scheduled_time', { ascending: true })
                .limit(5),
        ]);

        const upcoming = [
            ...(tasksRes.data || []).map(t => ({
                type: 'task',
                title: t.content,
                date: t.due_date,
            })),
            ...(remindersRes.data || []).map(r => ({
                type: 'reminder',
                title: r.text,
                date: r.scheduled_time,
            })),
        ].sort((a, b) => new Date(a.date) - new Date(b.date));

        res.json({ upcoming });
    } catch (err) {
        console.error('GET /upcoming-items error:', err.message);
        res.status(500).json({ upcoming: [] });
    }
});

// ─── Dashboard ────────────────────────────────────────────────────────────────
const BACKLOG_PATH = () => path.join(__dirname, 'backlog.json');

const BACKLOG_RANKING_VERSION = 'mvp-v1';
const BACKLOG_RANKING_WEIGHTS = {
    impact: 0.4,
    effort: 0.2, // low effort should rank higher (inverted in score formula)
    risk: 0.2,   // low risk should rank higher (inverted in score formula)
    confidence: 0.2,
};

function clampScore(v) {
    return Math.max(1, Math.min(5, Math.round(v)));
}

function includesAny(text, words = []) {
    return words.some(w => text.includes(w));
}

function classifyProposalSensitivity(proposal = {}) {
    const text = `${(proposal.title || '').toLowerCase()} ${(proposal.plan || '').toLowerCase()} ${(proposal.category || '').toLowerCase()}`;
    if (includesAny(text, ['auth', 'security', 'permission', 'token', 'secret', 'encryption', 'privacy', 'gdpr', 'memory', 'contact', 'personal', 'user data'])) {
        return 'high';
    }
    if (includesAny(text, ['database', 'schema', 'api', 'integration'])) {
        return 'medium';
    }
    return 'low';
}

function scoreProposalRuleBased(proposal = {}) {
    const title = (proposal.title || '').toString().toLowerCase();
    const plan = (proposal.plan || '').toString().toLowerCase();
    const category = (proposal.category || '').toString().toLowerCase();
    const text = `${title} ${plan} ${category}`;

    // Impact: higher for critical user flow improvements.
    let impact = 3;
    if (includesAny(text, ['login', 'signup', 'onboarding', 'chat', 'task', 'reminder', 'payment', 'sync', 'notification', 'voice'])) impact = 5;
    else if (includesAny(text, ['ux', 'ui', 'performance', 'search'])) impact = 4;

    // Effort: lower number = easier change.
    let effort = 3;
    if (includesAny(text, ['refactor', 'migration', 'rewrite', 'architecture', 'cross-platform', 'infra'])) effort = 5;
    else if (includesAny(text, ['small', 'quick', 'copy', 'text', 'label', 'single endpoint', 'נקודתי', 'קטן'])) effort = 1;
    else if (includesAny(text, ['endpoint', 'screen', 'widget', 'field'])) effort = 2;

    // Risk: higher when touching permissions/personal memory/security.
    let risk = 2;
    if (includesAny(text, ['permission', 'auth', 'security', 'token', 'secret', 'personal memory', 'memory', 'privacy', 'gdpr', 'rls', 'encryption'])) risk = 5;
    else if (includesAny(text, ['database', 'schema', 'migration', 'billing'])) risk = 4;
    else if (includesAny(text, ['ui', 'copy', 'style'])) risk = 1;

    // Confidence: lower with broad/unclear scope.
    let confidence = 3;
    if (includesAny(text, ['unknown', 'research', 'investigate', 'maybe', 'experimental'])) confidence = 2;
    if (includesAny(text, ['small', 'quick', 'mvp', 'נקודתי'])) confidence = 5;

    impact = clampScore(impact);
    effort = clampScore(effort);
    risk = clampScore(risk);
    confidence = clampScore(confidence);

    const weightedRaw =
        (impact * BACKLOG_RANKING_WEIGHTS.impact) +
        ((6 - effort) * BACKLOG_RANKING_WEIGHTS.effort) +
        ((6 - risk) * BACKLOG_RANKING_WEIGHTS.risk) +
        (confidence * BACKLOG_RANKING_WEIGHTS.confidence);

    const weighted_score = Number(weightedRaw.toFixed(2));
    const why_now = impact >= 4
        ? 'משפר זרימת משתמש קריטית עם יחס עלות-תועלת טוב כרגע.'
        : risk >= 4
            ? 'חשוב לטפל עכשיו כדי לצמצם סיכון בהרשאות/אבטחה/פרטיות.'
            : 'מומלץ לקדם כעת כדי לייצר שיפור מהיר ובטוח לחוויית המשתמש.';

    return { impact, effort, risk, confidence, weighted_score, why_now };
}

function readBacklog() {
    try {
        const data = JSON.parse(require('fs').readFileSync(BACKLOG_PATH(), 'utf8'));
        if (!data.items)     data.items     = [];
        if (!data.proposals) data.proposals = [];
        if (!data.proposals_history) data.proposals_history = [];
        if (!data.ranking_version) data.ranking_version = BACKLOG_RANKING_VERSION;
        if (!data._nextId)   data._nextId   = (data.items.length > 0 ? Math.max(...data.items.map(i => i.id)) + 1 : 1);
        return data;
    } catch {
        return {
            items: [],
            proposals: [],
            proposals_history: [],
            ranking_version: BACKLOG_RANKING_VERSION,
            _nextId: 1,
        };
    }
}
function writeBacklog(data) {
    require('fs').writeFileSync(BACKLOG_PATH(), JSON.stringify(data, null, 2));
}


const PROGRESS_MAP_SCHEMA_PATH = path.join(__dirname, 'progress_map_schema.json');
const PROGRESS_MAP_CONFIG = {
    statuses: ['proposal', 'draft_plan', 'active', 'validation', 'done'],
    priorityLevels: ['high', 'medium', 'low'],
    statusFilters: ['all', 'proposal', 'draft_plan', 'active', 'validation', 'done'],
    priorityFilters: ['all', 'high', 'medium', 'low'],
    labels: {
        status: {
            proposal: '💡 הצעה', draft_plan: '🧭 תכנון', active: '⚡ פעיל', validation: '🧪 ולידציה', done: '✅ הושלם', all: 'הכל',
        },
        priority: { high: '🔴 גבוה', medium: '🟡 בינוני', low: '🟢 נמוך', all: 'הכל' },
    },
};

function buildRoadmapNodes(features = {}, proposals = []) {
    return [
        { id: 'done', title: `הושלם (${(features.done || []).length})`, description: 'יכולות בפרודקשן', status: 'done' },
        { id: 'building', title: `בבנייה (${(features.building || []).length})`, description: 'יכולות בפיתוח', status: 'active' },
        { id: 'planned', title: `מתוכנן (${(features.planned || []).length})`, description: `בקנה: ${proposals.filter((p) => p.status === 'proposal').length} הצעות`, status: 'proposal' },
    ];
}

function buildProgressMetrics(features = {}, proposals = []) {
    return {
        done_features: (features.done || []).length,
        building_features: (features.building || []).length,
        planned_features: (features.planned || []).length,
        proposal_count: proposals.filter((p) => p.status === 'proposal').length,
        active_proposal_count: proposals.filter((p) => p.status === 'active').length,
    };
}

function validateProgressMapPayload(payload) {
    if (!payload || typeof payload !== 'object') return { ok: false, error: 'payload must be an object' };
    if (!Array.isArray(payload.proposals)) return { ok: false, error: 'proposals must be an array' };
    for (const p of payload.proposals) {
        if (typeof p.id !== 'number') return { ok: false, error: 'proposal.id must be number' };
        if (typeof p.title !== 'string') return { ok: false, error: 'proposal.title must be string' };
        if (typeof p.plan !== 'string') return { ok: false, error: 'proposal.plan must be string' };
        if (!PROGRESS_MAP_CONFIG.statuses.includes(p.status)) return { ok: false, error: `invalid proposal.status: ${p.status}` };
        if (!PROGRESS_MAP_CONFIG.priorityLevels.includes(p.priority)) return { ok: false, error: `invalid proposal.priority: ${p.priority}` };
    }
    if (!Array.isArray(payload.roadmap_nodes)) return { ok: false, error: 'roadmap_nodes must be an array' };
    if (!payload.metrics || typeof payload.metrics !== 'object') return { ok: false, error: 'metrics must be object' };
    return { ok: true };
}

const PROPOSAL_STATUSES = ['proposal', 'draft_plan', 'active', 'validation', 'done'];
const PROPOSAL_ACTIONS = Object.freeze({
    startPlanning: {
        actionType: 'start_planning',
        targetStatus: 'draft_plan',
        message: 'תוכנית עבודה ראשונית נפתחה.',
    },
    startExecution: {
        actionType: 'start_execution',
        targetStatus: 'active',
        message: 'הצעה עברה לביצוע.',
    },
    sendToValidation: {
        actionType: 'send_to_validation',
        targetStatus: 'validation',
        message: 'הצעה עברה לולידציה.',
    },
    markDone: {
        actionType: 'mark_done',
        targetStatus: 'done',
        message: 'הצעה סומנה כהושלמה.',
    },
    rollbackToActive: {
        actionType: 'rollback_to_active',
        targetStatus: 'active',
        message: 'הצעה הוחזרה לביצוע פעיל.',
    },
});
const PROPOSAL_ACTION_TYPES = Object.values(PROPOSAL_ACTIONS).map((x) => x.actionType);

function resolveProposalActor(req) {
    const authHeader = String(req.headers.authorization || '');
    const bearerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
    const sessionUserId = req.headers['x-session-user-id'] || req.headers['x-user-id'];
    const tokenUserId = bearerToken.startsWith('demo-') ? bearerToken.slice(5).trim() : '';
    const userId = String(tokenUserId || sessionUserId || '').trim();
    if (!userId) return { ok: false, error: 'unauthorized' };
    return { ok: true, userId, actor: `user:${userId}` };
}

function normalizeProposalForMvp(p) {
    if (!Array.isArray(p.auditTrail)) p.auditTrail = [];
    if (!Array.isArray(p.checklist)) p.checklist = [];
    if (!Array.isArray(p.blockers)) p.blockers = [];
    if (!Array.isArray(p.acceptanceCriteria)) p.acceptanceCriteria = [];
    if (!p.owner || !['agent', 'human'].includes(p.owner)) p.owner = 'agent';
    if (!p.estimation || typeof p.estimation !== 'string') p.estimation = 'MVP';
    if (!p.sprint || typeof p.sprint !== 'string') p.sprint = 'sprint-1';
    if (!p.privacyChecklist || typeof p.privacyChecklist !== 'object') {
        p.privacyChecklist = {
            permissionScopeChecked: false,
            piiExposureChecked: false,
            memoryRetentionReviewed: false,
        };
    }
    if (!PROPOSAL_STATUSES.includes(p.status)) p.status = 'proposal';
    return p;
}

function canTransitionProposalStatus(from, to) {
    if (from === to) return true;
    const allowed = {
        proposal: ['draft_plan'],
        draft_plan: ['active', 'proposal'],
        active: ['validation', 'draft_plan'],
        validation: ['done', 'active'],
        done: ['validation'],
    };
    return (allowed[from] || []).includes(to);
}

app.get('/dashboard/features', (_req, res) => {
    try {
        const data = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'features.json'), 'utf8'));
        res.json(data);
    } catch { res.status(500).json({ error: 'features.json not found' }); }
});

app.get('/dashboard/backlog/config', (_req, res) => {
    res.json(PROGRESS_MAP_CONFIG);
});

app.get('/dashboard/backlog/schema', (_req, res) => {
    try {
        const schema = JSON.parse(require('fs').readFileSync(PROGRESS_MAP_SCHEMA_PATH, 'utf8'));
        res.json(schema);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.get('/dashboard/backlog', (_req, res) => {
    const data = readBacklog();

    // Normalize old proposals and ensure Stage-1 scoring exists for every item.
    data.proposals = (data.proposals || []).map((p) => {
        normalizeProposalForMvp(p);
        if (!p.scores || typeof p.scores !== 'object') {
            const scored = scoreProposalRuleBased(p);
            p.scores = {
                impact: scored.impact,
                effort: scored.effort,
                risk: scored.risk,
                confidence: scored.confidence,
                weighted_score: scored.weighted_score,
            };
            p.why_now = p.why_now || scored.why_now;
        }
        if (!p.why_now) {
            const rescored = scoreProposalRuleBased(p);
            p.why_now = rescored.why_now;
        }
        p.ranking_version = p.ranking_version || BACKLOG_RANKING_VERSION;
        return p;
    }).sort((a, b) => (b.scores?.weighted_score || 0) - (a.scores?.weighted_score || 0));

    const topInsights = (data.proposals || [])
        .sort((a, b) => (b.outcomes?.outcome_score || 0) - (a.outcomes?.outcome_score || 0))
        .slice(0, 3)
        .map((p) => {
            const kept = p.outcomes?.kept_count || 0;
            const total = p.outcomes?.completed_count || 0;
            const ttv = p.outcomes?.avg_time_to_value_sec;
            const ttvText = Number.isFinite(ttv) ? `⏱️ זמן-ערך ממוצע: ${Math.round(ttv / 60)} דק׳` : '⏱️ זמן-ערך עדיין נלמד';
            return `למדנו ש־${p.title || 'הצעה'} נשמרה ${kept}/${Math.max(total, 1)} פעמים. ${ttvText}`;
        });

    const featuresData = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'features.json'), 'utf8'));
    const progressPayload = {
        ...data,
        ranking_version: data.ranking_version || BACKLOG_RANKING_VERSION,
        learned_insights: topInsights,
        roadmap_nodes: buildRoadmapNodes(featuresData.features || {}, data.proposals || []),
        metrics: buildProgressMetrics(featuresData.features || {}, data.proposals || []),
        config: PROGRESS_MAP_CONFIG,
    };
    const validation = validateProgressMapPayload(progressPayload);
    if (!validation.ok) {
        return res.status(500).json({ error: `progress payload validation failed: ${validation.error}` });
    }
    res.json(progressPayload);
});

app.post('/dashboard/backlog', (req, res) => {
    try {
        const { text } = req.body;
        if (!text || !text.trim()) return res.status(400).json({ error: 'text required' });
        const data = readBacklog();
        const item = { id: data._nextId, text: text.trim(), done: false, added: new Date().toISOString().slice(0, 10) };
        data.items.unshift(item);
        data._nextId++;
        writeBacklog(data);
        res.json({ item });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// proposals routes must come BEFORE /:id catch-all
app.patch('/dashboard/backlog/proposals/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const data = readBacklog();
        const item = data.proposals.find(p => p.id === id);
        if (!item) return res.status(404).json({ error: 'not found' });

        normalizeProposalForMvp(item);

        const requestedStatus = (req.body?.status || '').toString();
        const actor = (req.body?.actor || 'system').toString().slice(0, 40);
        const reason = (req.body?.reason || '').toString().slice(0, 200);
        const nextStatus = requestedStatus || item.status;

        if (!PROPOSAL_STATUSES.includes(nextStatus)) {
            return res.status(400).json({ error: 'invalid status' });
        }
        if (!canTransitionProposalStatus(item.status, nextStatus)) {
            return res.status(400).json({ error: `invalid transition: ${item.status} -> ${nextStatus}` });
        }
        if (nextStatus === 'done' && item.status !== 'validation') {
            return res.status(400).json({ error: 'cannot move to done before validation' });
        }

        const prev = item.status;
        item.status = nextStatus;
        item.auditTrail.unshift({
            from: prev,
            to: nextStatus,
            by: actor,
            reason: reason || 'status update',
            at: new Date().toISOString(),
        });
        item.auditTrail = item.auditTrail.slice(0, 20);
        writeBacklog(data);
        res.json({ item });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/dashboard/backlog/proposals/:id/draft-plan', (req, res) => {
    try {
        const id = parseInt(req.params.id, 10);
        const data = readBacklog();
        const item = data.proposals.find(p => p.id === id);
        if (!item) return res.status(404).json({ error: 'not found' });
        normalizeProposalForMvp(item);
        if (!canTransitionProposalStatus(item.status, 'draft_plan')) {
            return res.status(400).json({ error: `invalid transition: ${item.status} -> draft_plan` });
        }

        const body = req.body || {};
        const steps = Array.isArray(body.steps) ? body.steps : [
            'להגדיר API schema וסוגי סטטוסים',
            'להטמיע ולידציה ו-audit trail',
            'לעדכן UI למסכי ניהול התקדמות',
            'בדיקות זרימה מקצה לקצה',
        ];
        const acceptanceCriteria = Array.isArray(body.acceptanceCriteria) ? body.acceptanceCriteria : [
            'יש מעבר מלא proposal→draft_plan→active→validation→done',
            'אי אפשר לעבור ל-done לפני validation',
            'לכל מעבר סטטוס נשמר audit trail',
        ];
        item.checklist = steps.map((s, i) => ({ id: i + 1, text: String(s), done: false }));
        item.owner = ['agent', 'human'].includes(body.owner) ? body.owner : 'agent';
        item.estimation = (body.estimation || 'MVP / 1 sprint').toString();
        item.sprint = 'sprint-1';
        item.blockers = Array.isArray(body.blockers) ? body.blockers.map(String) : [];
        item.acceptanceCriteria = acceptanceCriteria.map(String);
        item.privacyChecklist = {
            permissionScopeChecked: Boolean(body.privacyChecklist?.permissionScopeChecked),
            piiExposureChecked: Boolean(body.privacyChecklist?.piiExposureChecked),
            memoryRetentionReviewed: Boolean(body.privacyChecklist?.memoryRetentionReviewed),
        };

        const prev = item.status;
        item.status = 'draft_plan';
        item.auditTrail.unshift({
            from: prev,
            to: 'draft_plan',
            by: (body.actor || 'system').toString().slice(0, 40),
            reason: (body.reason || 'draft plan created').toString().slice(0, 200),
            at: new Date().toISOString(),
        });
        item.auditTrail = item.auditTrail.slice(0, 20);

        writeBacklog(data);
        res.json({ item });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.delete('/dashboard/backlog/proposals/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const data = readBacklog();
        data.proposals = data.proposals.filter(p => p.id !== id);
        writeBacklog(data);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/proposals/:id/action', (req, res) => {
    try {
        const auth = resolveProposalActor(req);
        if (!auth.ok) return res.status(401).json({ ok: false, message: 'Unauthorized' });

        const id = parseInt(req.params.id, 10);
        if (!Number.isInteger(id)) return res.status(400).json({ ok: false, message: 'Invalid proposal id' });

        const actionType = String(req.body?.actionType || '').trim();
        if (!PROPOSAL_ACTION_TYPES.includes(actionType)) {
            return res.status(400).json({
                ok: false,
                proposalId: id,
                message: `Unsupported actionType. Supported: ${PROPOSAL_ACTION_TYPES.join(', ')}`,
            });
        }

        const data = readBacklog();
        const item = (data.proposals || []).find((p) => p.id === id);
        if (!item) return res.status(404).json({ ok: false, proposalId: id, message: 'Proposal not found' });

        normalizeProposalForMvp(item);
        const proposalOwnerId = String(item.userId || item.ownerUserId || '').trim();
        if (proposalOwnerId && proposalOwnerId !== auth.userId) {
            return res.status(403).json({ ok: false, proposalId: id, message: 'Forbidden: proposal does not belong to this user' });
        }

        const actionConfig = Object.values(PROPOSAL_ACTIONS).find((a) => a.actionType === actionType);
        const nextStatus = actionConfig.targetStatus;
        if (!canTransitionProposalStatus(item.status, nextStatus)) {
            return res.status(400).json({
                ok: false,
                proposalId: id,
                newStatus: item.status,
                message: `Invalid transition: ${item.status} -> ${nextStatus}`,
            });
        }

        const previousStatus = item.status;
        item.status = nextStatus;
        const auditId = `audit-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
        item.auditTrail.unshift({
            id: auditId,
            from: previousStatus,
            to: nextStatus,
            by: auth.actor,
            reason: `action:${actionType}`,
            executionMode: 'stub',
            at: new Date().toISOString(),
        });
        item.auditTrail = item.auditTrail.slice(0, 20);
        if (!proposalOwnerId) item.ownerUserId = auth.userId;

        writeBacklog(data);
        return res.json({
            ok: true,
            proposalId: id,
            newStatus: nextStatus,
            message: `${actionConfig.message} (stub execution)`,
            auditId,
        });
    } catch (e) {
        return res.status(500).json({ ok: false, message: e.message });
    }
});

app.patch('/dashboard/backlog/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const data = readBacklog();
        const item = data.items.find(i => i.id === id);
        if (!item) return res.status(404).json({ error: 'not found' });
        item.done = !item.done;
        writeBacklog(data);
        res.json({ item });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/dashboard/backlog/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const data = readBacklog();
        data.items = data.items.filter(i => i.id !== id);
        writeBacklog(data);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// ─── Dashboard – AI backlog generation ───────────────────────────────────────
app.post('/dashboard/backlog/generate', async (_req, res) => {
    try {
        const features = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'features.json'), 'utf8'));
        const backlog  = readBacklog();

        const done     = features.features?.done     || [];
        const building = features.features?.building || [];
        const planned  = features.features?.planned  || [];

        const prompt = `You are a senior project manager for "Jarvis" — a personal AI assistant built with Flutter + Node.js.

Project status:
DONE (${done.length}): ${done.map(f => f.name).join(', ')}
IN PROGRESS (${building.length}): ${building.map(f => `${f.name}`).join(', ')}
PLANNED (${planned.length}): ${planned.map(f => `${f.name}`).join(', ')}

Suggest 6 high-priority backlog items sorted by urgency.

IMPORTANT: Respond with ONLY a JSON array. No markdown, no explanation, no code blocks. Use ONLY these exact English field names.

Output format (copy exactly, replace the values):
[{"title":"short title in Hebrew (max 60 chars)","plan":"detailed plan in Hebrew (3-4 sentences: what to do, why it matters, how to implement technically)","priority":"high","category":"improvement"},{"title":"...","plan":"...","priority":"medium","category":"feature"}]`;

        const raw = await callGemma4(prompt, false, 2000);

        // Extract JSON array — strip markdown code fences, find first [ ... ] block
        const stripped = raw.replace(/```(?:json)?/gi, '').replace(/```/g, '');
        let parsed;
        try {
            // Try to find outermost [...] array
            const start = stripped.indexOf('[');
            const end   = stripped.lastIndexOf(']');
            if (start === -1 || end === -1 || end <= start) throw new Error('no array');
            parsed = JSON.parse(stripped.slice(start, end + 1));
            if (!Array.isArray(parsed)) throw new Error('not array');
        } catch (parseErr) {
            console.error('backlog/generate: no JSON array found in LLM output:', raw.slice(0, 200));
            return res.status(500).json({ error: 'מודל ה-AI לא החזיר JSON תקין — נסה שוב' });
        }

        // Map both English and Hebrew field name variants
        const baseId = backlog._nextId;
        backlog._nextId += 6;
        const proposals = parsed.slice(0, 6).map((p, i) => {
            const generated_at = new Date().toISOString().slice(0, 10);
            const baseProposal = {
            id: baseId + i,
            title:    ((p.title    || p['כותרת']   || p['כותרת:'] || '').toString()).slice(0, 80),
            plan:     ((p.plan     || p['תוכנית']  || p['תכנית']  || p['תיאור'] || '').toString()),
            priority: ['high', 'medium', 'low'].includes(p.priority || p['עדיפות'])
                ? (p.priority || p['עדיפות']) : 'medium',
            category: (p.category || p['קטגוריה'] || 'improvement').toString(),
            status: 'proposal',
            generated_at,
            ranking_version: BACKLOG_RANKING_VERSION,
            scores: {
                impact: 3, effort: 3, risk: 2, confidence: 3, weighted_score: 3.2,
            },
            why_now: '',
            };
            const scored = scoreProposalRuleBased(baseProposal);
            return {
                ...baseProposal,
                scores: {
                    impact: scored.impact,
                    effort: scored.effort,
                    risk: scored.risk,
                    confidence: scored.confidence,
                    weighted_score: scored.weighted_score,
                },
                why_now: scored.why_now,
                policyGate: {
                    sensitivity: classifyProposalSensitivity(baseProposal),
                    requiresPrivacyApproval: true,
                    consent: {
                        policyVersion: null,
                        approvedAt: null,
                        expiresAt: null,
                        doubleApprovedAt: null,
                        dataUsageExplanation: null,
                    },
                },
            };
        }).filter(p => p.title.trim() || p.plan.trim()) // drop truly empty items
            .sort((a, b) => b.scores.weighted_score - a.scores.weighted_score);

        if (proposals.length === 0) {
            console.error('backlog/generate: all proposals had empty title+plan. Raw:', raw.slice(0, 300));
            return res.status(500).json({ error: 'לא הצלחתי לחלץ הצעות — נסה שוב' });
        }

        backlog.proposals      = proposals;
        backlog._lastGenerated = new Date().toISOString().slice(0, 10);
        backlog.ranking_version = BACKLOG_RANKING_VERSION;
        backlog.proposals_history.unshift({
            snapshot_at: new Date().toISOString(),
            ranking_version: BACKLOG_RANKING_VERSION,
            proposals: proposals.map(p => ({
                id: p.id,
                title: p.title,
                scores: p.scores,
                why_now: p.why_now,
            })),
        });
        backlog.proposals_history = backlog.proposals_history.slice(0, 100);
        writeBacklog(backlog);
        res.json({ proposals, generated_at: backlog._lastGenerated, ranking_version: BACKLOG_RANKING_VERSION });
    } catch (e) {
        console.error('backlog/generate error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

// ─── Dashboard – Claude Code prompt generator ────────────────────────────────
app.post('/dashboard/generate-prompt', async (req, res) => {
    try {
        const { description } = req.body;
        if (!description?.trim()) return res.status(400).json({ error: 'description required' });

        const prompt = `אתה מומחה בכתיבת הוראות מדויקות ל-Claude Code — עוזר הקוד של Anthropic.

הקשר פרויקט Jarvis:
- אפליקציית Flutter (ממשק עברית RTL) עם ORB קולי, צ'אט, משימות, תזכורות, פתקים, קניות, לוח שנה
- שרת Node.js (server.js) עם 17+ אייג'נטים בתיקיית agents/ (router.js, chatAgent.js, taskAgent.js וכו')
- Supabase כ-DB, Pinecone לזיכרון סמנטי, LLMs (Groq → DeepSeek → Gemini כ-fallback)
- קבצים מרכזיים: server.js, jarvis_mobile/lib/main.dart, agents/router.js, agents/models.js

בקשת המפתח: "${description.trim()}"

כתוב פרומפט מפורט ל-Claude Code שהמפתח יוכל להדביק ישירות כדי לממש את הפיצ'ר. הפרומפט צריך:
- להיות ישיר ומעשי ללא הקדמות — כאילו כותבים הוראות לעוזר קוד
- לציין קבצים ספציפיים לשינוי (עם נתיבים)
- לפרט שינויים בצד שרת ו/או Flutter לפי הצורך
- לכלול endpoints חדשים, widgets, schemas — כל מה שנחוץ למימוש מלא
- לסיים בהוראת בדיקה / וידוא

כתוב את הפרומפט בעברית, מוכן להדבקה ב-Claude Code:`;

        const result = await callGemma4(prompt, false, 1500);
        res.json({ prompt: result });
    } catch (e) {
        console.error('generate-prompt error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

// ─── Dashboard – Graph actions (MVP) ────────────────────────────────────────
app.post('/dashboard/graph/action', (req, res) => {
    try {
        const { nodeId, nodeLabel, nodeType, action, source = 'unknown', actor = 'anonymous' } = req.body || {};
        if (!action || !nodeType) {
            return res.status(400).json({ error: 'action and nodeType are required' });
        }
        const allow = new Set(['activate', 'defer', 'split']);
        if (!allow.has(action)) return res.status(400).json({ error: 'invalid action' });

        const data = readBacklog();
        let updated = null;

        if (nodeType === 'proposal') {
            const item = (data.proposals || []).find(p =>
                (nodeId && String(p.id) === String(nodeId)) ||
                (nodeLabel && (p.title || '').trim() === String(nodeLabel).trim())
            );
            if (!item) return res.status(404).json({ error: 'proposal not found' });

            if (action === 'activate') item.status = 'active';
            if (action === 'defer') item.status = 'draft_plan';
            if (action === 'split') {
                const baseId = data._nextId || 1000;
                data._nextId = baseId + 1;
                const splitItem = {
                    ...item,
                    id: baseId,
                    title: `${item.title} · חלק ב׳`,
                    status: 'proposal',
                    createdAt: new Date().toISOString(),
                };
                data.proposals.push(splitItem);
            }
            updated = { id: item.id, title: item.title, status: item.status };
            writeBacklog(data);
        }

        const event = {
            ts: new Date().toISOString(),
            actor,
            source,
            action,
            nodeType,
            nodeId: nodeId ?? null,
            nodeLabel: nodeLabel ?? null,
        };
        console.log('[graph-action]', JSON.stringify(event));
        return res.json({ ok: true, updated, audit: event });
    } catch (e) {
        console.error('graph/action error:', e.message);
        return res.status(500).json({ error: 'graph action failed' });
    }
});

cron.schedule('17 2 * * *', async () => {
    try {
        const data = readBacklog();
        for (const p of (data.proposals || [])) {
            normalizeProposalForMvp(p);
            recomputeProposalOutcomeScore(p);
            p.scores.weighted_score = Number(((p.scores?.weighted_score || 0) + p.outcomes.outcome_score * 0.3).toFixed(2));
        }
        writeBacklog(data);
    } catch (e) {
        console.error('daily rescore failed:', e.message);
    }
});

// ─── Start ────────────────────────────────────────────────────────────────────

module.exports = { app, cacheInvalidate };

if (require.main === module) {
    const PORT = process.env.PORT || 3000;
    const server = app.listen(PORT, () => {
        console.log(`🚀 JARVIS ONLINE | MULTI-AGENT v3 | PORT: ${PORT}`);
        // Init Pinecone and sync existing memories in background (non-blocking)
        pinecone.ensureInit().then(() => pinecone.syncFromSupabase(supabase)).catch(() => {});
    });

    // ── Live talk WebSocket ─────────────────────────────────────────────────
    const { WebSocketServer } = require('ws');
    const { createWsHandler } = require('./routes/wsJarvis');
    const _wsAllowedOrigins = _corsOrigins;
    const wss = new WebSocketServer({
        server,
        path: '/ws-jarvis',
        maxPayload: 64 * 1024, // 64 KB per frame
        verifyClient: ({ origin }) => {
            if (!_wsAllowedOrigins) return true; // dev mode: allow all
            if (!origin) return true;            // non-browser clients (mobile app)
            return _wsAllowedOrigins.includes(origin);
        },
    });
    const wsHandler = createWsHandler({
        classifyIntent,
        contextResolver,
        loadChatHistory,
        fetchLongTermMemories,
        conversationSummary,
        buildSystemPrompt,
        callGemma4Stream,
        runChatAgent,
        runWeatherAgent,
        runNewsAgent,
        runStocksAgent,
        runTranslationAgent,
        saveChatMessage,
        cacheInvalidate,
        autoExtractMemory,
        generateSpeech,
        supabase,
    });
    wss.on('connection', wsHandler);
    console.log(`🔊 Live talk WebSocket mounted at /ws-jarvis`);

    function shutdown(signal) {
        console.log(`\n${signal} received — shutting down gracefully...`);
        server.close(() => {
            console.log('✅ HTTP server closed. Goodbye.');
            process.exit(0);
        });
        setTimeout(() => { console.error('⚠️ Forced exit after timeout.'); process.exit(1); }, 10_000).unref();
    }

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT',  () => shutdown('SIGINT'));
}
