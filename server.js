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

const { classifyIntent, classifyIntentWithLLM } = require('./agents/router');
const { runTaskAgent }        = require('./agents/taskAgent');
const { runReminderAgent }    = require('./agents/reminderAgent');
const { runMemoryAgent, autoExtractMemory } = require('./agents/memoryAgent');
const { runChatAgent, detectFollowUp, filterRelevantMemories, buildSystemPrompt } = require('./agents/chatAgent');
const conversationSummary = require('./services/conversationSummary');
const { runSportsAgent }      = require('./agents/sportsAgent');
const { runMessagingAgent }   = require('./agents/messagingAgent');
const { runDraftAgent }       = require('./agents/draftAgent');
const { runSecurityAgent }    = require('./agents/securityAgent');
const { runCodeErrorAgent }   = require('./agents/codeErrorAgent');
const { runE2EAgent, buildClaudePrompt, countsBySeverity, computeScore } = require('./agents/e2eAgent');
const { runAgentFactoryAgent} = require('./agents/agentFactoryAgent');
const { runInsightAgent }     = require('./agents/insightAgent');
const { runWeatherAgent }     = require('./agents/weatherAgent');
const { SURVEY_QUESTIONS, selectSurveyQuestions, buildSurveyJson, generateSurveySummary } = require('./agents/surveyAgent');
const { runNewsAgent }        = require('./agents/newsAgent');
const { runShoppingAgent }    = require('./agents/shoppingAgent');
const { runNotesAgent }       = require('./agents/notesAgent');
const { runStocksAgent }      = require('./agents/stocksAgent');
const { runTranslationAgent } = require('./agents/translationAgent');
const { runMusicAgent }       = require('./agents/musicAgent');
const obsidianSync            = require('./services/obsidianSync');
const pinecone                = require('./services/pineconeMemory');
const { createTasksRouter } = require('./routes/tasks');
const { createRemindersRouter } = require('./routes/reminders');
const { createRemindersController } = require('./controllers/remindersController');
const { createChatRouter } = require('./routes/chat');
const { isAllowedByRolePlan, isBlockedAction } = require('./services/policyEngine');

const helmet    = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
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
            scriptSrc:  ["'self'", "'unsafe-inline'", 'unpkg.com', 'cdn.jsdelivr.net'],
            styleSrc:   ["'self'", "'unsafe-inline'"],
            connectSrc: ["'self'"],
            imgSrc:     ["'self'", 'data:'],
        },
    },
}));
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
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

// ─── Obsidian Sync ────────────────────────────────────────────────────────────
obsidianSync.initSync({
    vaultPath: process.env.OBSIDIAN_VAULT_PATH,
    supabase,
}).then(() => obsidianSync.fullSyncFromDb())
  .catch(err => console.error('[ObsidianSync] init error:', err.message));

// ─── In-memory TTL Cache ──────────────────────────────────────────────────────

const _cache = new Map(); // key → { value, expiresAt }

function cacheGet(key) {
    const entry = _cache.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) { _cache.delete(key); return undefined; }
    return entry.value;
}

function cacheSet(key, value, ttlMs) {
    _cache.set(key, { value, expiresAt: Date.now() + ttlMs });
}

function cacheInvalidate(key) { _cache.delete(key); }

