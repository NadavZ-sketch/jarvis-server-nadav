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
const { runChatAgent, detectFollowUp, filterRelevantMemories } = require('./agents/chatAgent');
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

const helmet    = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
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
    allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key'],
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

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);
app.use('/tasks', createTasksRouter({ supabase }));
app.use('/reminders', createRemindersRouter({ supabase, pinecone }));
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

        // ── Fire-and-forget: passive memory extraction (zero latency impact) ─
        if (agentName === 'chat' && !imageBase64) {
            setImmediate(() => {
                autoExtractMemory(userMessage, answer, supabase, settings).catch(() => {});
            });
        }

    } catch (err) {
        console.error('Route Error:', err.message);
        res.status(500).json({ answer: 'שגיאת מערכת פנימית.' });
    }
}

// ─── Send Email (called after user confirms in Flutter) ───────────────────────

app.post('/send-email', async (req, res) => {
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
        const { sessionMinutes, agentCallCount } = req.query;
        const minutes = parseInt(sessionMinutes) || 0;
        const calls = parseInt(agentCallCount) || 0;

        // Trigger survey after 20+ minutes OR 3+ agent calls
        const shouldShowSurvey = minutes >= 20 || calls >= 3;

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

        res.json({ success: true, summary });
    } catch (err) {
        console.error('⚠️ /survey-submit error:', err.message);
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

// ─── Check Reminders (polled by Flutter) ──────────────────────────────────────

// ─── Contacts REST ────────────────────────────────────────────────────────────

app.get('/contacts', async (_req, res) => {
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

app.delete('/contacts/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('contacts').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /contacts/:id error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
    }
});

// ─── PUT /tasks/:id — update task (done, due_date, content) ──────────────────
app.put('/tasks/:id', async (req, res) => {
    try {
        const { done, due_date, content } = req.body;
        const updates = {};
        if (done      !== undefined) updates.done     = done;
        if (due_date  !== undefined) updates.due_date = due_date;
        if (content   !== undefined) updates.content  = content;
        if (Object.keys(updates).length === 0)
            return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await supabase
            .from('tasks').update(updates).eq('id', req.params.id).select().single();
        if (error) throw error;
        res.json({ task: data });
    } catch (err) {
        console.error('PUT /tasks/:id error:', err.message);
        res.status(500).json({ error: err.message });
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
app.post('/contacts', async (req, res) => {
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
app.put('/contacts/:id', async (req, res) => {
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

        // Only chat/draft agents support streaming — others fall back to regular
        if (!['chat', 'draft'].includes(agentName)) {
            let result;
            if (agentName === 'weather')   result = await runWeatherAgent(userMessage);
            else if (agentName === 'news') result = await runNewsAgent(userMessage);
            else if (agentName === 'stocks') result = await runStocksAgent(userMessage);
            else if (agentName === 'translate') result = await runTranslationAgent(userMessage, supabase, useLocal);
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

        // Chat streaming via Groq
        const [chatHistory, longTermMemories] = await Promise.all([
            loadChatHistory(chatId), fetchLongTermMemories()
        ]);

        const systemPrompt = `אתה ג'רביס, עוזר אישי חכם שמדבר עברית. ענה תמיד בעברית טבעית ויעילה.
זיכרונות ארוכי טווח:
${longTermMemories}`;

        const msgs = [
            { role: 'system', content: systemPrompt },
            ...chatHistory.map(m => ({ role: m.role === 'jarvis' ? 'assistant' : 'user', content: m.text })),
            { role: 'user', content: userMessage },
        ];

        let fullAnswer = '';
        await callGemma4Stream(msgs, useLocal, (chunk) => {
            fullAnswer += chunk;
            send({ chunk });
        }, controller.signal);

        send({ done: true, chatId });

        await Promise.all([
            saveChatMessage('user', userMessage, chatId),
            saveChatMessage('jarvis', fullAnswer, chatId),
        ]);
        cacheInvalidate(`chatHistory:${chatId}`);
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

cron.schedule('* * * * *', async () => {
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
cron.schedule('0 7 * * *', async () => {
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
cron.schedule('0 21 * * *', async () => {
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
cron.schedule('*/5 * * * *', () => {
    if (!obsidianAutoSync) return;
    obsidianSync.syncAll().catch(err => console.error('[ObsidianSync] cron:', err.message));
});

app.get('/chart.js', (_req, res) => {
    res.sendFile(path.join(__dirname, 'node_modules/chart.js/dist/chart.umd.min.js'),
        err => { if (err && !res.headersSent) res.status(404).send('Not found'); });
});

app.get('/progress-map', (_req, res) => {
    res.sendFile(path.join(__dirname, 'progress-map.html'),
        err => { if (err && !res.headersSent) res.status(404).send('Not found'); });
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
function readBacklog() {
    try {
        const data = JSON.parse(require('fs').readFileSync(BACKLOG_PATH(), 'utf8'));
        if (!data.items)     data.items     = [];
        if (!data.proposals) data.proposals = [];
        if (!data._nextId)   data._nextId   = (data.items.length > 0 ? Math.max(...data.items.map(i => i.id)) + 1 : 1);
        return data;
    } catch {
        return { items: [], proposals: [], _nextId: 1 };
    }
}
function writeBacklog(data) {
    require('fs').writeFileSync(BACKLOG_PATH(), JSON.stringify(data, null, 2));
}

app.get('/dashboard/features', (_req, res) => {
    try {
        const data = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'features.json'), 'utf8'));
        res.json(data);
    } catch { res.status(500).json({ error: 'features.json not found' }); }
});

app.get('/dashboard/backlog', (_req, res) => {
    res.json(readBacklog());
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
        item.status = (req.body?.status) || ({ proposal: 'active', active: 'done', done: 'proposal' }[item.status] || 'active');
        writeBacklog(data);
        res.json({ item });
    } catch (e) { res.status(500).json({ error: e.message }); }
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
        const proposals = parsed.slice(0, 6).map((p, i) => ({
            id: baseId + i,
            title:    ((p.title    || p['כותרת']   || p['כותרת:'] || '').toString()).slice(0, 80),
            plan:     ((p.plan     || p['תוכנית']  || p['תכנית']  || p['תיאור'] || '').toString()),
            priority: ['high', 'medium', 'low'].includes(p.priority || p['עדיפות'])
                ? (p.priority || p['עדיפות']) : 'medium',
            category: (p.category || p['קטגוריה'] || 'improvement').toString(),
            status: 'proposal',
            generated_at: new Date().toISOString().slice(0, 10),
        })).filter(p => p.title.trim() || p.plan.trim()); // drop truly empty items

        if (proposals.length === 0) {
            console.error('backlog/generate: all proposals had empty title+plan. Raw:', raw.slice(0, 300));
            return res.status(500).json({ error: 'לא הצלחתי לחלץ הצעות — נסה שוב' });
        }

        backlog.proposals      = proposals;
        backlog._lastGenerated = new Date().toISOString().slice(0, 10);
        writeBacklog(backlog);
        res.json({ proposals, generated_at: backlog._lastGenerated });
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

// ─── Start ────────────────────────────────────────────────────────────────────

module.exports = { app };

if (require.main === module) {
    const PORT = process.env.PORT || 3000;
    const server = app.listen(PORT, () => {
        console.log(`🚀 JARVIS ONLINE | MULTI-AGENT v3 | PORT: ${PORT}`);
        // Init Pinecone and sync existing memories in background (non-blocking)
        pinecone.ensureInit().then(() => pinecone.syncFromSupabase(supabase)).catch(() => {});
    });

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
