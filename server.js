require('dotenv').config();
const express    = require('express');
const cors       = require('cors');
const cron       = require('node-cron');
const nodemailer = require('nodemailer');
const fs         = require('fs');
const path       = require('path');
const { createClient } = require('@supabase/supabase-js');
const googleTTS  = require('google-tts-api');

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

const { classifyIntent }      = require('./agents/router');
const { runTaskAgent }        = require('./agents/taskAgent');
const { runReminderAgent }    = require('./agents/reminderAgent');
const { runMemoryAgent }      = require('./agents/memoryAgent');
const { runChatAgent, detectFollowUp } = require('./agents/chatAgent');
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

const helmet    = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.options('*', cors()); // explicit preflight handler for all routes
app.use(express.json({ limit: '10mb' }));
app.use('/ask-jarvis', rateLimit({ windowMs: 60_000, max: 30, standardHeaders: true, legacyHeaders: false }));

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);

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
}

// ─── Memories ─────────────────────────────────────────────────────────────────

async function fetchLongTermMemories() {
    const cached = cacheGet('memories');
    if (cached) return cached;

    const { data } = await supabase.from('memories').select('content');
    const result = (!data || data.length === 0)
        ? 'אין עדיין זיכרונות שמורים.'
        : data.map(m => `- ${m.content}`).join('\n');
    cacheSet('memories', result, TTL_MEMORIES);
    return result;
}

// ─── TTS ──────────────────────────────────────────────────────────────────────

async function generateSpeech(text) {
    try {
        const results = await googleTTS.getAllAudioBase64(text, {
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
    res.json({ ok: true, version: 'multi-agent-v3', ts: Date.now() });
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
        let agentName = imageBase64 ? 'chat' : await classifyIntent(userMessage);

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

        console.log(`🎯 Dispatching to: ${agentName} (+${Date.now() - t0}ms)`);
        const tRoute = Date.now();

        // ── Lazy DB load: only chat/draft need history + memories ─────────────
        const needsHistory = ['chat', 'draft'].includes(agentName);
        let chatHistory = [], longTermMemories = '';
        if (needsHistory) {
            [chatHistory, longTermMemories] = await Promise.all([
                loadChatHistory(),
                fetchLongTermMemories()
            ]);
        }
        const tDb = Date.now();

        // ── Dispatch ──────────────────────────────────────────────────────────
        let result;
        if (agentName === 'task') {
            result = await runTaskAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'reminder') {
            result = await runReminderAgent(userMessage, supabase);
        } else if (agentName === 'memory') {
            result = await runMemoryAgent(userMessage, supabase, useLocal, settings);
            cacheInvalidate('memories'); // memory changed — bust cache
        } else if (agentName === 'weather') {
            result = await runWeatherAgent(userMessage);
        } else if (agentName === 'news') {
            result = await runNewsAgent(userMessage);
        } else if (agentName === 'shopping') {
            result = await runShoppingAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'notes') {
            result = await runNotesAgent(userMessage, supabase, useLocal);
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
        const { text, scheduled_time } = req.body;
        if (!text || !scheduled_time) return res.status(400).json({ error: 'text and scheduled_time required' });
        const { data, error } = await supabase
            .from('reminders')
            .insert([{ text, scheduled_time, fired: false }])
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
            .eq('done', false)
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

// ─── Reminder Cron (every minute) ─────────────────────────────────────────────

cron.schedule('* * * * *', async () => {
    try {
        const now = new Date().toISOString();
        const { data: due, error } = await supabase
            .from('reminders')
            .select('id, text, scheduled_time')
            .eq('fired', false)
            .lte('scheduled_time', now);

        if (error) { console.error('⏰ Cron error:', error.message); return; }
        if (!due || due.length === 0) return;

        const ids = due.map(r => r.id);
        due.forEach(r => console.log(`🔔 REMINDER: ${r.text} [${r.scheduled_time}]`));
        await supabase.from('reminders').update({ fired: true }).in('id', ids);
    } catch (err) {
        console.error('⏰ Cron unexpected error:', err.message);
    }
});

// ─── Start ────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
const server = app.listen(PORT, () => {
    console.log(`🚀 JARVIS ONLINE | MULTI-AGENT v3 | PORT: ${PORT}`);
});

// ─── Graceful Shutdown ────────────────────────────────────────────────────────

function shutdown(signal) {
    console.log(`\n${signal} received — shutting down gracefully...`);
    server.close(() => {
        console.log('✅ HTTP server closed. Goodbye.');
        process.exit(0);
    });
    // Force-exit after 10s if requests are hanging
    setTimeout(() => { console.error('⚠️ Forced exit after timeout.'); process.exit(1); }, 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