const TTL_MEMORIES     = 5  * 60 * 1000; // 5 min
const TTL_CHAT_HISTORY = 30 * 1000;       // 30 sec

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
        const { data, error } = await supabase
            .from('chat_history')
            .select('role, text')
            .eq('chat_id', chatId)
            .order('created_at', { ascending: false })
            .limit(20);

        if (error) throw error;
        const result = (data || []).reverse();
        cacheSet(cacheKey, result, TTL_CHAT_HISTORY);
        return result;
    } catch (err) {
        console.error('⚠️ loadChatHistory fallback:', err.message);
        return chatMemoryFallback.slice(-20);
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
    if (chatMemoryFallback.length > 20) chatMemoryFallback = chatMemoryFallback.slice(-20);
    obsidianSync.appendChatMessage(role, text).catch(() => {});
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
        .replace(/\n{2,}/g, '. ')
        .replace(/\n/g, ' ')
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

async function tryCustomAgent(agentName, userMessage, supabase, useLocal, settings) {
    try {
        const registry = JSON.parse(fs.readFileSync(CUSTOM_REGISTRY, 'utf8'));
        const entry = registry.find(r => r.name === agentName);
        if (!entry) return null;

        const agentPath = entry.filePath;
        // Clear require cache so hot-reload works after factory creates/updates an agent
        delete require.cache[require.resolve(agentPath)];
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

async function getUserProfile() {
    const { data, error } = await supabase
        .from('user_profiles')
        .select('*')
        .order('updated_at', { ascending: false })
        .limit(1);
    if (error) {
        console.error('user_profiles fetch error:', error.message);
        return readLocalProfile();
    }
    const dbProfile = Array.isArray(data) && data.length > 0 ? data[0] : null;
    return dbProfile || readLocalProfile();
}

// ─── Route ────────────────────────────────────────────────────────────────────

async function askJarvisHandler(req, res) {
    try {
        const userMessage = req.body.command || '';
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

        // ── Routing ───────────────────────────────────────────────────────────
        let agentName = imageBase64 ? 'chat' : classifyIntent(userMessage);
        if (agentName === 'chat' && !imageBase64 && userMessage.trim().length > 12) {
            agentName = await classifyIntentWithLLM(userMessage);
        }

        // Follow-up override: if the user is continuing a previous conversation,
        // route to chat even if keywords matched a specialized agent
        const CONTEXT_OVERRIDE_AGENTS = ['sports', 'weather', 'news', 'task', 'insight', 'security', 'e2e', 'factory'];
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
            // Keyword fallback filter (no-op when Pinecone already filtered)
            if (!pinecone.isReady()) {
                longTermMemories = filterRelevantMemories(longTermMemories, userMessage);
            }
            // Inject rolling conversation summary so agent remembers context beyond 20 msgs
            if (agentName === 'chat') {
                settings.chatSummary = await conversationSummary.getSummary(chatId, supabase);
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
        let result;
        if (agentName === 'task') {
            result = await runTaskAgent(userMessage, supabase, useLocal, settings);
        } else if (agentName === 'reminder') {
            result = await runReminderAgent(userMessage, supabase);
        } else if (agentName === 'memory') {
            result = await runMemoryAgent(userMessage, supabase, useLocal, settings);
            cacheInvalidate('memories'); // memory changed — bust cache
        } else if (agentName === 'weather') {
            result = await runWeatherAgent(userMessage, settings);
        } else if (agentName === 'news') {
            result = await runNewsAgent(userMessage, settings);
        } else if (agentName === 'shopping') {
            result = await runShoppingAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'notes') {
            result = await runNotesAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'stocks') {
            result = await runStocksAgent(userMessage);
        } else if (agentName === 'translate') {
            result = await runTranslationAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'music') {
            result = await runMusicAgent(userMessage, supabase, useLocal, settings);
        } else if (agentName === 'sports') {
            result = await runSportsAgent(userMessage);
        } else if (agentName === 'messaging') {
            result = await runMessagingAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'draft') {
            result = await runDraftAgent(userMessage, chatHistory, longTermMemories, settings);
        } else if (agentName === 'insight') {
            result = await runInsightAgent(userMessage, supabase, useLocal, settings);
        } else if (agentName === 'security') {
            result = await runSecurityAgent(userMessage, useLocal, sendEmail);
        } else if (agentName === 'code_error') {
            setImmediate(async () => {
                try {
                    const ceResult = await runCodeErrorAgent(userMessage, useLocal, sendEmail);
                    await saveChatMessage('jarvis', ceResult.answer, chatId);
                    cacheInvalidate(`chatHistory:${chatId}`);
                    console.log('🔍 codeErrorAgent background run saved to chat history');
                } catch (err) {
                    console.error('🔍 codeErrorAgent background run failed:', err.message);
                    await saveChatMessage('jarvis', '❌ סריקת שגיאות נכשלה: ' + err.message, chatId).catch(() => {});
                    cacheInvalidate(`chatHistory:${chatId}`);
                }
            });
            result = { answer: '🔍 מתחיל סריקת שגיאות קוד ברקע — הדוח יופיע בשיחה כשיסיים. רענן את השיחה כדי לראות את התוצאות.', skipTts: true };
        } else if (agentName === 'e2e') {
            // Run in background — return immediately so the HTTP request doesn't time out.
            // The full report is saved to chat_history when the run finishes; the app
            // will see it on the next history refresh.
            const reportChatId = chatId; // Capture chatId in closure
            setImmediate(async () => {
                try {
                    const e2eResult = await runE2EAgent(userMessage, supabase, useLocal, settings);
                    console.log(`🧪 E2E saving to chatId: ${reportChatId}`);
                    await saveChatMessage('jarvis', e2eResult.answer, reportChatId);
                    cacheInvalidate(`chatHistory:${reportChatId}`);
                    console.log('🧪 E2E background run saved to chat history');
                } catch (err) {
                    console.error('🧪 E2E background run failed:', err.message);
                    await saveChatMessage('jarvis', '❌ בדיקות הקצה נכשלו: ' + err.message, reportChatId).catch(() => {});
                    cacheInvalidate(`chatHistory:${reportChatId}`);
                }
            });
            result = { answer: '🧪 מתחיל בדיקות קצה ברקע — הדוח המלא יופיע בשיחה כשיסיים (בד"כ תוך 1-2 דקות). רענן את השיחה כדי לראות את התוצאות.', skipTts: true };
        } else if (agentName === 'factory') {
            result = await runAgentFactoryAgent(userMessage, supabase, useLocal);
        } else {
            // Try a dynamically-created custom agent, fall back to chat
            result = await tryCustomAgent(agentName, userMessage, supabase, useLocal, settings)
                  || await runChatAgent(userMessage, imageBase64, chatHistory, longTermMemories, settings);
        }
        const tAgent = Date.now();

        let answer = result.answer || 'לא הצלחתי לגבש תשובה.';
        const action = result.action || null;

        // ── Parallel: save history + TTS ──────────────────────────────────────
        // Long-running agents (e.g. e2e in background) set skipTts to short-circuit
        // the response and avoid the client-side timeout.
        const ttsEnabled = settings.ttsEnabled !== false && !result.skipTts;
        const [,, audioBase64] = await Promise.all([
            saveChatMessage('user', userMessage, chatId),
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
        res.json({ answer, audio: audioBase64, action, chatId });

        // ── Fire-and-forget: passive memory extraction + summary update ────────
        if (agentName === 'chat' && !imageBase64) {
            setImmediate(() => {
                autoExtractMemory(userMessage, answer, supabase, settings).catch(() => {});
                // Reload fresh history (cache was just invalidated) for summary
                loadChatHistory(chatId).then(freshHistory => {
                    conversationSummary.updateSummaryIfNeeded(chatId, freshHistory, supabase, settings).catch(() => {});
                }).catch(() => {});
            });
        }

    } catch (err) {
        console.error('Route Error:', err.message);
        res.status(500).json({ answer: 'שגיאת מערכת פנימית.' });
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
        res.status(500).json({ ok: false, error: err.message });
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
        res.status(500).json({ error: err.message });
    }
});

// ─── User Profile (Learning) ───────────────────────────────────────────────
app.get('/user-profile', async (_req, res) => {
    try {
        const profile = await getUserProfile();
        res.json({ profile });
    } catch (err) {
        res.status(500).json({ error: err.message, profile: null });
    }
});

app.post('/user-profile', async (req, res) => {
    try {
        const {
            speaking_tone = 'friendly',
            preferred_hours = [],
            interests = [],
            recurring_tasks = [],
        } = req.body || {};

        const sanitizeList = (v, max = 20) => Array.isArray(v)
            ? v.map(x => String(x).trim()).filter(Boolean).slice(0, max)
            : [];

        const payload = {
            speaking_tone: String(speaking_tone || 'friendly').trim().slice(0, 40),
            preferred_hours: sanitizeList(preferred_hours, 8),
            interests: sanitizeList(interests, 20),
            recurring_tasks: sanitizeList(recurring_tasks, 20),
            updated_at: new Date().toISOString(),
        };

        const existing = await getUserProfile();
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
            return res.json({ success: true, profile: localProfile, fallback: true });
        }
        writeLocalProfile(result.data);
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
            return res.json({ success: true, deleted: true, fallback: true });
        }
        const { error } = await supabase.from('user_profiles').delete().eq('id', existing.id);
        if (error) {
            console.error('user_profiles delete error:', error.message);
            deleteLocalProfile();
            return res.json({ success: true, deleted: true, fallback: true });
        }
        deleteLocalProfile();
        res.json({ success: true, deleted: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─── Survey check (should user take survey?) ──────────────────────────────
app.get('/survey-check', async (req, res) => {
    try {
        const { sessionMinutes, agentCallCount, force } = req.query;
        const minutes = parseInt(sessionMinutes) || 0;
        const calls = parseInt(agentCallCount) || 0;
        const forced = force === 'true' || force === '1';

        // Trigger survey after 20+ minutes OR 3+ agent calls (or forced by user)
        const shouldShowSurvey = forced || minutes >= 20 || calls >= 3;

        if (shouldShowSurvey) {
            const questions = selectSurveyQuestions({ minutes, calls });
            const surveyJson = buildSurveyJson(questions);
            res.json({ showSurvey: true, questions: surveyJson });
        } else {
            res.json({ showSurvey: false });
        }
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

        // Build survey structure for summary
        const surveyQIds = Object.keys(responses);
        const survey = surveyQIds.map(id => ({
            id,
            question: SURVEY_QUESTIONS[id]?.question || id,
        }));

        // Get latest E2E test report for context
        let e2eContext = '';
        try {
            const { data: e2eData } = await supabase
                .from('e2e_reports')
                .select('score, critical, high, medium')
                .order('created_at', { ascending: false })
                .limit(1);

            if (e2eData && e2eData.length > 0) {
                const report = e2eData[0];
                e2eContext = `\n\n🧪 *דוח בדיקות אחרון:* Score ${report.score}, ` +
                    `${report.critical || 0} קריטיות, ${report.high || 0} גבוהות`;
            }
        } catch (_) {}

        // Generate AI summary
        let summary = await generateSurveySummary(survey, responses, userName);
        summary += e2eContext;

        // Save survey to DB
        const { error } = await supabase
            .from('user_surveys')
            .insert([{
                user_name: userName,
                responses: JSON.stringify(responses),
                summary,
                created_at: new Date().toISOString(),
            }]);

        if (error) throw error;

        // Invalidate aggregate insights cache so the next /survey-insights
        // request picks up this new submission.
        _surveyInsightsCache.delete(userName);

        res.json({ success: true, summary });
    } catch (err) {
        console.error('⚠️ /survey-submit error:', err.message);
        res.status(500).json({ error: err.message });
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
        res.status(500).json({ error: err.message });
    }
});

// ─── Survey aggregate insights (TTL cache, 1h) ────────────────────────────
// LRU-bounded: drops oldest entries beyond _SURVEY_INSIGHTS_CACHE_MAX
// to prevent unbounded memory growth across many users.
const _SURVEY_INSIGHTS_CACHE_MAX = 500;
const _surveyInsightsCache = new Map(); // userName -> { insights, generatedAt, ts }
app.get('/survey-insights', async (req, res) => {
    try {
        const { userName } = req.query;
        if (!userName) return res.status(400).json({ error: 'userName required' });

        const cached = _surveyInsightsCache.get(userName);
        if (cached && Date.now() - cached.ts < 60 * 60 * 1000) {
            // Refresh recency for LRU eviction order.
            _surveyInsightsCache.delete(userName);
            _surveyInsightsCache.set(userName, cached);
            return res.json({ insights: cached.insights, generatedAt: cached.generatedAt, cached: true });
        }

        const { data, error } = await supabase
            .from('user_surveys')
            .select('summary, created_at')
            .eq('user_name', userName)
            .order('created_at', { ascending: false })
            .limit(20);

        if (error) throw error;

        const summariesWithContent = (data || []).filter(s => (s.summary || '').trim().length > 0);
        if (summariesWithContent.length === 0) {
            return res.json({ insights: [], generatedAt: null });
        }

        const summariesText = summariesWithContent
            .map((s, i) => `[${i + 1}] (${s.created_at}) ${s.summary}`)
            .join('\n\n');

        let insights = [];
        try {
            const raw = await callGemma4([
                { role: 'system', content: 'אתה אנליסט מוצר. ענה תמיד ב-JSON בלבד.' },
                { role: 'user', content: `סקרים אחרונים של המשתמש "${userName}":\n${summariesText}\n\nסכם 3-5 תובנות מצטברות בעברית על המשתמש (העדפות, נקודות חוזק, אזורי שיפור). החזר JSON: {"insights":["...","..."]}` },
            ], false, 500);
            const match = raw.match(/\{[\s\S]*\}/);
            if (match) {
                const parsed = JSON.parse(match[0]);
                if (Array.isArray(parsed.insights)) insights = parsed.insights.filter(x => typeof x === 'string');
            }
        } catch (e) {
            console.error('⚠️ survey-insights LLM error:', e.message);
        }

        const generatedAt = new Date().toISOString();
        _surveyInsightsCache.set(userName, { insights, generatedAt, ts: Date.now() });
        while (_surveyInsightsCache.size > _SURVEY_INSIGHTS_CACHE_MAX) {
            const oldestKey = _surveyInsightsCache.keys().next().value;
            _surveyInsightsCache.delete(oldestKey);
        }
        res.json({ insights, generatedAt, cached: false });
    } catch (err) {
        console.error('⚠️ /survey-insights error:', err.message);
        res.status(500).json({ error: err.message });
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
    ]);

    const getCount = (result) => {
        if (result.status === 'fulfilled' && !result.value.error) return result.value.count ?? 0;
        return 0;
    };

    res.json({
        chat:      { total: getCount(chatTotal),      today:   getCount(chatToday) },
        tasks:     { total: getCount(tasksTotal),     done:    getCount(tasksDone),    pending: getCount(tasksTotal) - getCount(tasksDone) },
        reminders: { total: getCount(remindersTotal), active:  getCount(remindersActive) },
        memories:  { total: getCount(memoriesTotal) },
        notes:     { total: getCount(notesTotal) },
        shopping:  { total: getCount(shoppingTotal),  checked: getCount(shoppingChecked) },
    });
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

// ─── Contacts REST ────────────────────────────────────────────────────────────

app.get('/contacts', requirePolicy('contacts.read', { sensitive: true }), async (_req, res) => {
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
        res.status(500).json({ ok: false, error: err.message });
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
        res.status(500).json({ error: err.message });
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
        res.status(500).json({ error: err.message });
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
        res.status(500).json({ error: err.message });
    }
});

app.delete('/shopping/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('shopping_items').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /shopping:id error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
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
        res.status(500).json({ error: err.message });
    }
});

app.delete('/notes/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('notes').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /notes:id error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
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
        res.status(500).json({ reports: [], error: err.message });
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
        res.status(500).json({ findings: [], error: err.message });
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
        res.status(500).json({ ok: false, error: err.message });
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
        res.status(500).json({ error: err.message });
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
        res.status(500).json({ ok: false, error: err.message });
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
        res.status(500).json({ error: 'scan failed', message: err.message });
    }
});

// ─── PUT /reminders/:id — update text and/or scheduled_time ──────────────────
// ─── POST /contacts — add contact from app ───────────────────────────────────
app.post('/contacts', requirePolicy('contacts.create', { sensitive: true }), async (req, res) => {
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
        res.status(500).json({ error: err.message });
    }
});

// ─── PUT /contacts/:id — update contact ───────────────────────────────────────
app.put('/contacts/:id', requirePolicy('contacts.update', { sensitive: true }), async (req, res) => {
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
        res.status(500).json({ error: err.message });
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
        res.status(500).json({ error: err.message });
    }
});

// ─── Streaming endpoint (SSE) ─────────────────────────────────────────────────

const { callGemma4Stream, callGemma4 } = require('./agents/models');

async function streamJarvisHandler(req, res) {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    const send = (data) => { if (!res.destroyed) res.write(`data: ${JSON.stringify(data)}\n\n`); };

    const controller = new AbortController();
    req.on('close', () => controller.abort());

    try {
        const userMessage = req.body.command || '';
        const chatId = req.body.chatId || req.body.chat_id || `session-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const settings    = req.body.settings || {};
        const useLocal    = settings.useLocalModel === true;

        if (userMessage.length > 5000) {
            send({ error: 'ההודעה ארוכה מדי.', chatId });
            return res.end();
        }

        const agentName = await classifyIntent(userMessage);

        // Background agents: respond immediately and run in background via setImmediate
        const backgroundAgents = { e2e: runE2EAgent, code_error: runCodeErrorAgent, security: runSecurityAgent };
        if (backgroundAgents[agentName]) {
            const placeholder = agentName === 'e2e'
                ? '🧪 מתחיל בדיקות קצה ברקע — התוצאה תופיע בשיחה בעוד כמה דקות.'
                : agentName === 'code_error'
                    ? '🔍 סורק שגיאות קוד ברקע — התוצאה תופיע בשיחה בקרוב.'
                    : '🔒 סורק אבטחה ברקע — התוצאה תופיע בשיחה בקרוב.';
            send({ chunk: placeholder, done: true, chatId });
            await Promise.all([
                saveChatMessage('user', userMessage, chatId),
                saveChatMessage('jarvis', placeholder, chatId),
            ]);
            res.end();
            const bgChatId = chatId;
            setImmediate(async () => {
                try {
                    const r = await backgroundAgents[agentName](userMessage, supabase, useLocal, settings);
                    await saveChatMessage('jarvis', r.answer, bgChatId);
                    cacheInvalidate(`chatHistory:${bgChatId}`);
                } catch (err) {
                    await saveChatMessage('jarvis', `❌ ${err.message}`, bgChatId).catch(() => {});
                    cacheInvalidate(`chatHistory:${bgChatId}`);
                }
            });
            return;
        }

        // Only chat/draft agents support streaming — others fall back to regular
        if (!['chat', 'draft'].includes(agentName)) {
            let result;
            if (agentName === 'weather')   result = await runWeatherAgent(userMessage);
            else if (agentName === 'news') result = await runNewsAgent(userMessage);
            else if (agentName === 'stocks') result = await runStocksAgent(userMessage);
            else if (agentName === 'translate') result = await runTranslationAgent(userMessage, supabase, useLocal);
            else if (agentName === 'factory') result = await runAgentFactoryAgent(userMessage, supabase, useLocal, settings);
            else if (agentName === 'insight') result = await runInsightAgent(userMessage, supabase, useLocal, settings);
            else {
                const [chatHistory, longTermMemories] = await Promise.all([
                    loadChatHistory(chatId), fetchLongTermMemories()
                ]);
                result = await runChatAgent(userMessage, null, chatHistory, longTermMemories, settings);
            }
            const answer = result.answer || '';
            send({ chunk: answer, done: true, chatId });
            await Promise.all([
                saveChatMessage('user', userMessage, chatId),
                saveChatMessage('jarvis', answer, chatId),
            ]);
            return res.end();
        }

        // Chat streaming via Groq — same quality as /ask-jarvis
        const [chatHistory, longTermMemories, chatSummary] = await Promise.all([
            loadChatHistory(chatId),
            fetchLongTermMemories(userMessage),
            conversationSummary.getSummary(chatId, supabase),
        ]);

        settings.chatSummary = chatSummary;
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

        send({ done: true, chatId });

        await Promise.all([
            saveChatMessage('user', userMessage, chatId),
            saveChatMessage('jarvis', fullAnswer, chatId),
        ]);
        cacheInvalidate(`chatHistory:${chatId}`);

        // Update rolling summary + passive memory extraction (fire-and-forget)
        setImmediate(() => {
            autoExtractMemory(userMessage, fullAnswer, supabase, settings).catch(() => {});
            loadChatHistory(chatId).then(fresh => {
                conversationSummary.updateSummaryIfNeeded(chatId, fresh, supabase, settings).catch(() => {});
            }).catch(() => {});
        });
    } catch (err) {
        console.error('SSE error:', err.message);
        send({ error: 'שגיאת מערכת.' });
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

// ─── Proactive Notification Helpers ──────────────────────────────────────────

async function enqueueNotification(text) {
    await supabase.from('reminders').insert([{
        text,
        scheduled_time: new Date().toISOString(),
        fired: true,
    }]);
}

// Morning briefing — 7:00 AM Jerusalem
if (!isTestEnv) cron.schedule('0 7 * * *', async () => {
    try {
        const [{ data: tasks }, { data: todayReminders }] = await Promise.all([
            supabase.from('tasks').select('id'),
            supabase
                .from('reminders')
                .select('id')
                .eq('fired', false)
                .gte('scheduled_time', (() => { const d = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' })); d.setHours(0, 0, 0, 0); return d.toISOString(); })())
                .lt('scheduled_time',  (() => { const d = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' })); d.setHours(23, 59, 59, 999); return d.toISOString(); })()),
        ]);

        const dayName = new Date().toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });
        let text = `בוקר טוב! ${dayName} 🌅`;
        if (tasks?.length)          text += ` יש לך ${tasks.length} משימות פתוחות.`;
        if (todayReminders?.length) text += ` ${todayReminders.length} תזכורות להיום.`;

        await enqueueNotification(text);
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

// ─── Obsidian sync endpoints ──────────────────────────────────────────────────
let obsidianAutoSync = true;

app.post('/sync/obsidian', async (_req, res) => {
    try {
        const result = await obsidianSync.syncAll();
        res.json({ ok: true, ...result });
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

app.post('/sync/obsidian/auto', (req, res) => {
    obsidianAutoSync = req.body?.enabled !== false;
    console.log(`[ObsidianSync] auto-sync ${obsidianAutoSync ? 'enabled' : 'disabled'}`);
    res.json({ ok: true, autoSync: obsidianAutoSync });
});

app.get('/sync/obsidian/status', (_req, res) => {
    res.json({ autoSync: obsidianAutoSync, vaultReady: !!process.env.OBSIDIAN_VAULT_PATH });
});

// ─── Obsidian auto-sync cron (every 5 min) ────────────────────────────────────
if (!isTestEnv) cron.schedule('*/5 * * * *', () => {
    if (!obsidianAutoSync) return;
    obsidianSync.syncAll().catch(err => console.error('[ObsidianSync] cron:', err.message));
});

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

app.get('/chart.js', (_req, res) => {
    res.sendFile(path.join(__dirname, 'node_modules/chart.js/dist/chart.umd.min.js'),
        err => { if (err && !res.headersSent) res.status(404).send('Not found'); });
});

const { createAgentCenterRouter } = require('./routes/agentCenter');
app.use('/progress-map', createAgentCenterRouter({ callGemma4 }));
app.get('/agent-center', (_req, res) => res.redirect(301, '/progress-map'));

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

        // Extract JSON array — handle markdown code blocks and leading text
        const jsonMatch = raw.match(/\[[\s\S]*\]/);
        if (!jsonMatch) {
            console.error('backlog/generate: no JSON array found in LLM output:', raw.slice(0, 200));
            return res.status(500).json({ error: 'מודל ה-AI לא החזיר JSON תקין — נסה שוב' });
        }

        const parsed = JSON.parse(jsonMatch[0]);

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

// ─── Dashboard – Smart telemetry (MVP) ──────────────────────────────────────
app.post('/dashboard/smart-telemetry', async (req, res) => {
    try {
        const { userId, eventName, eventValue, metadata } = req.body || {};
        if (!userId || !String(userId).trim()) return res.status(400).json({ error: 'userId required' });
        if (!eventName || !String(eventName).trim()) return res.status(400).json({ error: 'eventName required' });

        const payload = {
            user_id: String(userId).trim(),
            event_name: String(eventName).trim(),
            event_value: Number.isFinite(Number(eventValue)) ? Number(eventValue) : 1,
            metadata: (metadata && typeof metadata === 'object') ? metadata : {},
        };

        const { error } = await supabase.from('smart_telemetry_events').insert(payload);
        if (error) return res.status(500).json({ error: error.message });
        res.json({ ok: true });
    } catch (e) {
        console.error('smart-telemetry POST error:', e.message);
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

app.get('/dashboard/smart-telemetry', async (req, res) => {
    try {
        const userId = String(req.query.userId || '').trim();
        if (!userId) return res.status(400).json({ error: 'userId required' });

        const { data, error } = await supabase
            .from('smart_telemetry_events')
            .select('event_name,event_value,created_at')
            .eq('user_id', userId)
            .order('created_at', { ascending: false })
            .limit(300);

        if (error) return res.status(500).json({ error: error.message });
        const counters = {};
        for (const row of (data || [])) {
            const key = row.event_name || 'unknown';
            counters[key] = (counters[key] || 0) + (Number(row.event_value) || 0);
        }
        res.json({ counters, events: data || [] });
    } catch (e) {
        console.error('smart-telemetry GET error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

app.delete('/dashboard/smart-telemetry/history', async (req, res) => {
    try {
        const userId = String(req.body?.userId || req.query.userId || '').trim();
        if (!userId) return res.status(400).json({ error: 'userId required' });
        const { error } = await supabase.from('smart_telemetry_events').delete().eq('user_id', userId);
        if (error) return res.status(500).json({ error: error.message });
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
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

module.exports = { app };

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
    const wss = new WebSocketServer({ server, path: '/ws-jarvis' });
    const wsHandler = createWsHandler({
        classifyIntent,
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
