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
const { runChatAgent }        = require('./agents/chatAgent');
const { runSportsAgent }      = require('./agents/sportsAgent');
const { runMessagingAgent }   = require('./agents/messagingAgent');
const { runDraftAgent }       = require('./agents/draftAgent');
const { runSecurityAgent }    = require('./agents/securityAgent');
const { runAgentFactoryAgent} = require('./agents/agentFactoryAgent');

const helmet    = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use('/ask-jarvis', rateLimit({ windowMs: 60_000, max: 30, standardHeaders: true, legacyHeaders: false }));

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);

// ─── Chat History ─────────────────────────────────────────────────────────────

let chatMemoryFallback = [];

async function loadChatHistory() {
    try {
        const { data, error } = await supabase
            .from('chat_history')
            .select('role, text')
            .order('created_at', { ascending: false })
            .limit(10);

        if (error) throw error;
        return (data || []).reverse();
    } catch (err) {
        console.error('⚠️ loadChatHistory fallback:', err.message);
        return chatMemoryFallback.slice(-10);
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
    if (chatMemoryFallback.length > 10) chatMemoryFallback = chatMemoryFallback.slice(-10);
}

// ─── Memories ─────────────────────────────────────────────────────────────────

async function fetchLongTermMemories() {
    const { data } = await supabase.from('memories').select('content');
    if (!data || data.length === 0) return 'אין עדיין זיכרונות שמורים.';
    return data.map(m => `- ${m.content}`).join('\n');
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

// ─── Route ────────────────────────────────────────────────────────────────────

app.post('/ask-jarvis', async (req, res) => {
    try {
        const userMessage = req.body.command || '';
        const imageBase64 = req.body.image;

        if (userMessage.length > 5000) {
            return res.status(400).json({ answer: 'ההודעה ארוכה מדי. נסה בקצר יותר.' });
        }

        console.log(`\n--- Incoming: "${userMessage.slice(0, 60)}" | Image: ${!!imageBase64} ---`);
        const startTime = Date.now();

        const settings  = req.body.settings || {};
        const useLocal  = settings.useLocalModel === true;
        const agentName = imageBase64 ? 'chat' : await classifyIntent(userMessage);
        console.log(`🎯 Dispatching to: ${agentName}`);

        const [chatHistory, longTermMemories] = await Promise.all([
            loadChatHistory(),
            fetchLongTermMemories()
        ]);

        let result;
        if (agentName === 'task') {
            result = await runTaskAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'reminder') {
            result = await runReminderAgent(userMessage, supabase);
        } else if (agentName === 'memory') {
            result = await runMemoryAgent(userMessage, supabase, useLocal, settings);
        } else if (agentName === 'sports') {
            result = await runSportsAgent(userMessage);
        } else if (agentName === 'messaging') {
            result = await runMessagingAgent(userMessage, supabase, useLocal);
        } else if (agentName === 'draft') {
            result = await runDraftAgent(userMessage, chatHistory, longTermMemories, settings);
        } else if (agentName === 'security') {
            result = await runSecurityAgent(userMessage, useLocal, sendEmail);
        } else if (agentName === 'factory') {
            result = await runAgentFactoryAgent(userMessage, useLocal);
        } else {
            // Try a dynamically-created custom agent, fall back to chat
            result = await tryCustomAgent(agentName, userMessage, supabase, useLocal, settings)
                  || await runChatAgent(userMessage, imageBase64, chatHistory, longTermMemories, settings);
        }

        let answer = result.answer || 'לא הצלחתי לגבש תשובה.';
        console.log(`⏱️ ${(Date.now() - startTime) / 1000}s | Agent: ${agentName}`);

        const action = result.action || null;

        await Promise.all([
            saveChatMessage('user', userMessage),
            saveChatMessage('jarvis', answer)
        ]);

        const audioBase64 = await generateSpeech(answer);
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
app.listen(PORT, () => {
    console.log(`🚀 JARVIS ONLINE | MULTI-AGENT v3 | PORT: ${PORT}`);
});
