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
const { runAgentFactoryAgent} = require('./agents/agentFactoryAgent');
const { runInsightAgent }     = require('./agents/insightAgent');
const { runWeatherAgent }     = require('./agents/weatherAgent');
const { runNewsAgent }        = require('./agents/newsAgent');
const { runShoppingAgent }    = require('./agents/shoppingAgent');
const { runNotesAgent }       = require('./agents/notesAgent');
const { runStocksAgent }      = require('./agents/stocksAgent');
const { runTranslationAgent } = require('./agents/translationAgent');
const { runMusicAgent }       = require('./agents/musicAgent');
const obsidianSync            = require('./services/obsidianSync');
const pinecone                = require('./services/pineconeMemory');

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

async function loadChatHistory() {
    const cached = cacheGet('chatHistory');
    if (cached) return cached;

    try {
        const { data, error } = await supabase
            .from('chat_history')
            .select('role, text')
            .order('created_at', { ascending: false })
            .limit(20);

        if (error) throw error;
        const result = (data || []).reverse();
        cacheSet('chatHistory', result, TTL_CHAT_HISTORY);
        return result;
    } catch (err) {
        console.error('⚠️ loadChatHistory fallback:', err.message);
        return chatMemoryFallback.slice(-20);
    }
}

async function saveChatMessage(role, text) {
    try {
        const { error } = await supabase.from('chat_history').insert([{ role, text }]);
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

// ─── Route ────────────────────────────────────────────────────────────────────

app.post('/ask-jarvis', async (req, res) => {
    try {
        const userMessage = req.body.command || '';
        const imageBase64 = req.body.image;

        if (userMessage.length > 5000) {
            return res.status(400).json({ answer: 'ההודעה ארוכה מדי. נסה בקצר יותר.' });
        }

        console.log(`\n--- Incoming: "${userMessage.slice(0, 60)}" | Image: ${!!imageBase64} ---`);
        const t0 = Date.now();

        const settings  = req.body.settings || {};
        const useLocal  = settings.useLocalModel === true;

        // ── Routing ───────────────────────────────────────────────────────────
        let agentName = imageBase64 ? 'chat' : classifyIntent(userMessage);
        if (agentName === 'chat' && !imageBase64 && userMessage.trim().length > 12) {
            agentName = await classifyIntentWithLLM(userMessage);
        }

        // Follow-up override: if the user is continuing a previous conversation,
        // route to chat even if keywords matched a specialized agent
        const CONTEXT_OVERRIDE_AGENTS = ['sports', 'weather', 'news', 'task', 'insight', 'security', 'factory'];
        if (CONTEXT_OVERRIDE_AGENTS.includes(agentName)) {
            const tempHistory = await loadChatHistory(); // uses TTL cache — cheap
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
                loadChatHistory(),
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
        const ttsEnabled = settings.ttsEnabled !== false;
        const [,, audioBase64] = await Promise.all([
            saveChatMessage('user', userMessage),
            saveChatMessage('jarvis', answer),
            ttsEnabled ? generateSpeech(answer) : Promise.resolve(null),
        ]);
        cacheInvalidate('chatHistory'); // history just updated
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
        res.json({ answer, audio: audioBase64, action });

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
});

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

// ─── Chat History (read-only for Flutter UI) ──────────────────────────────────

app.get('/chat-history', async (req, res) => {
    try {
        const limit = Math.min(parseInt(req.query.limit) || 60, 200);
        const { data, error } = await supabase
            .from('chat_history')
            .select('role, text, created_at')
            .order('created_at', { ascending: false })
            .limit(limit);
        if (error) throw error;
        res.json({ messages: (data || []).reverse() });
    } catch (err) {
        console.error('⚠️ /chat-history error:', err.message);
        res.status(500).json({ messages: [] });
    }
});

// ─── Live DB Stats ────────────────────────────────────────────────────────────

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
        supabase.from('long_term_memory').select('id', { count: 'exact', head: true }),
        supabase.from('notes').select('id', { count: 'exact', head: true }),
        supabase.from('shopping').select('id', { count: 'exact', head: true }),
        supabase.from('shopping').select('id', { count: 'exact', head: true }).eq('checked', true),
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

app.get('/check-reminders', async (_req, res) => {
    try {
        // Fetch fired reminders, then delete them so they only notify once
        const { data, error } = await supabase
            .from('reminders')
            .select('id, text')
            .eq('fired', true);

        if (error) throw error;

        if (data && data.length > 0) {
            const ids = data.map(r => r.id);
            await supabase.from('reminders').delete().in('id', ids);
        }

        res.json({ reminders: data || [] });
    } catch (err) {
        console.error('check-reminders error:', err.message);
        res.json({ reminders: [] });
    }
});

// ─── Tasks REST ───────────────────────────────────────────────────────────────

app.get('/tasks', async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('tasks')
            .select('*')
            .order('created_at', { ascending: false });
        if (error) throw error;
        res.json({ tasks: data || [] });
    } catch (err) {
        console.error('GET /tasks error:', err.message);
        res.status(500).json({ tasks: [] });
    }
});

app.delete('/tasks/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('tasks').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /tasks/:id error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
    }
});

