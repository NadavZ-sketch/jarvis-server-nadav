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

const pushService = require('./services/pushService');
const systemLog   = require('./services/systemLog');

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
    const urlRegex = /https?:\/\/[^\s<>"']+/g;
    const htmlBody = body
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(urlRegex, url => `<a href="${url}" style="color:#1a73e8">${url}</a>`)
        .replace(/\n/g, '<br>');
    await mailTransporter.sendMail({
        from: `"Jarvis" <${process.env.GMAIL_USER}>`,
        to,
        subject: 'הודעה מג\'רביס',
        text: body,
        html: `<div dir="rtl" style="font-family:Arial,sans-serif;font-size:15px;line-height:1.6">${htmlBody}</div>`,
    });
    console.info(`[email] sent to ${to}`);
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
const { runE2EAgent, buildClaudePrompt, countsBySeverity, computeScore, persistFindings } = require('./agents/e2eAgent');
const { SURVEY_QUESTIONS, selectSurveyQuestions, buildSurveyJson, buildSurveySummary, aggregateSurveys, insightsFromAggregation, isNegativeAnswer } = require('./agents/surveyAgent');
const { runManusAgent, isManusConfigured } = require('./agents/manusAgent');
const { analyzePatterns, optimizeDayPlan, runInsightAgent } = require('./agents/insightAgent');
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
const dashboardLearner = require('./services/dashboardLearner');
const { selectByTokenBudget } = require('./services/contextWindow');
const documentParser = require('./services/documentParser');
const { runCalendarAgent, buildAuthUrl, getAccessToken } = require('./agents/calendarAgent');
const { runPromptAgent }      = require('./agents/promptAgent');
const { runSettingsAgent }    = require('./agents/settingsAgent');
const { runProjectAgent, buildProjectsBriefing } = require('./agents/projectAgent');
const { runHabitAgent }       = require('./agents/habitAgent');
const dispatcher              = require('./agents/dispatcher');

// Single AGENTS map passed into the dispatcher so intent→agent wiring lives in
// one place (agents/dispatcher.js) instead of duplicated if/else chains.
const AGENTS = {
    runTaskAgent, runReminderAgent, runMemoryAgent, runWeatherAgent, runNewsAgent,
    runShoppingAgent, runNotesAgent, runStocksAgent, runTranslationAgent, runMusicAgent,
    runSportsAgent, runMessagingAgent, runDraftAgent,
    runCalendarAgent, runPromptAgent, runSettingsAgent, runProjectAgent, runHabitAgent, runInsightAgent,
    runSecurityAgent, runCodeErrorAgent, runE2EAgent, runManusAgent,
};

// MCP client manager — non-blocking init, guarded behind MCP_ENABLED flag.
// Jarvis boots normally even if MCP servers are unreachable.
if (process.env.MCP_ENABLED === 'true') {
    const mcpClientManager = require('./services/mcp/mcpClientManager');
    mcpClientManager.init().catch(err => console.warn('[MCP] Boot init error:', err.message));
}

const pinecone                = require('./services/pineconeMemory');
const obsidianSync            = require('./services/obsidianSync');
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

// Parse an optional lead time from the confirmation reply, e.g. "כן, שעתיים לפני",
// "כן יומיים לפני", "כן 3 ימים לפני", "כן שבוע לפני". Returns the number of hours
// before the due date to fire. Defaults to a full day (24h) when unspecified.
function parseReminderLead(userMessage) {
    const m = userMessage;
    // hours
    if (/שעתיים\s+לפני/.test(m)) return { hours: 2, label: 'שעתיים' };
    const hourMatch = m.match(/(\d+)\s*שעות?\s+לפני/);
    if (hourMatch) return { hours: parseInt(hourMatch[1], 10), label: `${hourMatch[1]} שעות` };
    if (/שעה\s+לפני/.test(m)) return { hours: 1, label: 'שעה' };
    // days
    if (/יומיים\s+לפני/.test(m)) return { hours: 48, label: 'יומיים' };
    const dayMatch = m.match(/(\d+)\s*ימים\s+לפני/);
    if (dayMatch) return { hours: parseInt(dayMatch[1], 10) * 24, label: `${dayMatch[1]} ימים` };
    if (/שבוע\s+לפני/.test(m)) return { hours: 24 * 7, label: 'שבוע' };
    return { hours: 24, label: 'יום' }; // default: one day before
}

async function handleTaskReminderConfirmation(userMessage) {
    const pending = await loadTaskReminderPending();
    if (!pending) return null;

    if (TASK_REM_YES.test(userMessage.trim())) {
        const { taskContent, dueDate } = pending;
        const lead = parseReminderLead(userMessage);

        // Anchor the due date at 09:00, then subtract the requested lead time.
        const reminderDate = new Date(dueDate);
        reminderDate.setHours(9, 0, 0, 0);
        reminderDate.setHours(reminderDate.getHours() - lead.hours);

        const pad = n => String(n).padStart(2, '0');
        const isoReminder = `${reminderDate.getFullYear()}-${pad(reminderDate.getMonth()+1)}-${pad(reminderDate.getDate())}T${pad(reminderDate.getHours())}:${pad(reminderDate.getMinutes())}:00+03:00`;

        try {
            await supabase.from('reminders').insert([{ text: `לסיים משימה: ${taskContent}`, scheduled_time: isoReminder }]);
        } catch { /* ignore */ }

        await clearTaskReminderPending();
        const dateStr = reminderDate.toLocaleString('he-IL', { timeZone: 'Asia/Jerusalem', weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
        return { answer: `✅ הגדרתי תזכורת ל${dateStr} (${lead.label} לפני) לסיים את: "${taskContent}"` };
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

// Pure policy decision: given the action, its flags, the actor, and the
// consent/confirmation signals already extracted from the request, decide the
// outcome. No req/res, no env checks, no side effects — so it's unit-testable
// directly (the requirePolicy middleware below is a thin wrapper around it).
function evaluatePolicy({
    actionType,
    sensitive = false,
    irreversible = false,
    actor,
    explicitConsent = false,
    consentAlreadyGranted = false,
    confirmed = false,
}) {
    if (isBlockedAction(actionType)) {
        return { result: 'blocked', status: 403, code: 'ACTION_BLOCKED', message: 'This action is blocked by policy.', storeConsent: false };
    }
    if (!isAllowedByRolePlan({ actionType, role: actor.role, plan: actor.plan })) {
        return { result: 'denied_not_allowed', status: 403, code: 'INSUFFICIENT_PERMISSION', message: 'Your role/plan is not allowed to perform this action.', storeConsent: false };
    }
    if (sensitive && !explicitConsent && !consentAlreadyGranted) {
        return { result: 'denied_no_consent', status: 403, code: 'CONSENT_REQUIRED', message: 'Explicit consent is required for sensitive actions.', storeConsent: false };
    }
    // Consent granted now is persisted regardless of a later confirmation gate.
    const storeConsent = !!(sensitive && explicitConsent);
    if (irreversible && !confirmed) {
        return { result: 'denied_missing_confirmation', status: 409, code: 'CONFIRMATION_REQUIRED', message: 'Are you sure? confirmation is required for irreversible action.', storeConsent };
    }
    return { result: 'allowed', storeConsent };
}

function requirePolicy(actionType, options = {}) {
    const { sensitive = false, irreversible = false } = options;
    return (req, res, next) => {
        if (process.env.NODE_ENV === 'test') return next();
        const actor = getActor(req);
        const explicitConsent = req.body?.consent === true || String(req.headers['x-user-consent'] || '').toLowerCase() === 'true';
        const consentAlreadyGranted = hasStoredConsent(actor.userId, actionType);
        const confirmed = req.body?.confirm === true || String(req.headers['x-confirm-action'] || '').toLowerCase() === 'yes';

        const decision = evaluatePolicy({ actionType, sensitive, irreversible, actor, explicitConsent, consentAlreadyGranted, confirmed });

        if (decision.storeConsent) storeConsent(actor.userId, actionType);
        auditPolicy({ userId: actor.userId, actionType, result: decision.result });

        if (decision.result !== 'allowed') {
            return res.status(decision.status).json({ ok: false, code: decision.code, message: decision.message });
        }
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
    allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key', 'X-User-Id', 'X-User-Role', 'X-User-Plan', 'X-User-Consent', 'X-Confirm-Action', 'X-Jarvis-Key'],
}));

app.use(express.json({ limit: '10mb' }));

// ─── API Key auth middleware ──────────────────────────────────────────────────
// Single shared-secret check for a personal single-user deployment.
// Set JARVIS_API_KEY in production. When the var is unset the middleware is a
// no-op so all 78 test files keep passing without changes.
const _JARVIS_API_KEY = process.env.JARVIS_API_KEY || '';
const _AUTH_EXEMPT = new Set(['/health', '/health/providers', '/google-auth-callback']);
if (_JARVIS_API_KEY) {
    app.use((req, res, next) => {
        // Exempt health checks, OAuth callback, and webhook paths
        if (_AUTH_EXEMPT.has(req.path)) return next();
        if (req.path.startsWith('/webhooks/')) return next();
        // Dashboard HTML served via /progress-map — accept ?key= query param
        const key = req.headers['x-jarvis-key'] || req.query.key || '';
        if (key !== _JARVIS_API_KEY) {
            return res.status(401).json({ ok: false, error: 'Unauthorized' });
        }
        next();
    });
    console.log('🔑 API key auth active');
}

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
// Data-access seam: agents/controllers that have been migrated receive `repos`
// instead of the raw client (see services/dataAccess).
const { createRepos } = require('./services/dataAccess');
const repos = createRepos(supabase);

// Persist per-agent latency/intent metrics to Supabase (degrades to in-memory).
agentMetrics.init(supabase);

// Init push notification service and system logger with the Supabase client.
pushService.init(supabase);
systemLog.init(supabase, pushService);

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
        const data = await repos.chat.recentTail(chatId, { limit: 60 });
        const ordered = data.reverse();
        // Increased budget: savings from removing redundant LLM calls free up ~1700
        // tokens per request, which we reinvest in longer conversation history.
        const result = selectByTokenBudget(ordered, { maxTokens: 3000, maxMessages: 30 });
        cacheSet(cacheKey, result, TTL_CHAT_HISTORY);
        return result;
    } catch (err) {
        console.error('⚠️ loadChatHistory fallback:', err.message);
        return selectByTokenBudget(chatMemoryFallback, { maxTokens: 3000, maxMessages: 30 });
    }
}

async function saveChatMessage(role, text, chatId = 'default-session') {
    try {
        const { error } = await repos.chat.add(role, text, chatId);
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

    const contents = await repos.memories.allContents();
    const result = contents.length === 0
        ? 'אין עדיין זיכרונות שמורים.'
        : contents.map(c => `- ${c}`).join('\n');
    cacheSet('memories', result, TTL_MEMORIES);
    return result;
}

// ─── Full history search ──────────────────────────────────────────────────────

async function searchFullHistory(userMessage) {
    try {
        const data = await repos.chat.recentForSearch(200);

        if (!data || data.length === 0) return null;

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

// ─── Push notification token registration ────────────────────────────────────
app.post('/push/register-token', async (req, res) => {
    const { token, platform, appVersion } = req.body || {};
    if (!token) return res.status(400).json({ ok: false, error: 'token required' });
    try {
        await pushService.registerToken({ token, platform, appVersion });
        res.json({ ok: true });
    } catch (err) {
        systemLog.logError('route:/push/register-token', err).catch(() => {});
        res.status(500).json({ ok: false, error: 'registration failed' });
    }
});

// Debug-only route for manually testing push delivery
if (!isTestEnv && process.env.PUSH_DRIVER && process.env.PUSH_DRIVER !== 'none') {
    app.post('/push/test', async (req, res) => {
        const body = req.body?.body || '🔔 בדיקת התראה מג׳רביס';
        await pushService.sendPush({ title: 'ג׳רביס — בדיקה', body, category: 'alert' });
        res.json({ ok: true, message: 'push sent' });
    });
}

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

// ─── Saver mode ────────────────────────────────────────────────────────────────
// A single client toggle (settings.saverMode) that trims token usage end-to-end:
// forces short responses, lowers temperature, and caps maxTokens for chat. Mutates
// the settings object in place so the constraints ride along to every agent and to
// the provider opts. Safe to call on both /ask-jarvis and /stream-jarvis.
function applySaverMode(settings) {
    if (!settings || settings.saverMode !== true) return settings;
    settings.responseLength = 'short';
    const t = typeof settings.temperature === 'number' ? settings.temperature : 0.7;
    settings.temperature = Math.min(t, 0.3);
    settings._maxTokensCap = 350;
    return settings;
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
        applySaverMode(settings);
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
            }
            // Removed: the former `else if (agentName === 'chat' && length > 12)`
            // branch that called classifyIntentWithLLM a second time. If keywords
            // already returned 'chat', the LLM also returns 'chat' >90% of the time
            // — it's ~820 wasted tokens per request. Ambiguous collisions (multiple
            // keyword matches) are still disambiguated by the block above.
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
                longTermMemories = await filterRelevantMemoriesAsync(longTermMemories, userMessage, 8);
            }
            // Inject rolling conversation summary so agent remembers context beyond 20 msgs.
            // Cap at 1500 chars (~500 tokens) so a long summary can't flood the context.
            if (agentName === 'chat') {
                const raw = await conversationSummary.getSummary(chatId, supabase);
                settings.chatSummary = raw && raw.length > 600 ? raw.slice(0, 600) + '…' : raw;
            }
        } else {
            // All other agents get raw memories (TTL-cached — cheap)
            longTermMemories = await fetchLongTermMemories();
            // Inject last 4 turns so specialist agents (weather, news, sports, etc.) have conversation context.
            // loadChatHistory is TTL-cached (30s) so this adds no extra network cost.
            const recentHist = await loadChatHistory(chatId).catch(() => []);
            settings.recentHistory = recentHist.slice(-4);
        }

        // Inject user context so every agent can personalize its response
        settings.userMemories = longTermMemories
            ? longTermMemories.slice(0, 500)
            : '';
        const tDb = Date.now();

        // ── Past-conv: inject relevant history snippets beyond last 20 msgs ──
        if (agentName === 'chat' && PAST_CONV_PATTERN.test(userMessage)) {
            const historySnippet = await searchFullHistory(userMessage);
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
            userMessage, supabase, repos, useLocal, settings,
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
                    proactiveEngine.computeProactiveSuggestion(supabase, userMessage),
                    new Promise(resolve => { nudgeTimer = setTimeout(() => resolve(null), 400); }),
                ]);
                if (sug) {
                    answer += `\n\n💡 ${sug.message}`;
                    proactiveEngine.markNudged(chatId);
                }
            } catch (_) { /* never block the reply on a nudge */ }
            finally { clearTimeout(nudgeTimer); }
        }

        // ── Parallel: save history + TTS + passive memory extraction ─────────
        // Long-running agents (e.g. e2e in background) set skipTts to short-circuit
        // the response and avoid the client-side timeout.
        const ttsEnabled = settings.ttsEnabled !== false && !result.skipTts;
        const shouldExtract = agentName === 'chat' && !imageBase64;
        const [,, audioBase64, memorySaved] = await Promise.all([
            saveChatMessage('user', originalMessage, chatId),
            saveChatMessage('jarvis', answer, chatId),
            ttsEnabled ? generateSpeech(answer) : Promise.resolve(null),
            shouldExtract
                ? autoExtractMemory(originalMessage, answer, repos, settings).catch(e => { systemLog.logError('autoExtractMemory', e).catch(() => {}); return null; })
                : Promise.resolve(null),
        ]);
        cacheInvalidate(`chatHistory:${chatId}`); // history just updated

        // Summary update (fire-and-forget after response)
        if (shouldExtract) {
            setImmediate(() => {
                loadChatHistory(chatId).then(freshHistory => {
                    conversationSummary.updateSummaryIfNeeded(chatId, freshHistory, supabase, settings).catch(e => systemLog.logError('updateSummaryIfNeeded', e).catch(() => {}));
                }).catch(e => systemLog.logError('loadChatHistory:postChat', e).catch(() => {}));
            });
        }

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
        res.json({ answer, audio: audioBase64, action, chatId, suggestions, provider: llmProvider, memorySaved: memorySaved || null });

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
        const isDb = /supabase|PGRST|relation/i.test(err.message || '');
        res.status(200).json({
            answer: isRateLimit
                ? '⏳ כל ספקי ה-AI עמוסים כרגע (מגבלת קצב). נסה שוב בעוד כמה דקות.'
                : isDb
                    ? 'מסד הנתונים לא זמין כרגע. הפעולה לא בוצעה — נסה שוב בעוד רגע.'
                    : 'שגיאת מערכת פנימית.',
            suggestions: ['נסה שוב'],
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

        // Portable app/web preferences (AI, voice, appearance, etc.) — stored in a
        // single JSONB column so they survive reinstalls and sync across devices.
        // Shallow-merged onto whatever is already stored (partial updates allowed).
        // Keys must stay in sync with AppSettings.toPreferences() (Flutter) and the
        // settings blob in progress-map.html.
        if (rawBody.preferences && typeof rawBody.preferences === 'object' && !Array.isArray(rawBody.preferences)) {
            const existingPrefs = (existing && typeof existing.preferences === 'object' && existing.preferences) || {};
            const incoming = {};
            // Keep only primitive scalars (string/number/boolean); cap key count.
            // Skip 'role' — it's validated separately below to prevent bypass via preferences blob.
            for (const [k, v] of Object.entries(rawBody.preferences)) {
                if (k === 'role') continue; // role must be validated at top level
                if (Object.keys(incoming).length >= 40) break;
                if (v === null) continue;
                const t = typeof v;
                if (t === 'string') incoming[k] = v.slice(0, 200);
                else if (t === 'number' || t === 'boolean') incoming[k] = v;
            }
            payload.preferences = { ...existingPrefs, ...incoming };
        }

        // Control-center access role (admin|user). Stored inside the preferences
        // JSONB blob (no schema migration needed) so it survives reinstalls and
        // syncs across devices. Drives which dashboard tabs are visible.
        // Validated here regardless of whether sent at top level or inside preferences.
        const roleValue = rawBody.role || (rawBody.preferences && rawBody.preferences.role);
        if (roleValue && ['user', 'admin'].includes(roleValue)) {
            const basePrefs = payload.preferences
                || (existing && typeof existing.preferences === 'object' && existing.preferences)
                || {};
            payload.preferences = { ...basePrefs, role: roleValue };
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
        // Cache only the LLM narrative (costly); deterministic plan data is always fresh.
        const TTL_DAYPLAN_NARRATIVE = 45 * 60 * 1000; // 45 min
        const narrativeCacheKey = `dayplan:narrative:${settings.userName}`;
        const cachedAi = cacheGet(narrativeCacheKey);
        const ai = cachedAi ?? await optimizeDayPlan(plan.items, patterns, plan.load, settings);
        if (!cachedAi && ai.ai_available) cacheSet(narrativeCacheKey, ai, TTL_DAYPLAN_NARRATIVE);

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

// Personalized control-center layout learned from tab-view telemetry. Returns a
// "most-used first" tab order + the tab to spotlight. Deterministic, never fails.
app.get('/control-center/layout', _rl(60), async (req, res) => {
    try {
        const layout = await dashboardLearner.getDashboardLayout(supabase, {
            userId: req.query.user_id || 'default',
            sinceDays: Math.min(Number(req.query.days) || 30, 90),
        });
        res.json(layout);
    } catch (err) {
        console.error('GET /control-center/layout error:', err.message);
        res.json({ order: dashboardLearner.DEFAULT_ORDER, spotlight: null, counts: {}, learned: false });
    }
});

// ─── Analytics — time-series for the dashboard's Analytics tab ────────────────
// Buckets recent activity (system + personal) into daily series. Every query is
// scoped to the requested window and degrades to empty data if a table is
// missing, so the endpoint never hard-fails. callGemma4/feedbackStore/supabase
// are resolved at request time (defined elsewhere in this module).
const ANALYTICS_RANGES = { '7d': 7, '30d': 30, '90d': 90 };

function _dayKey(d) { return new Date(d).toISOString().slice(0, 10); }

function _dateAxis(days) {
    const out = [];
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    for (let i = days - 1; i >= 0; i--) out.push(_dayKey(new Date(today.getTime() - i * 86400000)));
    return out;
}

async function computeAnalytics(days) {
    const sinceISO = new Date(Date.now() - days * 86400000).toISOString();
    const axis = _dateAxis(days);
    const zero = () => Object.fromEntries(axis.map(k => [k, 0]));

    const [chatRes, tasksRes, remindersRes, metricsRes, eventsAgg] = await Promise.allSettled([
        supabase.from('chat_history').select('role, created_at').gte('created_at', sinceISO).limit(20000),
        supabase.from('tasks').select('done, created_at').gte('created_at', sinceISO).limit(20000),
        supabase.from('reminders').select('created_at').gte('created_at', sinceISO).limit(20000),
        supabase.from('agent_metrics').select('agent, ms, intent_mode, created_at').gte('created_at', sinceISO).limit(20000),
        feedbackStore.aggregateEvents(supabase, { sinceDays: days, limit: 5000 }),
    ]);
    const rows = (r) => (r.status === 'fulfilled' && r.value && !r.value.error && Array.isArray(r.value.data)) ? r.value.data : [];
    const seriesFrom = (obj) => axis.map(k => obj[k] || 0);

    // ── Personal: chat volume per day + active-hour histogram (Jerusalem) ──
    const chatRows = rows(chatRes);
    const chatPerDay = zero();
    const hours = Array(24).fill(0);
    let userMsgs = 0;
    for (const r of chatRows) {
        const k = _dayKey(r.created_at);
        if (k in chatPerDay) chatPerDay[k]++;
        hours[(new Date(r.created_at).getUTCHours() + 3) % 24]++;
        if (r.role === 'user') userMsgs++;
    }

    // ── Personal: tasks created per day + completion rate ──
    const taskRows = rows(tasksRes);
    const tasksPerDay = zero();
    let tasksDone = 0;
    for (const r of taskRows) {
        const k = _dayKey(r.created_at);
        if (k in tasksPerDay) tasksPerDay[k]++;
        if (r.done) tasksDone++;
    }
    const completionRate = taskRows.length ? Math.round(tasksDone / taskRows.length * 100) : 0;

    // ── Personal: reminders created per day ──
    const remPerDay = zero();
    for (const r of rows(remindersRes)) { const k = _dayKey(r.created_at); if (k in remPerDay) remPerDay[k]++; }

    // ── System: agent latency + intent trend + top agents ──
    const metricRows = rows(metricsRes);
    const latPerDay = {}, intentPerDay = {}, byAgent = {};
    for (const k of axis) { latPerDay[k] = { sum: 0, count: 0 }; intentPerDay[k] = { fast: 0, llm: 0 }; }
    for (const r of metricRows) {
        const k = _dayKey(r.created_at);
        const ms = Number(r.ms) || 0;
        if (latPerDay[k]) { latPerDay[k].sum += ms; latPerDay[k].count++; }
        if (intentPerDay[k]) { if (r.intent_mode === 'fast') intentPerDay[k].fast++; else if (r.intent_mode === 'llm') intentPerDay[k].llm++; }
        const a = (r.agent || '').replace('Agent', '') || 'unknown';
        byAgent[a] = byAgent[a] || { sum: 0, count: 0 };
        byAgent[a].sum += ms; byAgent[a].count++;
    }
    const topAgents = Object.entries(byAgent)
        .map(([agent, v]) => ({ agent, count: v.count, avgMs: Math.round(v.sum / v.count) }))
        .sort((a, b) => b.count - a.count).slice(0, 8);

    // ── System: event volume per day + top event types ──
    const events = (eventsAgg.status === 'fulfilled' && eventsAgg.value) ? (eventsAgg.value.events || []) : [];
    const eventsPerDay = zero();
    const eventTypes = {};
    for (const e of events) {
        const k = _dayKey(e.created_at);
        if (k in eventsPerDay) eventsPerDay[k]++;
        eventTypes[e.event_name] = (eventTypes[e.event_name] || 0) + 1;
    }
    const topEvents = Object.entries(eventTypes).map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count).slice(0, 8);

    return {
        range: `${days}d`, days, generatedAt: new Date().toISOString(), axis,
        kpis: {
            chatMessages: chatRows.length, userMessages: userMsgs,
            tasksCreated: taskRows.length, completionRate,
            remindersCreated: rows(remindersRes).length,
            agentCalls: metricRows.length, events: events.length,
        },
        personal: {
            chatVolume: seriesFrom(chatPerDay),
            tasksCreated: seriesFrom(tasksPerDay),
            reminders: seriesFrom(remPerDay),
            activeHours: hours, completionRate,
        },
        system: {
            agentLatency: axis.map(k => latPerDay[k].count ? Math.round(latPerDay[k].sum / latPerDay[k].count) : 0),
            intentFast: axis.map(k => intentPerDay[k].fast),
            intentLlm: axis.map(k => intentPerDay[k].llm),
            eventVolume: seriesFrom(eventsPerDay),
            topAgents, topEvents,
        },
    };
}

app.get('/dashboard/analytics', _rl(30), async (req, res) => {
    try {
        const days = ANALYTICS_RANGES[String(req.query.range)] || 7;
        res.json(await computeAnalytics(days));
    } catch (err) {
        console.error('❌ /dashboard/analytics:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// In-memory cache for AI insights, keyed by range. The dashboard auto-refreshes
// every 30s; without this each refresh would burn an LLM call. A 30-minute TTL
// keeps insights fresh enough while making the feature token-frugal. Bypass with
// { force:true } in the request body (used by the explicit "regenerate" button).
const _insightCache = new Map(); // range → { at, payload }
const INSIGHT_TTL_MS = 30 * 60 * 1000;

// AI-driven insights over the same window — compact summary → LLM → Hebrew tips.
app.post('/dashboard/analytics/insights', _rl(10), async (req, res) => {
    try {
        const rangeKey = String((req.body && req.body.range) || '7d');
        const force = !!(req.body && req.body.force);
        const days = ANALYTICS_RANGES[rangeKey] || 7;

        if (!force) {
            const hit = _insightCache.get(rangeKey);
            if (hit && (Date.now() - hit.at) < INSIGHT_TTL_MS) {
                return res.json({ ...hit.payload, cached: true });
            }
        }

        const a = await computeAnalytics(days);
        const peakHour = a.personal.activeHours.indexOf(Math.max(...a.personal.activeHours));
        const compact = {
            range: a.range,
            kpis: a.kpis,
            peakHour,
            topAgents: a.system.topAgents.slice(0, 5).map(x => `${x.agent}: ${x.count} קריאות, ${x.avgMs}ms ממוצע`),
            topEvents: a.system.topEvents.slice(0, 5).map(x => `${x.name}: ${x.count}`),
            chatTrend: a.personal.chatVolume,
            taskTrend: a.personal.tasksCreated,
            latencyTrend: a.system.agentLatency,
        };
        const prompt = `אתה אנליסט מוצר של ג'ארביס, עוזר אישי. נתח את נתוני השימוש (טווח ${days} ימים) והפק תובנות מעשיות בעברית.
נתונים: ${JSON.stringify(compact)}
החזר JSON בלבד: {"insights":[{"icon":"אמוג'י","title":"כותרת קצרה","detail":"משפט הסבר + המלצה"}]}
כלול 3-5 תובנות: מגמות בולטות, אנומליות (קפיצות/ירידות חריגות), שעת שיא הפעילות, ביצועי agents, והמלצה אחת לשיפור. פנה ישירות אל המשתמש.`;

        let insights = [];
        try {
            const raw = await callGemma4(prompt, false, 700);
            const m = String(raw).match(/\{[\s\S]*\}/);
            if (m) insights = JSON.parse(m[0]).insights || [];
            if ((!Array.isArray(insights) || !insights.length) && raw) {
                insights = [{ icon: '📊', title: 'תובנות', detail: String(raw).slice(0, 400) }];
            }
        } catch (llmErr) {
            console.error('⚠️ analytics insights LLM failed, using deterministic fallback:', llmErr.message);
        }

        // Deterministic fallback so the panel is never empty when the LLM is down.
        if (!Array.isArray(insights) || !insights.length) {
            insights = _deterministicInsights(a, peakHour);
        }
        const payload = { insights, generatedAt: new Date().toISOString(), source: insights._llm === false ? 'computed' : 'ai' };
        // Only cache real AI output — a deterministic fallback means the LLM was
        // down, so we retry next time rather than pinning the fallback for 30 min.
        if (payload.source === 'ai') _insightCache.set(rangeKey, { at: Date.now(), payload });
        res.json(payload);
    } catch (err) {
        console.error('❌ /dashboard/analytics/insights:', err.message);
        res.status(500).json({ error: 'Internal server error', insights: [] });
    }
});

// Build a handful of factual insights straight from the aggregated numbers — no
// LLM. Used as a graceful fallback when the model is unavailable.
function _deterministicInsights(a, peakHour) {
    const out = [];
    const k = a.kpis;
    out.push({ icon: '💬', title: 'נפח פעילות', detail: `${k.chatMessages} הודעות ו-${k.tasksCreated} משימות נוצרו בטווח ${a.days} הימים האחרונים.` });
    if (k.tasksCreated > 0) {
        out.push({ icon: k.completionRate >= 60 ? '✅' : '📌', title: 'שיעור השלמה',
            detail: `השלמת ${k.completionRate}% מהמשימות. ${k.completionRate >= 60 ? 'קצב מצוין — המשך כך!' : 'שווה לפנות זמן לסגירת משימות פתוחות.'}` });
    }
    if (k.chatMessages > 0) {
        out.push({ icon: '🕐', title: 'שעת שיא', detail: `הכי פעיל סביב השעה ${peakHour}:00. תזמון משימות מורכבות לשעה זו עשוי לעזור.` });
    }
    const ta = a.system.topAgents[0];
    if (ta) out.push({ icon: '🤖', title: 'סוכן מוביל', detail: `הסוכן "${ta.agent}" טופל הכי הרבה (${ta.count} קריאות, ${ta.avgMs}ms בממוצע).` });
    out._llm = false;
    return out;
}

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
const TTL_MORNING_BRIEFING = 30 * 60 * 1000; // 30 min in-process cache
app.get('/morning-briefing', _rl(30), async (req, res) => {
    try {
        const city = req.query.city || '';
        const cacheKey = `morning-briefing:${city || 'default'}`;
        const cached = cacheGet(cacheKey);
        if (cached) return res.json({ briefing: cached, cached: true });

        const briefing = await buildMorningBriefing(city);
        cacheSet(cacheKey, briefing, TTL_MORNING_BRIEFING);
        res.json({ briefing, cached: false });
    } catch (err) {
        console.error('GET /morning-briefing error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Dashboard Context ────────────────────────────────────────────────────────

const TTL_DASHBOARD_WEATHER = 2 * 60 * 60 * 1000; // 2 h — weather changes slowly
const TTL_DASHBOARD_NEWS    = 60 * 60 * 1000;     // 1 h — headlines stay relevant for an hour

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

// Builds the hero subtitle locally (no LLM). A slot-aware greeting plus a short
// state line derived from the already-fetched tasks/reminders. This used to be
// an LLM call with a 5-minute cache — by far the home screen's most frequent
// token drain — and the templated version is indistinguishable in practice.
function _buildHeroCard(slot, tasks, reminders, settings) {
    const userName = settings?.userName || settings?.userProfile?.name || 'שלי';

    const greetings = {
        morning:      `בוקר טוב, ${userName}!`,
        late_morning: `שלום ${userName},`,
        noon:         `צהריים טובים, ${userName},`,
        afternoon:    `אחר צהריים טובים, ${userName},`,
        evening:      `ערב טוב, ${userName}!`,
        night:        `לילה טוב, ${userName}!`,
    };
    const greeting = greetings[slot] || `שלום, ${userName}!`;

    const openTasks = (tasks || []).length;
    const highCount = (tasks || []).filter(t => t.priority === 'high').length;

    // Soonest upcoming reminder (data is already ordered ascending by time).
    const nextRem = (reminders || [])[0];
    let remLine = '';
    if (nextRem?.scheduled_time) {
        const timeStr = new Date(nextRem.scheduled_time).toLocaleTimeString('he-IL', {
            timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit',
        });
        remLine = `הבא: ${nextRem.text} ב-${timeStr}`;
    }

    let stateLine;
    if (openTasks === 0 && !remLine) {
        stateLine = slot === 'night' || slot === 'evening'
            ? 'הכל סגור להיום — מגיע לך לנוח.'
            : 'אין משימות פתוחות כרגע. רגע טוב להתחיל משהו.';
    } else {
        const bits = [];
        if (openTasks > 0) {
            bits.push(highCount > 0
                ? `${openTasks} משימות פתוחות (${highCount} דחופות)`
                : `${openTasks} משימות פתוחות`);
        }
        if (remLine) bits.push(remLine);
        stateLine = bits.join(' · ');
    }

    const text = `${greeting} ${stateLine}`.trim();
    return { text, confidence: 1.0 };
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

        const nowJer = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
        const slot = _getDashboardTimeSlot(nowJer);

        // ── Parallel data fetch ──────────────────────────────────────────────
        const threeHoursLater = new Date(nowJer.getTime() + 3 * 60 * 60 * 1000).toISOString();

        const [tasksRes, remindersRes, weatherData, newsData] = await Promise.all([
            supabase.from('tasks').select('id,content,priority').eq('done', false)
                .order('priority', { ascending: false }).limit(6),
            supabase.from('reminders').select('id,text,scheduled_time').eq('fired', false)
                .lte('scheduled_time', threeHoursLater)
                .order('scheduled_time', { ascending: true }).limit(6),
            (async () => {
                const city = req.query.city || settings.userProfile?.city || '';
                const cacheKey = `dashboard:weather:${city || 'default'}`;
                const cached = cacheGet(cacheKey);
                if (cached) return cached;
                try {
                    const { getWeatherSummary } = require('./services/weatherSource');
                    const data = await getWeatherSummary(city);
                    if (data) cacheSet(cacheKey, data, TTL_DASHBOARD_WEATHER);
                    return data;
                } catch { return null; }
            })(),
            (async () => {
                const cacheKey = 'dashboard:news';
                const cached = cacheGet(cacheKey);
                if (cached) return cached;
                try {
                    const { getNewsSummary } = require('./services/newsSource');
                    const data = await getNewsSummary();
                    if (data) cacheSet(cacheKey, data, TTL_DASHBOARD_NEWS);
                    return data;
                } catch { return null; }
            })(),
        ]);

        const tasks     = tasksRes.data     || [];
        const reminders = remindersRes.data  || [];

        // ── Hero card (built locally each request — cheap, reflects live state) ─
        const { text: heroText, confidence } = _buildHeroCard(slot, tasks, reminders, settings);
        const heroCard = { text: heroText, confidence, slot };

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
        const contacts = await repos.contacts.listByName();
        res.json({ contacts });
    } catch (err) {
        console.error('GET /contacts error:', err.message);
        res.status(500).json({ contacts: [] });
    }
});

app.delete('/contacts/:id', requirePolicy('contacts.delete', { sensitive: true, irreversible: true }), async (req, res) => {
    try {
        const { error } = await repos.contacts.removeById(req.params.id);
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
        const { data, error } = await repos.notes.updateById(req.params.id, updates);
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
        const items = await repos.shopping.listAll();
        res.json({ items });
    } catch (err) {
        console.error('GET /shopping error:', err.message);
        res.status(500).json({ items: [] });
    }
});

app.post('/shopping', async (req, res) => {
    try {
        const { item } = req.body;
        if (!item) return res.status(400).json({ error: 'item required' });
        const { data, error } = await repos.shopping.create(item);
        if (error) throw error;
        res.json({ item: data });
    } catch (err) {
        console.error('POST /shopping error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/shopping/:id', async (req, res) => {
    try {
        const { error } = await repos.shopping.removeById(req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /shopping:id error:', err.message);
        res.status(500).json({ ok: false, error: 'Internal server error' });
    }
});

// ─── Memories REST API ────────────────────────────────────────────────────────
app.get('/memories', async (req, res) => {
    try {
        const { q } = req.query;
        if (q && pinecone.isReady()) {
            const hits = await pinecone.searchMemories(q, 20);
            if (hits) return res.json({ memories: hits.map(content => ({ content })) });
        }
        const data = await repos.memories.listAll();
        res.json({ memories: data });
    } catch (err) {
        console.error('GET /memories error:', err.message);
        res.status(500).json({ memories: [] });
    }
});

app.post('/memories', async (req, res) => {
    try {
        const { content, scope = 'long_term' } = req.body;
        if (!content || typeof content !== 'string' || !content.trim()) {
            return res.status(400).json({ error: 'content is required' });
        }
        const data = await repos.memories.create({ content: content.trim(), scope });
        const row = data?.[0];
        if (row?.id) {
            pinecone.upsertMemory(row.id, row.content).catch(() => {});
            obsidianSync.dbToVault('memories', row);
        }
        cacheInvalidate('memories');
        res.json({ memory: row });
    } catch (err) {
        console.error('POST /memories error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.put('/memories/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const { content, scope } = req.body;
        if (!content || typeof content !== 'string' || !content.trim()) {
            return res.status(400).json({ error: 'content is required' });
        }
        const patch = { content: content.trim() };
        if (scope) patch.scope = scope;
        const data = await repos.memories.updateById(id, patch);
        if (!data || data.length === 0) return res.status(404).json({ error: 'Memory not found' });
        pinecone.upsertMemory(data[0].id, data[0].content).catch(() => {});
        obsidianSync.dbToVault('memories', data[0]);
        cacheInvalidate('memories');
        res.json({ memory: data[0] });
    } catch (err) {
        console.error('PUT /memories/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/memories/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const data = await repos.memories.removeById(id);
        if (!data || data.length === 0) return res.status(404).json({ error: 'Memory not found' });
        await pinecone.deleteMemory(id);
        obsidianSync.removeFromVault('memories', data[0]);
        cacheInvalidate('memories');
        res.json({ deleted: true, memory: data[0] });
    } catch (err) {
        console.error('DELETE /memories/:id error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Notes ────────────────────────────────────────────────────────────────────
app.get('/notes', async (_req, res) => {
    try {
        const notes = await repos.notes.listAll();
        res.json({ notes });
    } catch (err) {
        console.error('GET /notes error:', err.message);
        res.status(500).json({ notes: [] });
    }
});

app.post('/notes', async (req, res) => {
    try {
        const { title, content } = req.body;
        if (!content) return res.status(400).json({ error: 'content required' });
        const data = await repos.notes.add({ title: title || '', content });
        res.json({ note: data });
    } catch (err) {
        console.error('POST /notes error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.delete('/notes/:id', async (req, res) => {
    try {
        const { error } = await repos.notes.removeById(req.params.id);
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
        const result = await buildProjectsBriefing(repos.projects, userName);
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
                    kind: row.kind || 'e2e',
                    created_at: row.created_at,
                    count: 0,
                    critical: 0, high: 0, medium: 0, low: 0,
                    measured: 0, evaluated: 0,
                    done: 0,
                });
            }
            const g = byRun.get(row.run_id);
            if (row.kind) g.kind = row.kind;
            if (row.created_at > g.created_at) g.created_at = row.created_at;
            if (row.status === 'done') { g.done++; continue; }
            g.count++;
            if (g[row.severity] !== undefined) g[row.severity]++;
            // 'source' may be absent on rows from before the migration → treat as measured.
            if (row.source === 'evaluated') g.evaluated++; else g.measured++;
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
            kind:    findings[0]?.kind || 'e2e',
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

// ─── Survey check (should user take survey?) ──────────────────────────────
// Per-user 48h cooldown after a completed submission; questions answered in
// the last 7 days are excluded from the next survey so it feels fresh.
const SURVEY_COOLDOWN_HOURS = 48;
const SURVEY_EXCLUDE_WINDOW_DAYS = 7;
// Minimum number of completed surveys before we show aggregated conclusions.
// Below this we report "not enough data" instead of inventing insights.
const SURVEY_MIN_FOR_INSIGHTS = 2;

app.get('/survey-check', async (req, res) => {
    try {
        const { sessionMinutes, agentCallCount, force, userName } = req.query;
        const minutes = parseInt(sessionMinutes) || 0;
        const calls = parseInt(agentCallCount) || 0;
        const forced = force === 'true' || force === '1';

        // Trigger survey after 25+ minutes OR 8+ agent calls (or forced by user).
        // Higher thresholds keep the survey from interrupting short, active sessions.
        const shouldShowSurvey = forced || minutes >= 25 || calls >= 8;
        if (!shouldShowSurvey) return res.json({ showSurvey: false });

        // Cooldown + recent-question exclusion (requires userName).
        let excludeIds = [];
        if (userName) {
            try {
                const cooldownCutoff = new Date(Date.now() - SURVEY_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString();
                const excludeCutoff  = new Date(Date.now() - SURVEY_EXCLUDE_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();

                // 1) Cooldown: any completed survey since cutoff blocks new prompts.
                if (!forced) {
                    const { data: recent } = await supabase
                        .from('user_surveys')
                        .select('id, completed_at')
                        .eq('user_name', userName)
                        .gte('completed_at', cooldownCutoff)
                        .limit(1);
                    if (recent && recent.length > 0) {
                        return res.json({ showSurvey: false, cooldown: true });
                    }
                }

                // 2) Build exclude list from question_ids of surveys in the last 7 days.
                const { data: recentWeek } = await supabase
                    .from('user_surveys')
                    .select('question_ids')
                    .eq('user_name', userName)
                    .gte('completed_at', excludeCutoff)
                    .limit(20);
                for (const row of (recentWeek || [])) {
                    for (const qid of (row.question_ids || [])) excludeIds.push(qid);
                }
            } catch (cooldownErr) {
                // If the cooldown columns don't exist yet (migration not applied), proceed without filtering.
                console.warn('⚠️ /survey-check cooldown query failed (will still serve survey):', cooldownErr.message);
            }
        }

        const questions = selectSurveyQuestions({ minutes, calls }, excludeIds);
        if (Object.keys(questions).length === 0) {
            return res.json({ showSurvey: false, exhausted: true });
        }
        const surveyJson = buildSurveyJson(questions);
        res.json({ showSurvey: true, questions: surveyJson });
    } catch (err) {
        console.error('⚠️ /survey-check error:', err.message);
        res.json({ showSurvey: false });
    }
});

// ─── Survey submission ─────────────────────────────────────────────────────
app.post('/survey-submit', async (req, res) => {
    try {
        const { responses, userName } = req.body;
        if (!responses || !userName) {
            return res.status(400).json({ error: 'Missing responses or userName' });
        }

        // Build survey structure from the actually-answered questions.
        const surveyQIds = Object.keys(responses);
        const survey = surveyQIds.map(id => ({
            id,
            question: SURVEY_QUESTIONS[id]?.question || id,
        }));

        // Build a factual summary straight from the answers — no LLM, no invented text.
        const { text: summary, breakdown } = buildSurveySummary(survey, responses, userName);

        // Save survey to DB with completion tracking so future /survey-check
        // calls can enforce the per-user cooldown and exclude answered question_ids.
        const nowIso = new Date().toISOString();
        const insertRow = {
            user_name: userName,
            responses: JSON.stringify(responses),
            summary,
            created_at: nowIso,
            completed_at: nowIso,
            question_ids: surveyQIds,
        };
        let { error } = await supabase.from('user_surveys').insert([insertRow]);

        // If the migration hasn't been applied yet, retry without the new columns
        // so old deployments don't break on submit.
        if (error && /completed_at|question_ids/i.test(error.message || '')) {
            delete insertRow.completed_at;
            delete insertRow.question_ids;
            ({ error } = await supabase.from('user_surveys').insert([insertRow]));
        }
        if (error) throw error;

        res.json({ success: true, summary, breakdown });
    } catch (err) {
        console.error('⚠️ /survey-submit error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Survey history (past surveys for a user) ─────────────────────────────
app.get('/survey-history', async (req, res) => {
    try {
        const { userName } = req.query;
        if (!userName) return res.status(400).json({ error: 'userName required' });

        const { data, error } = await supabase
            .from('user_surveys')
            .select('id, created_at, summary, responses')
            .eq('user_name', userName)
            .order('created_at', { ascending: false })
            .limit(50);

        if (error) throw error;

        const surveys = (data || []).map(s => {
            let parsed = s.responses;
            if (typeof parsed === 'string') {
                try { parsed = JSON.parse(parsed); } catch (_) { parsed = {}; }
            }
            return { id: s.id, createdAt: s.created_at, summary: s.summary, responses: parsed };
        });

        res.json({ surveys });
    } catch (err) {
        console.error('⚠️ /survey-history error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── Survey aggregate insights ─────────────────────────────────────────────
// Real aggregation of stored responses (counts + percentages) — NOT LLM text.
// Returns enough:false (and no conclusions) until there are enough surveys.
app.get('/survey-insights', async (req, res) => {
    try {
        const { userName } = req.query;
        if (!userName) return res.status(400).json({ error: 'userName required' });

        const { data, error } = await supabase
            .from('user_surveys')
            .select('responses, created_at')
            .eq('user_name', userName)
            .order('created_at', { ascending: false })
            .limit(50);
        if (error) throw error;

        const agg = aggregateSurveys(data || []);
        if (agg.surveyCount < SURVEY_MIN_FOR_INSIGHTS) {
            return res.json({
                enough: false,
                surveyCount: agg.surveyCount,
                minRequired: SURVEY_MIN_FOR_INSIGHTS,
                insights: [],
                aggregation: agg,
            });
        }

        res.json({
            enough: true,
            surveyCount: agg.surveyCount,
            insights: insightsFromAggregation(agg),
            aggregation: agg,
            generatedAt: new Date().toISOString(),
        });
    } catch (err) {
        console.error('⚠️ /survey-insights error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── GET /survey-smart-check — generate contextual questions using LLM ────────
// Reads usage data (agent metrics + past concerns) and lets the LLM craft
// personalised questions, making each survey feel relevant rather than generic.
app.get('/survey-smart-check', async (req, res) => {
    const { userName = '' } = req.query;
    try {
        const snap = await agentMetrics.snapshot().catch(() => ({ latency: [] }));
        const topAgents = (snap.latency || [])
            .filter(r => r.count > 0)
            .sort((a, b) => b.count - a.count)
            .slice(0, 5)
            .map(r => ({ agent: r.agent, count: r.count }));

        let pastConcerns = [];
        if (userName) {
            const { data: surveyRows } = await supabase
                .from('user_surveys')
                .select('responses')
                .eq('user_id', userName)
                .order('created_at', { ascending: false })
                .limit(5);
            for (const s of surveyRows || []) {
                let resp = s.responses;
                if (typeof resp === 'string') { try { resp = JSON.parse(resp); } catch (_) { resp = {}; } }
                for (const [qId, answer] of Object.entries(resp || {})) {
                    if (isNegativeAnswer(answer) && SURVEY_QUESTIONS[qId]) {
                        pastConcerns.push({ area: SURVEY_QUESTIONS[qId].question, answer });
                    }
                }
            }
        }

        const { generateSmartSurvey } = require('./agents/surveyAgent');
        const questions = await generateSmartSurvey(callGemma4, { topAgents, pastConcerns });
        res.json({ showSurvey: true, questions, smart: true });
    } catch (err) {
        console.error('⚠️ /survey-smart-check error:', err.message);
        res.json({ showSurvey: false });
    }
});

// ─── GET /survey-impact — feedback loop: what concerns came from surveys ───────
app.get('/survey-impact', async (req, res) => {
    const { userName = '' } = req.query;
    try {
        const { data: surveyRows } = await supabase
            .from('user_surveys')
            .select('responses, created_at')
            .eq('user_id', userName)
            .order('created_at', { ascending: false })
            .limit(20);

        const concerns = [];
        for (const s of surveyRows || []) {
            let resp = s.responses;
            if (typeof resp === 'string') { try { resp = JSON.parse(resp); } catch (_) { resp = {}; } }
            for (const [qId, answer] of Object.entries(resp || {})) {
                if (isNegativeAnswer(answer) && SURVEY_QUESTIONS[qId]) {
                    concerns.push({ area: SURVEY_QUESTIONS[qId].question, answer, date: s.created_at });
                }
            }
        }
        res.json({ concerns, totalSurveys: (surveyRows || []).length });
    } catch (err) {
        console.error('⚠️ /survey-impact error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── GET /dashboard/conversation-insights — usage patterns from agent metrics ──
app.get('/dashboard/conversation-insights', async (req, res) => {
    try {
        const snap = await agentMetrics.snapshot().catch(() => ({ latency: [], intent: { fast: 0, llm: 0 } }));
        const topAgents = (snap.latency || [])
            .filter(r => r.count > 0)
            .sort((a, b) => b.count - a.count)
            .slice(0, 8)
            .map(r => ({ agent: r.agent, count: r.count, avgMs: r.avgMs || 0 }));

        const since7 = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
        const { count: recentChats } = await supabase
            .from('chat_history')
            .select('id', { count: 'exact', head: true })
            .gte('created_at', since7)
            .eq('role', 'user');

        res.json({
            topAgents,
            intentClassification: snap.intent,
            recentChatVolume: recentChats || 0,
            generatedAt: new Date().toISOString(),
        });
    } catch (err) {
        console.error('⚠️ /dashboard/conversation-insights error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── POST /dashboard/smart-proposals/generate ─────────────────────────────────
// Generates personalized dev proposals from survey answers + usage patterns.
app.post('/dashboard/smart-proposals/generate', async (req, res) => {
    const { userName = '' } = req.body;
    // Cache proposals for 30 min per user — the underlying data (surveys, metrics)
    // changes slowly; repeated dashboard clicks should not burn LLM tokens.
    const proposalsCacheKey = `smart_proposals:${userName}`;
    const cached = cacheGet(proposalsCacheKey);
    if (cached) return res.json(cached);
    try {
        // 1. Collect survey concerns (negative answers only)
        const { data: surveyRows } = await supabase
            .from('user_surveys')
            .select('responses, created_at')
            .eq('user_id', userName)
            .order('created_at', { ascending: false })
            .limit(15);

        const concerns = [];
        for (const s of surveyRows || []) {
            let resp = s.responses;
            if (typeof resp === 'string') { try { resp = JSON.parse(resp); } catch (_) { resp = {}; } }
            for (const [qId, answer] of Object.entries(resp || {})) {
                if (isNegativeAnswer(answer) && SURVEY_QUESTIONS[qId]) {
                    concerns.push({ area: SURVEY_QUESTIONS[qId].question, answer });
                }
            }
        }

        // 2. Collect usage patterns from agent metrics
        const snap = await agentMetrics.snapshot().catch(() => ({ latency: [], intent: {} }));
        const topAgents = (snap.latency || [])
            .filter(r => r.count > 0)
            .sort((a, b) => b.count - a.count)
            .slice(0, 6)
            .map(r => ({ agent: r.agent, count: r.count, avgMs: r.avgMs || 0 }));

        // 3. Recent chat volume
        const since7 = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
        const { count: recentChats } = await supabase
            .from('chat_history')
            .select('id', { count: 'exact', head: true })
            .gte('created_at', since7)
            .eq('role', 'user');

        // 4. Build personalised prompt
        const concernsText = concerns.length > 0
            ? concerns.map(c => `- "${c.area}": תשובה שלילית: "${c.answer}"`).join('\n')
            : 'אין תלונות ספציפיות מהסקרים';
        const agentsText = topAgents.length > 0
            ? topAgents.map(a => `${a.agent} (${a.count} שיחות, ${a.avgMs}ms ממוצע)`).join(', ')
            : 'אין נתוני שימוש עדיין';
        const intentText = Object.entries(snap.intent || {}).map(([k, v]) => `${k}: ${v}`).join(', ') || 'אין נתונים';

        const prompt = `אתה מנהל מוצר בכיר של "ג'רביס" — עוזר AI אישי בעברית (Flutter + Node.js).

==נתוני שימוש (7 ימים אחרונים)==
שיחות כולל: ${recentChats || 0}
סוכנים הכי בשימוש: ${agentsText}
פיצ'ר זיהוי כוונות: ${intentText}

==תלונות מסקרי המשתמש==
${concernsText}

==מטרה==
צור 4-5 הצעות פיתוח ממוקדות ואישיות. כל הצעה חייבת:
1. להתייחס ישירות לנתונים (סוכן ספציפי, תלונה ספציפית, או שניהם)
2. להיות מעשית ויישומית — לא כללית
3. להסביר למה זה חשוב עכשיו בהתבסס על הנתונים

החזר JSON בלבד (ללא markdown, ללא הסברים):
[
  {
    "title": "כותרת קצרה בעברית (עד 55 תווים)",
    "description": "מה לעשות ואיך — 2 משפטים",
    "rationale": "למה עכשיו — משפט אחד שמתייחס לנתון ספציפי",
    "source": "survey",
    "category": "improvement",
    "priority_score": 8
  }
]
source: "survey" (מבוסס על תלונה), "usage" (מבוסס על שימוש), "both" (שניהם)
category: "improvement", "feature", "bug_fix", "ux", "performance"
priority_score: 1-10 (בהתאם לדחיפות ולהשפעה על המשתמש)`;

        const raw = await callGemma4(prompt, false, 1400);
        const stripped = raw.replace(/```(?:json)?/gi, '').replace(/```/g, '').trim();
        const start = stripped.indexOf('[');
        const end   = stripped.lastIndexOf(']');
        if (start === -1 || end === -1 || end <= start) {
            return res.status(500).json({ error: 'לא הצלחתי לייצר הצעות — נסה שוב' });
        }
        let proposals;
        try {
            proposals = JSON.parse(stripped.slice(start, end + 1));
        } catch (_) {
            return res.status(500).json({ error: 'שגיאת JSON מהמודל — נסה שוב' });
        }

        const now = Date.now();
        const tagged = (Array.isArray(proposals) ? proposals : [])
            .filter(p => p.title && p.description)
            .map((p, i) => ({
                id: `smart_${now}_${i}`,
                title:          (p.title || '').toString().slice(0, 80),
                description:    (p.description || '').toString(),
                rationale:      (p.rationale || '').toString(),
                source:         ['survey', 'usage', 'both'].includes(p.source) ? p.source : 'usage',
                category:       ['improvement', 'feature', 'bug_fix', 'ux', 'performance'].includes(p.category)
                                    ? p.category : 'improvement',
                priority_score: Math.min(10, Math.max(1, Number(p.priority_score) || 5)),
            }))
            .sort((a, b) => b.priority_score - a.priority_score);

        const payload = { proposals: tagged, generatedAt: new Date().toISOString(), basedOn: { surveys: concerns.length, topAgents: topAgents.length } };
        cacheSet(proposalsCacheKey, payload, 30 * 60 * 1000); // 30 min
        res.json(payload);
    } catch (err) {
        console.error('⚠️ /dashboard/smart-proposals/generate error:', err.message);
        res.status(500).json({ error: 'שגיאה פנימית' });
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

// ─── GET /dashboard/error-report/export — Claude-ready Markdown report ────────
// Runs the code error scanner and enriches every finding with real code context
// (±4 lines around the flagged line) so Claude can verify genuine vs. false positives.
app.get('/dashboard/error-report/export', _rl(5), async (_req, res) => {
    try {
        const fsSync = require('fs');
        const { runCodeErrorScanner } = require('./agents/e2e/codeErrorScanner');
        const { findings, score, summary } = await runCodeErrorScanner({});

        // ── Attach code context to each finding ───────────────────────────────
        const fileLineCache = {};
        const withCtx = await Promise.all(findings.map(async (f) => {
            const m = (f.target || '').match(/^(.+?):(\d+)$/);
            if (!m) return { ...f, codeContext: null };
            const [, relPath, lineStr] = m;
            const lineNum = parseInt(lineStr, 10);
            if (!fileLineCache[relPath]) {
                try {
                    const src = await fsSync.promises.readFile(
                        require('path').join(__dirname, relPath), 'utf8');
                    fileLineCache[relPath] = src.split('\n');
                } catch { fileLineCache[relPath] = null; }
            }
            const lines = fileLineCache[relPath];
            if (!lines) return { ...f, codeContext: null };
            const start = Math.max(0, lineNum - 4);
            const end   = Math.min(lines.length, lineNum + 3);
            const ctx   = lines.slice(start, end).map((l, i) => {
                const ln = start + i + 1;
                return `${String(ln).padStart(4)}: ${l}${ln === lineNum ? '  // ← ממצא' : ''}`;
            }).join('\n');
            return { ...f, codeContext: ctx };
        }));

        // ── Build Markdown ─────────────────────────────────────────────────────
        const counts = { critical: 0, high: 0, medium: 0, low: 0 };
        for (const f of withCtx) if (f.severity in counts) counts[f.severity]++;
        const now = new Date().toLocaleString('he-IL', { timeZone: 'Asia/Jerusalem' });

        const header = [
            '# דוח שגיאות קוד — Jarvis | ייצוא לקלוד קוד',
            `**תאריך:** ${now} | **ציון:** ${score}/100 | 🔴 ${counts.critical} · 🟠 ${counts.high} · 🟡 ${counts.medium} · 🟢 ${counts.low}`,
            `**סיכום:** ${summary}`,
            '',
            '---',
            '',
            '## הוראות לקלוד',
            '',
            'אתה מקבל דוח שגיאות שנוצר אוטומטית — חלק מהממצאים עלולים להיות **false positives**.',
            '',
            '**בצע לפי הסדר עבור כל ממצא:**',
            '1. **בדוק** אם השגיאה אמיתית — הסתכל על קוד ההקשר המצורף',
            '2. **תקן** שגיאות אמיתיות (שינוי מינימלי, ללא refactor)',
            '3. **דלג** על false positives עם הסבר קצר',
            '4. **הרץ** `npm test` אחרי תיקונים קריטיים/גבוהים',
            '',
            '**בסוף, צור סיכום בפורמט:**',
            '```',
            '✅ תוקנו: [רשימת קבצים]',
            '⏭️ דולגו (false positive): [רשימה + הסבר]',
            '⚠️ נותרו פתוחים: [רשימה]',
            'ציון חדש משוער: X/100',
            '```',
            '',
            '---',
            '',
        ].join('\n');

        const sevHeader = { critical: '## 🔴 קריטי', high: '## 🟠 גבוה', medium: '## 🟡 בינוני', low: '## 🟢 נמוך' };
        const order     = { critical: 0, high: 1, medium: 2, low: 3 };
        const sorted    = [...withCtx].sort((a, b) => (order[a.severity] ?? 9) - (order[b.severity] ?? 9));
        const grouped   = { critical: [], high: [], medium: [], low: [] };
        for (const f of sorted) if (f.severity in grouped) grouped[f.severity].push(f);

        const sections = [];
        for (const sev of ['critical', 'high', 'medium', 'low']) {
            if (!grouped[sev].length) continue;
            sections.push('\n' + sevHeader[sev] + '\n');
            grouped[sev].forEach((f, i) => {
                const src = f.source === 'llm' ? 'ניתוח LLM' : 'סריקת regex';
                sections.push(`### ${i + 1}. \`${f.target}\``);
                sections.push(`**קטגוריה:** ${f.category} | **מקור:** ${src}`);
                sections.push(`**בעיה:** ${f.finding}`);
                sections.push(`**תיקון מוצע:** ${f.recommendation}`);
                if (f.codeContext) {
                    sections.push('\n**קוד בהקשר:**');
                    sections.push('```javascript');
                    sections.push(f.codeContext);
                    sections.push('```');
                }
                sections.push('\n---');
            });
        }

        const checklist = [
            '\n## רשימת תיקונים (Checklist)',
            '',
            sorted.slice(0, 30).map(f =>
                `- [ ] **[${(f.severity || '').toUpperCase()}]** \`${f.target}\` — ${f.recommendation || f.finding}`
            ).join('\n'),
        ].join('\n');

        const markdown = findings.length
            ? header + sections.join('\n') + checklist
            : '# דוח שגיאות קוד — Jarvis\n\n✅ לא נמצאו שגיאות קוד.';

        res.setHeader('Content-Type', 'text/plain; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="jarvis-error-report-${new Date().toISOString().slice(0,10)}.md"`);
        res.send(markdown);
    } catch (err) {
        console.error('❌ /dashboard/error-report/export:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ─── POST /scan/errors/run — run code scan AND persist it as a report ─────────
// Saved as a 'code_scan' run in e2e_reports so it shows up in the same reports
// list as E2E runs and can be sent to Claude from there (returns a run_id).
app.post('/scan/errors/run', _rl(5), async (_req, res) => {
    try {
        const { runCodeErrorScanner } = require('./agents/e2e/codeErrorScanner');
        const { findings, claudePrompt, summary, score } = await runCodeErrorScanner({});
        const runId = require('crypto').randomUUID();
        let persisted = false;
        if (findings.length) {
            try {
                await persistFindings(supabase, runId, findings, 'code_scan');
                persisted = true;
            } catch (pe) {
                console.error('❌ /scan/errors/run: persist failed:', pe.message);
            }
        }
        res.json({
            run_id: runId,
            kind: 'code_scan',
            persisted,
            findings,
            counts: countsBySeverity(findings),
            score,
            summary,
            claudePrompt,
        });
    } catch (err) {
        console.error('❌ /scan/errors/run:', err.message);
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
        const { data, error } = await repos.contacts.create(row);
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
        const { data, error } = await repos.contacts.updateById(req.params.id, updates);
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
        const { data, error } = await repos.shopping.updateById(req.params.id, updates);
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
        applySaverMode(settings);
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

        // Signal to client that processing has begun — reduces perceived latency before first token.
        send({ thinking: true, agent: agentName });

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
                const ctx = { userMessage, supabase, repos, useLocal, settings, sendEmail, chatId };
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

        settings.chatSummary = chatSummary && chatSummary.length > 600
            ? chatSummary.slice(0, 600) + '…'
            : chatSummary;
        const voiceMode = settings.voiceMode === true;
        // Honor responseLength (and saver mode's _maxTokensCap) — mirrors runChatAgent.
        const _lengthCaps = { short: 350, medium: 800, long: 1400 };
        let maxTokens = voiceMode ? 200 : (_lengthCaps[settings.responseLength] || 800);
        if (typeof settings._maxTokensCap === 'number') {
            maxTokens = Math.min(maxTokens, settings._maxTokensCap);
        }

        const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings, null, userMessage);
        const msgs = [
            { role: 'system', content: systemPrompt },
            ...chatHistory.map(m => ({ role: m.role === 'jarvis' ? 'assistant' : 'user', content: m.text })),
            { role: 'user', content: userMessage },
        ];

        let fullAnswer = '';
        let chunkBuffer = '';
        let flushTimer = null;
        const MIN_CHUNK_CHARS = 8;
        const MAX_CHUNK_WAIT_MS = 40;

        const flushChunkBuffer = () => {
            if (chunkBuffer) { send({ chunk: chunkBuffer }); fullAnswer += chunkBuffer; chunkBuffer = ''; }
            flushTimer = null;
        };

        await callGemma4Stream(msgs, useLocal, (chunk) => {
            chunkBuffer += chunk;
            if (chunkBuffer.length >= MIN_CHUNK_CHARS) {
                if (flushTimer) { clearTimeout(flushTimer); flushTimer = null; }
                flushChunkBuffer();
            } else if (!flushTimer) {
                flushTimer = setTimeout(flushChunkBuffer, MAX_CHUNK_WAIT_MS);
            }
        }, controller.signal, maxTokens);

        if (flushTimer) { clearTimeout(flushTimer); flushTimer = null; }
        flushChunkBuffer();

        // Proactive inline nudge (text chat only; skipped in voice mode) — mirrors /ask-jarvis.
        if (agentName === 'chat' && !voiceMode && !/[?？]\s*$/.test(fullAnswer)
            && proactiveEngine.shouldNudgeInline(chatId)) {
            let nudgeTimer;
            try {
                const sug = await Promise.race([
                    proactiveEngine.computeProactiveSuggestion(supabase, userMessage),
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
            autoExtractMemory(originalMessage, fullAnswer, repos, settings).catch(e => systemLog.logError('autoExtractMemory:stream', e).catch(() => {}));
            loadChatHistory(chatId).then(fresh => {
                conversationSummary.updateSummaryIfNeeded(chatId, fresh, supabase, settings).catch(e => systemLog.logError('updateSummaryIfNeeded:stream', e).catch(() => {}));
            }).catch(e => systemLog.logError('loadChatHistory:stream', e).catch(() => {}));
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
        const isDb = /supabase|PGRST|relation/i.test(err.message || '');
        const userMsg = isRateLimit
            ? '⏳ כל ספקי ה-AI עמוסים כרגע (מגבלת קצב). נסה שוב בעוד כמה דקות.'
            : isDb
                ? 'מסד הנתונים לא זמין כרגע. הפעולה לא בוצעה — נסה שוב בעוד רגע.'
                : 'שגיאת מערכת.';
        send({ chunk: userMsg, done: true, suggestions: ['נסה שוב'] });
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

// Fire due reminders: mark one-time reminders fired, reschedule recurring ones
// to their next occurrence. Extracted from the per-minute cron so the logic is
// unit-testable independent of node-cron and the test-env guard.
async function fireDueReminders(db = supabase, nowIso = new Date().toISOString()) {
    try {
        const { data: due, error } = await db
            .from('reminders')
            .select('id, text, scheduled_time, recurrence')
            .eq('fired', false)
            .lte('scheduled_time', nowIso);

        if (error) { console.error('⏰ Cron error:', error.message); return { fired: 0, rescheduled: 0 }; }
        if (!due || due.length === 0) return { fired: 0, rescheduled: 0 };

        due.forEach(r => console.log(`🔔 REMINDER: ${r.text} [${r.scheduled_time}]${r.recurrence ? ` 🔁 ${r.recurrence}` : ''}`));

        let fired = 0, rescheduled = 0;
        for (const r of due) {
            const next = r.recurrence ? computeNextOccurrence(r.scheduled_time, r.recurrence) : null;
            if (next) {
                // Recurring: reschedule to next occurrence
                await db.from('reminders')
                    .update({ scheduled_time: next.toISOString(), fired: false })
                    .eq('id', r.id);
                console.log(`🔁 Rescheduled "${r.text}" → ${next.toISOString()}`);
                // Push recurring reminders — app won't have pre-scheduled them for future occurrences
                pushService.sendPush({
                    title: 'ג׳רביס 🔔',
                    body: r.text,
                    data: { reminderId: String(r.id) },
                    category: 'reminder',
                }).catch(() => {});
                rescheduled++;
            } else {
                // One-time: mark as fired
                await db.from('reminders').update({ fired: true }).eq('id', r.id);
                // Push only if the reminder was created very recently (app couldn't pre-schedule it)
                const createdRecently = r.created_at
                    ? (Date.now() - new Date(r.created_at).getTime()) < 2 * 60 * 1000
                    : false;
                if (createdRecently) {
                    pushService.sendPush({
                        title: 'ג׳רביס 🔔',
                        body: r.text,
                        data: { reminderId: String(r.id) },
                        category: 'reminder',
                    }).catch(() => {});
                }
                fired++;
            }
        }
        return { fired, rescheduled };
    } catch (err) {
        console.error('⏰ Cron unexpected error:', err.message);
        return { fired: 0, rescheduled: 0 };
    }
}

if (!isTestEnv) scheduledJob('fire_reminders', '* * * * *', () => fireDueReminders());

// Hourly cleanup of expired session/recent memories (24h / 7d TTLs).
if (!isTestEnv) scheduledJob('memory_cleanup_hourly', '17 * * * *', async () => {
    const res = await cleanupExpiredMemories(supabase);
    if (res.deleted > 0) cacheInvalidate('memories');
    if (res.errors?.length) console.warn('🧹 memoryCleanup errors:', res.errors);
});

// ─── Proactive Notification Helpers ──────────────────────────────────────────

/**
 * Queue a notification for the in-app feed AND send a push to the device.
 * Existing call sites pass only `text`; the options object is optional.
 * @param {string} text
 * @param {{ title?: string, category?: string }} [opts]
 */
async function enqueueNotification(text, opts = {}) {
    const { title = 'ג׳רביס 🤖', category = 'proactive' } = opts;
    // Always write to the reminders feed (in-app polling)
    await supabase.from('reminders').insert([{
        text,
        scheduled_time: new Date().toISOString(),
        fired: true,
    }]);
    // Also push to the device when a driver is configured
    pushService.sendPush({ title, body: text, category }).catch(() => {});
}

// ─── Scheduled job wrapper ────────────────────────────────────────────────────
// Wraps cron.schedule with error capture → system_events + cron_runs tracking.
function scheduledJob(name, expr, fn, cronOpts = {}) {
    return cron.schedule(expr, async () => {
        let jobErr = null;
        try { await fn(); } catch (err) { jobErr = err; }

        if (jobErr) {
            systemLog.logError(`cron:${name}`, jobErr).catch(() => {});
            // Use .then(ok, err) instead of .catch() — Supabase v2 builder is
            // thenable but doesn't expose .catch() as a standalone method.
            supabase.from('cron_runs').upsert(
                { job_name: name, last_err_at: new Date().toISOString(), last_error: jobErr.message?.slice(0, 500) },
                { onConflict: 'job_name' }
            ).then(null, () => {});
        } else {
            supabase.from('cron_runs').upsert(
                { job_name: name, last_ok_at: new Date().toISOString() },
                { onConflict: 'job_name' }
            ).then(null, () => {});
        }
    }, cronOpts);
}

// ─── Morning briefing builder ─────────────────────────────────────────────────

async function buildMorningBriefing(city = '') {
    const nowJer = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
    const dayName = nowJer.toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });

    const dayStart = new Date(nowJer); dayStart.setHours(0, 0, 0, 0);
    const dayEnd   = new Date(nowJer); dayEnd.setHours(23, 59, 59, 999);

    const [{ data: pendingTasks }, { data: todayReminders }, weatherData, newsData] = await Promise.all([
        supabase.from('tasks').select('id, content, priority').eq('done', false)
            .order('priority', { ascending: false }).limit(10),
        supabase.from('reminders').select('text, scheduled_time').eq('fired', false)
            .gte('scheduled_time', dayStart.toISOString())
            .lt('scheduled_time', dayEnd.toISOString())
            .order('scheduled_time', { ascending: true }),
        (async () => { try { const { getWeatherSummary } = require('./services/weatherSource'); return await getWeatherSummary(city); } catch { return null; } })(),
        (async () => { try { const { getNewsSummary }    = require('./services/newsSource');    return await getNewsSummary();         } catch { return null; } })(),
    ]);

    let briefing = `🌅 בוקר טוב! ${dayName}\n`;

    // Weather block
    if (weatherData?.summary) {
        briefing += `\n${weatherData.summary}\n`;
    }

    // Tasks block
    if (pendingTasks?.length > 0) {
        const high = pendingTasks.filter(t => t.priority === 'high');
        briefing += `\n📋 ${pendingTasks.length} משימות פתוחות`;
        if (high.length > 0) briefing += ` (${high.length} דחופות)`;
        briefing += ':\n';
        pendingTasks.slice(0, 5).forEach((t, i) => {
            const prio = t.priority === 'high' ? ' 🔴' : '';
            briefing += `${i + 1}. ${t.content}${prio}\n`;
        });
    } else {
        briefing += '\n✅ אין משימות פתוחות — יום נקי!\n';
    }

    // Reminders block
    if (todayReminders?.length > 0) {
        briefing += `\n⏰ תזכורות להיום:\n`;
        todayReminders.slice(0, 5).forEach(r => {
            const timeStr = new Date(r.scheduled_time).toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit' });
            briefing += `• ${r.text} — ${timeStr}\n`;
        });
    }

    // News headlines
    if (newsData?.headlines?.length > 0) {
        briefing += `\n📰 כותרות:\n`;
        newsData.headlines.slice(0, 3).forEach(h => { briefing += `• ${h}\n`; });
    }

    return briefing.trim();
}

// ─── Boot-time morning briefing catch-up ─────────────────────────────────────
// Render free tier may sleep and miss the 07:00 cron. On startup, if the
// briefing hasn't run today and the hour is between 07:00–12:00 Jerusalem, fire
// it now so the user doesn't lose the daily summary.
if (!isTestEnv) {
    (async () => {
        try {
            const nowJer = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
            const hour = nowJer.getHours();
            if (hour < 7 || hour >= 12) return; // outside catch-up window
            const today = nowJer.toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' });
            const { data } = await supabase.from('cron_runs')
                .select('last_ok_at')
                .eq('job_name', 'morning_briefing')
                .maybeSingle().catch(() => ({ data: null }));
            const lastOk = data?.last_ok_at;
            if (lastOk && lastOk.startsWith(today)) return; // already ran today
            console.log('🌅 [boot] Running missed morning briefing catch-up');
            const profile = await getUserProfile().catch(() => null);
            const briefingText = await buildMorningBriefing(profile?.city || '');
            await enqueueNotification(briefingText, { title: '🌅 תדריך בוקר', category: 'briefing' });
            await supabase.from('cron_runs').upsert(
                { job_name: 'morning_briefing', last_ok_at: new Date().toISOString() },
                { onConflict: 'job_name' }
            ).catch(() => {});
        } catch (err) {
            systemLog.logError('boot:morning_briefing_catchup', err).catch(() => {});
        }
    })();
}

// Morning briefing — 7:00 AM Jerusalem
if (!isTestEnv) scheduledJob('morning_briefing', '0 7 * * *', async () => {
    const profile = await getUserProfile().catch(() => null);
    const city = profile?.city || '';
    const briefingText = await buildMorningBriefing(city);
    await enqueueNotification(briefingText, { title: '🌅 תדריך בוקר', category: 'briefing' });
    console.log('🌅 Morning briefing queued');
}, { timezone: 'Asia/Jerusalem' });

// Evening nudge — 21:00 Jerusalem (only when tasks remain open)
if (!isTestEnv) scheduledJob('evening_nudge', '0 21 * * *', async () => {
    const { data: tasks } = await supabase.from('tasks').select('id').eq('done', false);
    if (!tasks || tasks.length === 0) return;
    await enqueueNotification(`יש לך ${tasks.length} משימות פתוחות. לילה טוב ✨`, { title: '🌙 ג׳רביס', category: 'proactive' });
    console.log('🌙 Evening nudge queued');
}, { timezone: 'Asia/Jerusalem' });

// Proactive midday push — 13:00 Jerusalem. Fires at most once/day and only on
// high-signal task states (overdue / stale high-priority), so it complements
// the morning briefing and evening nudge without nagging.
let _lastProactivePushDate = null;
if (!isTestEnv) scheduledJob('proactive_push', '0 13 * * *', async () => {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' });
    if (_lastProactivePushDate === today) return;
    const sug = await proactiveEngine.computeProactiveSuggestion(supabase);
    if (sug && (sug.type === 'overdue' || sug.type === 'stale_high')) {
        await enqueueNotification(`💡 ${sug.message}`, { title: '💡 ג׳רביס', category: 'proactive' });
        _lastProactivePushDate = today;
        console.log('💡 Proactive push queued:', sug.type);
    }
}, { timezone: 'Asia/Jerusalem' });

// Daily cron — 09:00 Jerusalem — flag agents inactive for 7+ days
if (!isTestEnv) scheduledJob('inactive_agent_check', '0 9 * * *', async () => {
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
}, { timezone: 'Asia/Jerusalem' });

// Daily deep-clean at 03:30 — re-run the same cleanupExpiredMemories that runs
// hourly, but with full Pinecone + Obsidian sync. Catches anything the hourly
// job missed and keeps the three stores aligned.
if (!isTestEnv) scheduledJob('memory_cleanup_nightly', '30 3 * * *', async () => {
    const res = await cleanupExpiredMemories(supabase);
    if (res.deleted > 0) {
        cacheInvalidate('memories');
        console.log(`🧹 nightly memoryCleanup: removed ${res.deleted} expired memories`);
    }
    if (res.errors?.length) console.warn('🧹 nightly memoryCleanup errors:', res.errors);
}, { timezone: 'Asia/Jerusalem' });

// Daily user-profile learning — 03:45 Jerusalem (after the 03:30 memory cleanup).
// Derives preferred hours / interests / recurring tasks from behaviour and
// writes them into the profile without clobbering fields the user set manually.
if (!isTestEnv) scheduledJob('profile_learning', '45 3 * * *', async () => {
    const r = await profileLearner.learnUserProfile(supabase, { getProfile: getUserProfile });
    if (r.updated) console.log('🧠 User profile auto-learned from behaviour');
    if (r.updated) cacheInvalidate('userProfile');
    const s = await styleLearner.learnStyle(supabase, {
        getProfile: getUserProfile,
        onUpdate: () => cacheInvalidate('userProfile'),
    });
    if (s.updated) console.log('🎯 Style prefs learned from feedback:', JSON.stringify(s.learned));
}, { timezone: 'Asia/Jerusalem' });

app.get('/chart.js', (_req, res) => {
    res.sendFile(path.join(__dirname, 'node_modules/chart.js/dist/chart.umd.min.js'),
        err => { if (err && !res.headersSent) res.status(404).send('Not found'); });
});

const { createAgentCenterRouter } = require('./routes/agentCenter');
app.use('/progress-map', _rl(20), createAgentCenterRouter({ callGemma4, agentMetrics }));
app.get('/agent-center', (_req, res) => res.redirect(301, '/progress-map'));
app.get('/control-center', (_req, res) => res.redirect(301, '/progress-map'));

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

// PATCH /dashboard/features — move a feature between buckets and/or update its description
app.patch('/dashboard/features', (req, res) => {
    const { name, oldStatus, newStatus, desc } = req.body;
    if (!name || !oldStatus) return res.status(400).json({ error: 'name and oldStatus required' });
    const VALID = ['done', 'building', 'planned'];
    if (!VALID.includes(oldStatus)) return res.status(400).json({ error: 'invalid oldStatus' });
    const dst = VALID.includes(newStatus) ? newStatus : oldStatus;
    try {
        const filePath = path.join(__dirname, 'features.json');
        const data = JSON.parse(require('fs').readFileSync(filePath, 'utf8'));
        const feats = data.features;
        const idx = (feats[oldStatus] || []).findIndex(f => f.name === name);
        if (idx === -1) return res.status(404).json({ error: 'Feature not found' });
        const feature = { ...feats[oldStatus][idx] };
        if (desc !== undefined) feature.desc = desc;
        feats[oldStatus].splice(idx, 1);
        if (!feats[dst]) feats[dst] = [];
        feats[dst].push(feature);
        data.lastUpdated = new Date().toISOString().slice(0, 10);
        require('fs').writeFileSync(filePath, JSON.stringify(data, null, 2));
        res.json({ ok: true, feature, movedFrom: oldStatus, movedTo: dst });
    } catch (err) {
        console.error('PATCH /dashboard/features error:', err.message);
        res.status(500).json({ error: 'Internal error' });
    }
});

// POST /dashboard/features — add a new feature
app.post('/dashboard/features', (req, res) => {
    const { name, desc = '', status = 'planned' } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'name required' });
    const VALID = ['done', 'building', 'planned'];
    const bucket = VALID.includes(status) ? status : 'planned';
    try {
        const filePath = path.join(__dirname, 'features.json');
        const data = JSON.parse(require('fs').readFileSync(filePath, 'utf8'));
        if (!data.features[bucket]) data.features[bucket] = [];
        // Prevent duplicates
        const exists = (data.features.done || []).concat(data.features.building || [], data.features.planned || [])
            .some(f => f.name.trim().toLowerCase() === name.trim().toLowerCase());
        if (exists) return res.status(409).json({ error: 'Feature with this name already exists' });
        data.features[bucket].push({ name: name.trim(), desc: desc.trim() });
        data.lastUpdated = new Date().toISOString().slice(0, 10);
        require('fs').writeFileSync(filePath, JSON.stringify(data, null, 2));
        res.json({ ok: true });
    } catch (err) {
        console.error('POST /dashboard/features error:', err.message);
        res.status(500).json({ error: 'Internal error' });
    }
});

// DELETE /dashboard/features — remove a feature
app.delete('/dashboard/features', (req, res) => {
    const { name, status } = req.body;
    if (!name || !status) return res.status(400).json({ error: 'name and status required' });
    try {
        const filePath = path.join(__dirname, 'features.json');
        const data = JSON.parse(require('fs').readFileSync(filePath, 'utf8'));
        const before = (data.features[status] || []).length;
        data.features[status] = (data.features[status] || []).filter(f => f.name !== name);
        if (data.features[status].length === before) return res.status(404).json({ error: 'Not found' });
        data.lastUpdated = new Date().toISOString().slice(0, 10);
        require('fs').writeFileSync(filePath, JSON.stringify(data, null, 2));
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /dashboard/features error:', err.message);
        res.status(500).json({ error: 'Internal error' });
    }
});

// POST /dashboard/features/suggest-description — AI-generated description for one feature
app.post('/dashboard/features/suggest-description', async (req, res) => {
    const { name, status = 'planned' } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'name required' });
    const statusHe = status === 'done' ? 'הושלמה' : status === 'building' ? 'בפיתוח' : 'מתוכננת';
    try {
        const prompt = `אתה מתאר יכולת של "ג'רביס" — עוזר AI אישי בעברית (Flutter + Node.js).

יכולת: "${name}" (סטטוס: ${statusHe})

כתוב תיאור קצר וברור של היכולת — 1-2 משפטים בעברית.
התיאור צריך להסביר: מה היכולת עושה ואיך היא מועילה למשתמש.
ענה בתיאור בלבד, ללא כותרת, ללא JSON.`;
        const raw = await callGemma4(prompt, false, 200);
        const description = raw.trim().replace(/^["']|["']$/g, '').slice(0, 300);
        res.json({ description });
    } catch (err) {
        console.error('POST /dashboard/features/suggest-description error:', err.message);
        res.status(500).json({ error: 'שגיאה בייצור תיאור' });
    }
});

// POST /dashboard/features/generate-descriptions — batch AI descriptions for empty features
app.post('/dashboard/features/generate-descriptions', async (req, res) => {
    const { features = [] } = req.body; // [{ name, status, desc }]
    const needDesc = features.filter(f => !f.desc?.trim()).slice(0, 12); // cap at 12
    if (needDesc.length === 0) return res.json({ descriptions: [] });
    try {
        const list = needDesc.map(f => `- "${f.name}" (${f.status === 'done' ? 'הושלמה' : f.status === 'building' ? 'בפיתוח' : 'מתוכננת'})`).join('\n');
        const prompt = `אתה מתאר יכולות של "ג'רביס" — עוזר AI אישי בעברית (Flutter + Node.js).

צור תיאור קצר (משפט אחד, עד 100 תווים) לכל יכולת הבאה:
${list}

ענה JSON בלבד (ללא markdown):
[{"name":"שם היכולת","description":"תיאור קצר"}]`;
        const raw = await callGemma4(prompt, false, 800);
        const stripped = raw.replace(/```(?:json)?/gi, '').replace(/```/g, '').trim();
        const start = stripped.indexOf('[');
        const end   = stripped.lastIndexOf(']');
        if (start === -1 || end === -1) return res.json({ descriptions: [] });
        const parsed = JSON.parse(stripped.slice(start, end + 1));
        const descriptions = (Array.isArray(parsed) ? parsed : [])
            .filter(d => d.name && d.description)
            .map(d => ({ name: d.name.toString(), description: d.description.toString().slice(0, 150) }));
        res.json({ descriptions });
    } catch (err) {
        console.error('POST /dashboard/features/generate-descriptions error:', err.message);
        res.status(500).json({ error: 'שגיאה בייצור תיאורים' });
    }
});

// Architecture context per proposal category — injected into LLM prompts for grounding
function _getArchContext(category) {
    const base = `==מבנה הפרויקט==
קבצים מרכזיים: server.js (Express, ~5400 שורות), agents/ (24 agents), services/, controllers/, routes/
טסטים: tests/unit/ (Jest) | פקודות: npm test, npm run test:coverage, npx jest tests/unit/X.test.js
Flutter: jarvis_mobile/lib/ (screens/, widgets/, services/)
DB: Supabase (chat_history, tasks, reminders, memories, habits, projects, shopping_items, notes)`;
    const catMap = {
        bug_fix: `\n\nקבצים נפוצים לבאגים: agents/router.js, agents/models.js, server.js (handler ספציפי), agents/utils.js
תבנית תיקון: זהה root cause → תקן במקום אחד → הוסף regression test ב-tests/unit/`,
        feature: `\n\nתבנית agent חדש:
1. agents/myAgent.js — exports runMyAgent(userMessage, supabase, useLocal, settings) → {answer, action?}
2. agents/router.js — הוסף ל-KEYWORDS{} + VALID_INTENTS + LLM_CLASSIFY_PROMPT
3. server.js — import + case ב-POST /ask-jarvis + POST /stream-jarvis
4. tests/unit/myAgent.test.js — מוק Supabase עם jest.mock()`,
        ux: `\n\nקבצים frontend: progress-map.html (HTML+JS+CSS), agent-center.html
Flutter: jarvis_mobile/lib/screens/, jarvis_mobile/lib/widgets/
Endpoints רלוונטיים: GET /stats, GET /user-profile, POST /user-profile`,
        performance: `\n\nLLM stack: agents/models.js — callGemma4() עם failover Ollama→Groq→DeepSeek→Gemini
Cache: in-process TTL (memories 5min, chat 30s)
שיפור ביצועים: הפחת tokens, הוסף cache, קצר system prompts, עבד במקביל עם Promise.all`,
        improvement: `\n\nלפי תחום: agents/ לשיפור agent, server.js לשיפור endpoint, services/ לשיפור service layer
פונקציות שיתופיות ב-agents/utils.js — השתמש בהן במקום לשכפל`,
    };
    return base + (catMap[category] || catMap.improvement);
}

// Fetch recent e2e failures for proposal context enrichment (best-effort)
async function _getRecentBugContext(supabaseClient) {
    try {
        const { data } = await supabaseClient
            .from('e2e_reports')
            .select('summary, created_at')
            .eq('status', 'fail')
            .order('created_at', { ascending: false })
            .limit(3);
        if (!data?.length) return '';
        return '\n\n==תקלות אחרונות (e2e reports)==\n' +
            data.map(r => `- ${(r.summary || '').slice(0, 120)}`).join('\n');
    } catch (_) { return ''; }
}

// Deterministic fallback questions per category (used when LLM is unavailable)
function _clarifyFallback(category, title) {
    const base = [
        { id: 'q1', question: 'מה הסדר עדיפויות של הפיתוח הזה?', chips: ['דחוף — נדרש עכשיו', 'בינוני — בשבועות הקרובים', 'נמוך — יום אחד'] },
        { id: 'q2', question: 'באיזה חלק של המערכת מתמקד השינוי?', chips: ['Flutter (אפליקציה)', 'Node.js (שרת)', 'שניהם'] },
    ];
    const byCategory = {
        feature:     [{ id: 'q3', question: 'מי המשתמש העיקרי של הפיצ\'ר הזה?', chips: ['המשתמש היומיומי', 'מנהל/אדמין', 'שניהם'] }],
        bug_fix:     [{ id: 'q3', question: 'כמה דחוף תיקון הבאג?', chips: ['קריטי — חוסם שימוש', 'מציק אך לא חוסם', 'קוסמטי בלבד'] }],
        ux:          [{ id: 'q3', question: 'מה ה-friction העיקרי שרוצים לפתור?', chips: ['יותר מהיר', 'יותר ברור', 'יותר אינטואיטיבי'] }],
        performance: [{ id: 'q3', question: 'מה מדד ההצלחה לשיפור הביצועים?', chips: ['זמן טעינה <1 שניה', 'פחות קריאות API', 'פחות זיכרון/סוללה'] }],
        improvement: [{ id: 'q3', question: 'מה ההשפעה הצפויה של השיפור?', chips: ['חוויה טובה יותר', 'פחות שגיאות', 'יותר נתונים/תובנות'] }],
    };
    return [...base, ...(byCategory[category] || byCategory.improvement)];
}

// POST /dashboard/smart-proposals/clarify — AI generates 2-3 targeted clarifying questions
// for a smart proposal, each with 3 suggested chip answers
app.post('/dashboard/smart-proposals/clarify', async (req, res) => {
    const { title = '', description = '', category = 'improvement', rationale = '' } = req.body;
    if (!title.trim()) return res.status(400).json({ error: 'title required' });
    const catHe = { bug_fix: 'תיקון באג', ux: 'שיפור UX', performance: 'ביצועים', feature: "פיצ'ר", improvement: 'שיפור' }[category] || 'שיפור';
    const archCtx = _getArchContext(category);
    const sysPrompt = `אתה עוזר טכני בכיר שמכין פרומפט ל-Claude Code CLI עבור "ג'רביס" (Flutter + Node.js).
${archCtx}

ניתנת לך הצעת פיתוח. צור 2-3 שאלות קצרות וטכניות שיאפשרו לקלוד קוד לממש בצורה מדויקת.
שאלות טובות: על approach טכני (באיזה קובץ, איזו פונקציה), על scope (מה כן/לא לגעת), על התנהגות קצה, על מה לא לשבור.
שאלות גרועות: "כמה חשוב לך?", "מתי?", שאלות כלליות ללא הקשר טכני.
לכל שאלה — ספק 3 אפשרויות תשובה קצרות בעברית (chips).
ענה JSON בלבד, ללא markdown: [{"id":"q1","question":"...","chips":["...","...","..."]}]`;
    const userMsg = `הצעה: ${title}
קטגוריה: ${catHe}
${description ? `תיאור: ${description}` : ''}
${rationale ? `רציונל: ${rationale}` : ''}
צור 2-3 שאלות טכניות-ממוקדות.`;
    try {
        const raw = await callGemma4(`${sysPrompt}\n\n${userMsg}`, false, 800);
        const stripped = raw.replace(/```(?:json)?/gi, '').replace(/```/g, '').trim();
        const start = stripped.indexOf('[');
        const end   = stripped.lastIndexOf(']');
        if (start === -1 || end === -1) return res.json({ questions: _clarifyFallback(category, title) });
        const parsed = JSON.parse(stripped.slice(start, end + 1));
        const questions = (Array.isArray(parsed) ? parsed : []).slice(0, 3).map((q, i) => ({
            id: q.id || `q${i + 1}`,
            question: (q.question || '').toString().trim(),
            chips: (Array.isArray(q.chips) ? q.chips : []).slice(0, 3).map(c => c.toString().trim()),
        })).filter(q => q.question);
        res.json({ questions: questions.length ? questions : _clarifyFallback(category, title) });
    } catch (err) {
        console.warn('POST /dashboard/smart-proposals/clarify LLM failed, using fallback:', err.message);
        res.json({ questions: _clarifyFallback(category, title) });
    }
});

// Deterministic fallback prompt (used when LLM unavailable)
function _refineFallback({ title, description, category, rationale, answers }) {
    const catHe = { bug_fix: 'תיקון באג', ux: 'שיפור UX', performance: 'ביצועים', feature: "פיצ'ר", improvement: 'שיפור' }[category] || 'שיפור';
    const answersBlock = (answers || []).length
        ? `\nפרטים:\n${answers.map(a => `- ${a.question}: ${a.answer}`).join('\n')}`
        : '';
    return `📋 הצעת פיתוח ב-Jarvis: ${title}
סוג: ${catHe}

תיאור:
${description}${rationale ? `\n\nרציונל:\n${rationale}` : ''}${answersBlock}

בקשה לפיתוח (Flutter + Node.js):
1. מה בדיוק לממש — תיאור טכני מפורט
2. אילו קבצים/מודולים לשנות או ליצור (Flutter ו/או Node.js)
3. סדר עבודה מומלץ עם אבני דרך
4. קצוות קצה ומקרי שגיאה לטפל בהם
5. מה לבדוק לאחר הפיתוח`;
}

// POST /dashboard/smart-proposals/refine-prompt — builds a refined dev prompt from proposal + answers
app.post('/dashboard/smart-proposals/refine-prompt', async (req, res) => {
    const { title = '', description = '', category = 'improvement', rationale = '', answers = [] } = req.body;
    if (!title.trim()) return res.status(400).json({ error: 'title required' });
    const catHe = { bug_fix: 'תיקון באג', ux: 'שיפור UX', performance: 'ביצועים', feature: "פיצ'ר", improvement: 'שיפור' }[category] || 'שיפור';
    const answersBlock = answers.length
        ? answers.map(a => `- ${a.question}: ${a.answer}`).join('\n')
        : '';
    const archCtx = _getArchContext(category);
    const sysPrompt = `אתה כותב פרומפט מקצועי ל-Claude Code CLI עבור "ג'רביס" (Node.js + Flutter).
הפרומפט שתכתוב ייכנס ישירות ל-Claude Code וירוץ שינויי קוד אמיתיים — חייב להיות מדויק ומלא.

${archCtx}

==מבנה הפרומפט שתכתוב==
כתוב בעברית ובמבנה הבא (בדיוק):

**הקשר**
[2-3 שורות: מה קיים היום, מה לא עובד / חסר, למה זה חשוב עכשיו]

**משימה**
[תיאור טכני מלא ומדויק של מה לממש — ללא עמימות]

**קבצים לגעת בהם**
[רשימה מפורשת: \`path/to/file.js\` — מה משנים/מוסיפים שם]

**סדר ביצוע**
1. [צעד ראשון קונקרטי]
2. [צעד שני]
... (כל הצעדים)

**טסטים להריץ**
\`\`\`
npm test
npx jest tests/unit/X.test.js --verbose
\`\`\`

**קריטריוני הצלחה**
- [ ] [דבר ספציפי שחייב לעבוד]
- [ ] [עוד קריטריון]
... (3-5 בדיקות)

כתוב את הפרומפט ישירות — ללא הקדמה, ללא JSON, ללא "הנה הפרומפט:".
אסור: ניסוחים מעורפלים ("תוכל לשקול", "אולי כדאי"). כל משפט — הנחיה ספציפית.`;
    const userMsg = `הצעה: ${title}
קטגוריה: ${catHe}
${description ? `תיאור: ${description}` : ''}
${rationale ? `רציונל: ${rationale}` : ''}
${answersBlock ? `\nפרטים שהמשתמש סיפק:\n${answersBlock}` : ''}`;
    try {
        const raw = await callGemma4(`${sysPrompt}\n\n${userMsg}`, false, 1500);
        res.json({ prompt: raw.trim() });
    } catch (err) {
        console.warn('POST /dashboard/smart-proposals/refine-prompt LLM failed, using fallback:', err.message);
        res.json({ prompt: _refineFallback({ title, description, category, rationale, answers }) });
    }
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
        if (body.claudePrompt) item.claudePrompt = body.claudePrompt.slice(0, 5000);

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
app.post('/dashboard/backlog/generate', async (req, res) => {
    const { userName = '' } = req.body || {};
    try {
        const features = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'features.json'), 'utf8'));
        const backlog  = readBacklog();

        const done     = features.features?.done     || [];
        const building = features.features?.building || [];
        const planned  = features.features?.planned  || [];

        // ── Pull user context: memories + recent chat themes + bug history ──────
        let memoriesContext = '';
        let chatThemesContext = '';
        let bugContext = '';
        try {
            const [memResult, chatResult] = await Promise.all([
                supabase.from('memories').select('content').order('created_at', { ascending: false }).limit(25),
                supabase.from('chat_history').select('content').eq('role', 'user')
                    .gte('created_at', new Date(Date.now() - 14 * 86400000).toISOString())
                    .order('created_at', { ascending: false }).limit(40),
            ]);
            if (memResult.data?.length) {
                memoriesContext = '\n\n==זיכרונות המשתמש (העדפות, הרגלים)==\n' +
                    memResult.data.map(m => `- ${m.content}`).join('\n');
            }
            if (chatResult.data?.length) {
                const msgs = chatResult.data.map(m => m.content || '').filter(Boolean);
                chatThemesContext = '\n\n==הודעות אחרונות מהמשתמש (14 ימים)==\n' +
                    msgs.slice(0, 20).map(m => `• ${m.slice(0, 120)}`).join('\n');
            }
            bugContext = await _getRecentBugContext(supabase);
        } catch (_) { /* context enrichment is best-effort */ }

        const prompt = `אתה מנהל פרויקט בכיר של "ג'רביס" — עוזר AI אישי ב-Flutter + Node.js.

==ארכיטקטורה==
- שרת: server.js (Express) + agents/ (24 agents, כל agent מייצא run*Agent(userMessage, supabase, useLocal, settings))
- ניתוב: agents/router.js — KEYWORDS regex → LLM fallback → dispatch ב-server.js
- DB: Supabase (chat_history, memories, tasks, reminders, notes, habits, projects...)
- LLM stack: callGemma4() → Ollama → Groq → DeepSeek → Gemini
- Flutter: jarvis_mobile/lib/ — RTL עברית, ORB קולי, WebSocket, SSE streaming
- קבצים מרכזיים: server.js, agents/router.js, agents/chatAgent.js, agents/models.js, jarvis_mobile/lib/main.dart

==conventions==
- agent חדש: agents/X.js → רישום ב-router.js (KEYWORDS + VALID_INTENTS) → dispatch ב-server.js
- test file: tests/unit/X.test.js
- endpoint חדש: route + handler ב-server.js, מוגן ב-requirePolicy אם sensitive

==סטטוס הפרויקט==
הושלם (${done.length}): ${done.map(f => f.name).join(', ')}
בבנייה (${building.length}): ${building.map(f => f.name).join(', ')}
מתוכנן (${planned.length}): ${planned.map(f => f.name).join(', ')}
${memoriesContext}${chatThemesContext}${bugContext}

==מטרה==
הצע 6 פריטי backlog ממוינים לפי דחיפות.
כללים:
- בסס על זיכרונות, הודעות ותקלות — הצעות גנריות ללא בסיס בנתונים = לא רלוונטיות.
- אם המשתמש ביקש פיצ'ר ספציפי בשיחות — הצע לממש אותו.
- אם יש תקלה שעלתה בשיחות או ב-e2e — הצע לתקן אותה.
- ציין קבצים ספציפיים עם שורה משוערת כשידוע (למשל "agents/router.js:~120").

ענה JSON בלבד (ללא markdown):
[{
  "title": "כותרת קצרה בעברית (עד 60 תווים)",
  "plan": "תוכנית טכנית: מה לממש בדיוק ואיך",
  "files": ["agents/X.js:~50", "server.js:~600"],
  "effort": "XS|S|M|L|XL",
  "why_now": "למה עכשיו — בסס על הנתונים שקיבלת",
  "acceptance_criteria": ["קריטריון בדיקה 1", "קריטריון 2"],
  "priority": "high|medium|low",
  "category": "bug|improvement|feature"
}]`;

        const raw = await callGemma4(prompt, false, 1000);

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
            files:    Array.isArray(p.files) ? p.files.filter(f => typeof f === 'string') : [],
            effort:   ['XS','S','M','L','XL'].includes(p.effort) ? p.effort : 'M',
            acceptance_criteria: Array.isArray(p.acceptance_criteria) ? p.acceptance_criteria.filter(c => typeof c === 'string') : [],
            priority: ['high', 'medium', 'low'].includes(p.priority || p['עדיפות'])
                ? (p.priority || p['עדיפות']) : 'medium',
            category: (p.category || p['קטגוריה'] || 'improvement').toString(),
            status: 'proposal',
            generated_at,
            ranking_version: BACKLOG_RANKING_VERSION,
            scores: {
                impact: 3, effort: 3, risk: 2, confidence: 3, weighted_score: 3.2,
            },
            why_now: p.why_now || '',
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
        const { description, proposal, answers } = req.body;

        // Support both legacy (description string) and new (proposal object + answers)
        const title = proposal?.title || description || '';
        const plan  = proposal?.plan  || description || '';
        if (!title.trim() && !plan.trim()) return res.status(400).json({ error: 'description or proposal required' });

        const criteriaSection = proposal?.acceptance_criteria?.length
            ? `\n- קריטריוני קבלה: ${proposal.acceptance_criteria.join(' | ')}`
            : '';
        const effortSection = proposal?.effort ? `\n- היקף משוער: ${proposal.effort}` : '';
        const whyNowSection = proposal?.why_now ? `\n- למה עכשיו: ${proposal.why_now}` : '';
        const answersSection = answers && Object.keys(answers).length
            ? '\n\n==רקע ומוטיבציה מהמשתמש==\n' + Object.entries(answers).map(([q, a]) => `- ${q}: ${a}`).join('\n')
            : '';

        const prompt = `אתה מומחה בכתיבת הוראות ל-Claude Code — עוזר הקוד של Anthropic.

==הקשר פרויקט Jarvis==
- שרת Node.js (server.js, Express) עם 24 agents בתיקיית agents/
- כל agent: run*Agent(userMessage, supabase, useLocal, settings) → { answer, action? }
- ניתוב: agents/router.js — KEYWORDS regex → LLM fallback → dispatch ב-server.js
- DB: Supabase | זיכרון סמנטי: Pinecone | LLM: Groq → DeepSeek → Gemini
- Flutter: jarvis_mobile/lib/ — RTL עברית, ORB קולי, WebSocket
- conventions: agent חדש → router.js (KEYWORDS + VALID_INTENTS) → server.js dispatch | test: tests/unit/X.test.js

==מה לממש==
${title}

==תוכנית==
${plan}${effortSection}${criteriaSection}${whyNowSection}${answersSection}

כתוב פרומפט מובנה ל-Claude Code בעברית, מוכן להדבקה ישירה. השתמש בפורמט הבא בדיוק:

## מטרה
[תיאור קצר של מה לבנות ולמה — כולל הערך למשתמש]

## רקע ודוגמאות
[הבעיה שנפתרת, מתי היא קורה, ואם יש — דוגמה קונקרטית לתרחיש]

## מימוש
[הוראות שלב-אחר-שלב — ישירות, ללא הקדמות]

## קריטריוני קבלה
- [ ] קריטריון 1
- [ ] קריטריון 2

## בדיקה
\`npm test\` + [בדיקה ספציפית לפיצ'ר זה]

---
**לפני שמתחילים לממש:** בדוק את הטענות בפרומפט זה מול הקוד הקיים (Grep / Read לפי הצורך), ואחרי שאימתת את ההנחות — עבור ל-Plan Mode ובנה תוכנית עבודה מפורטת.`;

        const result = await callGemma4(prompt, false, 1200);
        res.json({ prompt: result });
    } catch (e) {
        console.error('generate-prompt error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

// ─── Dashboard – Backlog proposal clarifying questions ───────────────────────
app.post('/dashboard/backlog/analyze', async (req, res) => {
    try {
        const { proposal } = req.body;
        if (!proposal?.title) return res.status(400).json({ error: 'proposal required' });

        const prompt = `אתה עוזר שמסייע לדייק בקשות פיתוח.

ההצעה:
כותרת: "${proposal.title}"
תיאור: "${(proposal.plan || '').slice(0, 400)}"
סוג: ${proposal.category || 'improvement'}

צור 2-3 שאלות שיעזרו להבין **למה** רוצים לבנות את זה ומה חשוב למשתמש.
התמקד ב:
- הסיבה / הצורך שמאחורי ההצעה
- מה הבעיה שזה פותר עכשיו
- דוגמאות קונקרטיות לשימוש

אל תשאל על קבצים, טכנולוגיה, או ארכיטקטורה.
השאלות בשפה יומיומית, כל שאלה עם 2-4 אפשריות.

ענה JSON בלבד:
[
  {
    "label": "שאלה על הצורך / הרקע",
    "options": [{"value": "opt1", "label": "אפשרות 1"}, {"value": "other", "label": "אחר — אפרט"}]
  }
]`;

        let questions = [];
        try {
            const raw = await callGemma4(prompt, false, 500);
            const match = raw.match(/\[[\s\S]*\]/);
            if (match) {
                const parsed = JSON.parse(match[0]);
                if (Array.isArray(parsed)) questions = parsed.slice(0, 4);
            }
        } catch (_) {}

        if (!questions.length) {
            questions = [
                { label: 'מה הבעיה הכי מרגיזה שזה פותר?', options: [{ value: 'friction', label: 'כפתורים / ניווט מסורבל' }, { value: 'missing', label: 'פיצ\'ר שחסר לי כל הזמן' }, { value: 'slow', label: 'תהליך איטי / מייגע' }, { value: 'other', label: 'אחר — אפרט' }] },
                { label: 'מתי נרגיש הכי הרבה את השיפור?', options: [{ value: 'daily', label: 'כל יום' }, { value: 'weekly', label: 'כמה פעמים בשבוע' }, { value: 'rare', label: 'לפעמים, אבל אז זה קריטי' }, { value: 'other', label: 'אחר' }] },
            ];
        }

        res.json({ questions });
    } catch (e) {
        console.error('backlog/analyze error:', e.message);
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

module.exports = { app, cacheInvalidate, evaluatePolicy, requirePolicy, fireDueReminders };

if (require.main === module) {
    const PORT = process.env.PORT || 3000;
    const server = app.listen(PORT, () => {
        console.log(`🚀 JARVIS ONLINE | MULTI-AGENT v3 | PORT: ${PORT}`);
        // Init Pinecone and sync existing memories in background (non-blocking)
        pinecone.ensureInit().then(() => pinecone.syncFromSupabase(supabase)).catch(() => {});
        // Init Obsidian bidirectional sync if vault path is configured
        if (process.env.OBSIDIAN_VAULT_PATH) {
            obsidianSync.initSync({ vaultPath: process.env.OBSIDIAN_VAULT_PATH, supabase })
                .then(() => obsidianSync.fullSyncFromDb())
                .catch(err => console.warn('[ObsidianSync] startup init failed:', err.message));
        }
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
