require('dotenv').config();
const express = require('express');
const cors = require('cors');
const cron = require('node-cron');
const { createClient } = require('@supabase/supabase-js');
const googleTTS = require('google-tts-api');

const { classifyIntent }   = require('./agents/router');
const { runTaskAgent }     = require('./agents/taskAgent');
const { runReminderAgent } = require('./agents/reminderAgent');
const { runMemoryAgent }   = require('./agents/memoryAgent');
const { runChatAgent }     = require('./agents/chatAgent');
const { runSportsAgent }     = require('./agents/sportsAgent');
const { runMessagingAgent }  = require('./agents/messagingAgent');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

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

// ─── Route ────────────────────────────────────────────────────────────────────

app.post('/ask-jarvis', async (req, res) => {
    try {
        const userMessage = req.body.command || '';
        const imageBase64 = req.body.image;

        console.log(`\n--- Incoming: "${userMessage.slice(0, 60)}" | Image: ${!!imageBase64} ---`);
        const startTime = Date.now();

        const settings  = req.body.settings || {};
        const agentName = imageBase64 ? 'chat' : await classifyIntent(userMessage);
        console.log(`🎯 Dispatching to: ${agentName}`);

        const [chatHistory, longTermMemories] = await Promise.all([
            loadChatHistory(),
            fetchLongTermMemories()
        ]);

        let result;
        if (agentName === 'task') {
            result = await runTaskAgent(userMessage, supabase);
        } else if (agentName === 'reminder') {
            result = await runReminderAgent(userMessage, supabase);
        } else if (agentName === 'memory') {
            result = await runMemoryAgent(userMessage, supabase);
        } else if (agentName === 'sports') {
            result = await runSportsAgent(userMessage);
        } else if (agentName === 'messaging') {
            result = await runMessagingAgent(userMessage, supabase);
        } else {
            result = await runChatAgent(userMessage, imageBase64, chatHistory, longTermMemories, settings);
        }

        const answer = result.answer || 'לא הצלחתי לגבש תשובה.';
        console.log(`⏱️ ${(Date.now() - startTime) / 1000}s | Agent: ${agentName}`);

        await Promise.all([
            saveChatMessage('user', userMessage),
            saveChatMessage('jarvis', answer)
        ]);

        const audioBase64 = await generateSpeech(answer);
        res.json({ answer, audio: audioBase64, action: result.action || null });

    } catch (err) {
        console.error('Route Error:', err.message);
        res.status(500).json({ answer: 'שגיאת מערכת פנימית.' });
    }
});

// ─── Check Reminders (polled by Flutter) ──────────────────────────────────────

app.get('/check-reminders', async (_req, res) => {
    try {
        const { data, error } = await supabase
            .from('reminders')
            .select('id, text')
            .eq('fired', true)
            .eq('notified', false);

        if (error) throw error;

        if (data && data.length > 0) {
            const ids = data.map(r => r.id);
            await supabase.from('reminders').update({ notified: true }).in('id', ids);
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

        for (const reminder of due) {
            console.log(`🔔 REMINDER: ${reminder.text} [${reminder.scheduled_time}]`);
            await supabase.from('reminders').update({ fired: true }).eq('id', reminder.id);
        }
    } catch (err) {
        console.error('⏰ Cron unexpected error:', err.message);
    }
});

// ─── Start ────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 JARVIS ONLINE | MULTI-AGENT v3 | PORT: ${PORT}`);
});