// ─── Reminders REST ───────────────────────────────────────────────────────────

app.get('/reminders', async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('reminders')
            .select('id, text, scheduled_time, fired')
            .eq('fired', false)
            .order('scheduled_time', { ascending: true });
        if (error) throw error;
        res.json({ reminders: data || [] });
    } catch (err) {
        console.error('GET /reminders error:', err.message);
        res.status(500).json({ reminders: [] });
    }
});

app.delete('/reminders/:id', async (req, res) => {
    try {
        const { error } = await supabase.from('reminders').delete().eq('id', req.params.id);
        if (error) throw error;
        res.json({ ok: true });
    } catch (err) {
        console.error('DELETE /reminders/:id error:', err.message);
        res.status(500).json({ ok: false, error: err.message });
    }
});

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

// ─── POST /reminders — add reminder from app ──────────────────────────────────
app.post('/reminders', async (req, res) => {
    try {
        const { text, scheduled_time, recurrence } = req.body;
        if (!text || !scheduled_time) return res.status(400).json({ error: 'text and scheduled_time required' });
        const row = { text, scheduled_time, fired: false };
        if (recurrence && ['daily', 'weekly', 'monthly'].includes(recurrence)) row.recurrence = recurrence;
        const { data, error } = await supabase
            .from('reminders')
            .insert([row])
            .select().single();
        if (error) throw error;
        res.json({ reminder: data });
    } catch (err) {
        console.error('POST /reminders error:', err.message);
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

// ─── PUT /reminders/:id — update text and/or scheduled_time ──────────────────
app.put('/reminders/:id', async (req, res) => {
    try {
        const { text, scheduled_time } = req.body;
        const updates = {};
        if (text           !== undefined) updates.text           = text;
        if (scheduled_time !== undefined) updates.scheduled_time = scheduled_time;
        if (Object.keys(updates).length === 0)
            return res.status(400).json({ error: 'no fields to update' });
        const { data, error } = await supabase
            .from('reminders').update(updates).eq('id', req.params.id).select().single();
        if (error) throw error;
        res.json({ reminder: data });
    } catch (err) {
        console.error('PUT /reminders/:id error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

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

app.post('/stream-jarvis', async (req, res) => {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    const send = (data) => { if (!res.destroyed) res.write(`data: ${JSON.stringify(data)}\n\n`); };

    const controller = new AbortController();
    req.on('close', () => controller.abort());

    try {
        const userMessage = req.body.command || '';
        const settings    = req.body.settings || {};
        const useLocal    = settings.useLocalModel === true;

        if (userMessage.length > 5000) {
            send({ error: 'ההודעה ארוכה מדי.' });
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
                    loadChatHistory(), fetchLongTermMemories()
                ]);
                result = await runChatAgent(userMessage, null, chatHistory, longTermMemories, settings);
            }
            const answer = result.answer || '';
            send({ chunk: answer, done: true });
            await Promise.all([
                saveChatMessage('user', userMessage),
                saveChatMessage('jarvis', answer),
            ]);
            return res.end();
        }

        // Chat streaming via Groq
        const [chatHistory, longTermMemories] = await Promise.all([
            loadChatHistory(), fetchLongTermMemories()
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

        send({ done: true });

        await Promise.all([
            saveChatMessage('user', userMessage),
            saveChatMessage('jarvis', fullAnswer),
        ]);
        cacheInvalidate('chatHistory');
    } catch (err) {
        console.error('SSE error:', err.message);
        send({ error: 'שגיאת מערכת.' });
    } finally {
        res.end();
    }
});

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
                .gte('scheduled_time', new Date(new Date().setHours(0, 0, 0, 0)).toISOString())
                .lt('scheduled_time',  new Date(new Date().setHours(23, 59, 59, 999)).toISOString()),
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
            supabase.from('tasks').select('id, content, due_date, done').not('due_date', 'is', null),
            supabase.from('reminders').select('id, text, scheduled_time, fired'),
        ]);
        const tasks = (tasksRes.data || []).map(t => ({
            id:    `task-${t.id}`,
            type:  'task',
            title: t.content,
            date:  t.due_date,
            done:  t.done,
        }));
        const reminders = (remindersRes.data || []).map(r => ({
            id:    `reminder-${r.id}`,
            type:  'reminder',
            title: r.text,
            date:  r.scheduled_time,
            done:  r.fired,
        }));
        res.json({ events: [...tasks, ...reminders] });
    } catch (err) {
        console.error('GET /calendar-events error:', err.message);
        res.status(500).json({ events: [] });
    }
});

// ─── Dashboard ────────────────────────────────────────────────────────────────
app.get('/dashboard/features', (_req, res) => {
    try {
        const data = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'features.json'), 'utf8'));
        res.json(data);
    } catch { res.status(500).json({ error: 'features.json not found' }); }
});

app.get('/dashboard/backlog', (_req, res) => {
    try {
        const data = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'backlog.json'), 'utf8'));
        res.json(data);
    } catch { res.json({ items: [], _nextId: 1 }); }
});

app.post('/dashboard/backlog', (req, res) => {
    try {
        const { text } = req.body;
        if (!text || !text.trim()) return res.status(400).json({ error: 'text required' });
        const fp   = path.join(__dirname, 'backlog.json');
        const data = JSON.parse(require('fs').readFileSync(fp, 'utf8'));
        const item = { id: data._nextId, text: text.trim(), done: false, added: new Date().toISOString().slice(0, 10) };
        data.items.unshift(item);
        data._nextId++;
        require('fs').writeFileSync(fp, JSON.stringify(data, null, 2));
        res.json({ item });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.patch('/dashboard/backlog/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const fp   = path.join(__dirname, 'backlog.json');
        const data = JSON.parse(require('fs').readFileSync(fp, 'utf8'));
        const item = data.items.find(i => i.id === id);
        if (!item) return res.status(404).json({ error: 'not found' });
        item.done = !item.done;
        require('fs').writeFileSync(fp, JSON.stringify(data, null, 2));
        res.json({ item });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/dashboard/backlog/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const fp   = path.join(__dirname, 'backlog.json');
        const data = JSON.parse(require('fs').readFileSync(fp, 'utf8'));
        data.items = data.items.filter(i => i.id !== id);
        require('fs').writeFileSync(fp, JSON.stringify(data, null, 2));
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// ─── Dashboard – AI backlog generation ───────────────────────────────────────
app.post('/dashboard/backlog/generate', async (_req, res) => {
    try {
        const fp       = path.join(__dirname, 'backlog.json');
        const features = JSON.parse(require('fs').readFileSync(path.join(__dirname, 'features.json'), 'utf8'));
        const backlog  = JSON.parse(require('fs').readFileSync(fp, 'utf8'));

        const done     = features.features?.done     || [];
        const building = features.features?.building || [];
        const planned  = features.features?.planned  || [];

        const prompt = `אתה מנהל פרויקט בכיר לפרויקט Jarvis — עוזר אישי AI מבוסס Flutter + Node.js עם 17+ אייג'נטים.

מצב נוכחי של הפרויקט:
✅ הושלם (${done.length}): ${done.map(f => f.name).join(', ')}
🔨 בבנייה (${building.length}): ${building.map(f => `${f.name} — ${f.desc}`).join(', ')}
📋 מתוכנן (${planned.length}): ${planned.map(f => `${f.name} — ${f.desc}`).join(', ')}

הצע 6 פריטי backlog אסטרטגיים ממוינים לפי דחיפות. לכל פריט:
- title: כותרת קצרה ומדויקת (עד 60 תווים)
- plan: תוכנית מפורטת (3-4 משפטים: מה לעשות, למה זה חשוב, איך לבצע טכנית)
- priority: high / medium / low
- category: feature / improvement / bug / ux

ענה בפורמט JSON בלבד, ללא טקסט נוסף:
[{"title":"...","plan":"...","priority":"high","category":"improvement"},...]`;

        const raw = await callGemma4(prompt, false);
        const jsonMatch = raw.match(/\[[\s\S]*\]/);
        if (!jsonMatch) return res.status(500).json({ error: 'LLM did not return valid JSON' });

        const parsed = JSON.parse(jsonMatch[0]);
        const proposals = parsed.slice(0, 6).map((p, i) => ({
            id: Date.now() + i,
            title: (p.title || '').slice(0, 80),
            plan: p.plan || '',
            priority: ['high', 'medium', 'low'].includes(p.priority) ? p.priority : 'medium',
            category: p.category || 'improvement',
            status: 'proposal',
            generated_at: new Date().toISOString().slice(0, 10),
        }));

        if (!backlog.proposals) backlog.proposals = [];
        backlog.proposals = proposals;
        backlog._lastGenerated = new Date().toISOString().slice(0, 10);
        require('fs').writeFileSync(fp, JSON.stringify(backlog, null, 2));
        res.json({ proposals, generated_at: backlog._lastGenerated });
    } catch (e) {
        console.error('backlog/generate error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

app.patch('/dashboard/backlog/proposals/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const fp   = path.join(__dirname, 'backlog.json');
        const data = JSON.parse(require('fs').readFileSync(fp, 'utf8'));
        if (!data.proposals) data.proposals = [];
        const item = data.proposals.find(p => p.id === id);
        if (!item) return res.status(404).json({ error: 'not found' });
        if (req.body && req.body.status) {
            item.status = req.body.status;
        } else {
            const cycle = { proposal: 'active', active: 'done', done: 'proposal' };
            item.status = cycle[item.status] || 'active';
        }
        require('fs').writeFileSync(fp, JSON.stringify(data, null, 2));
        res.json({ item });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/dashboard/backlog/proposals/:id', (req, res) => {
    try {
        const id   = parseInt(req.params.id, 10);
        const fp   = path.join(__dirname, 'backlog.json');
        const data = JSON.parse(require('fs').readFileSync(fp, 'utf8'));
        if (!data.proposals) data.proposals = [];
        data.proposals = data.proposals.filter(p => p.id !== id);
        require('fs').writeFileSync(fp, JSON.stringify(data, null, 2));
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
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
