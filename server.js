require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');
const googleTTS = require('google-tts-api');

const { classifyIntent } = require('./agents/router');
const { runTaskAgent }   = require('./agents/taskAgent');
const { runMemoryAgent } = require('./agents/memoryAgent');
const { runChatAgent }   = require('./agents/chatAgent');
const { runSportsAgent } = require('./agents/sportsAgent');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);

let chatMemory = [];

async function fetchLongTermMemories() {
    const { data } = await supabase.from('memories').select('content');
    if (!data || data.length === 0) return 'אין עדיין זיכרונות שמורים.';
    return data.map(m => `- ${m.content}`).join('\n');
}

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
        console.error('❌ Google TTS Error:', err.message);
        return null;
    }
}

app.post('/ask-jarvis', async (req, res) => {
    try {
        const userMessage = req.body.command || '';
        const imageBase64 = req.body.image;

        console.log(`\n--- Incoming: "${userMessage.slice(0, 60)}" | Image: ${!!imageBase64} ---`);
        const startTime = Date.now();

        // Images always go to chatAgent — skip router
        const agentName = imageBase64 ? 'chat' : await classifyIntent(userMessage);
        console.log(`🎯 Dispatching to: ${agentName}`);

        const longTermMemories = await fetchLongTermMemories();

        let result;
        if (agentName === 'task') {
            result = await runTaskAgent(userMessage, supabase);
        } else if (agentName === 'memory') {
            result = await runMemoryAgent(userMessage, supabase);
        } else if (agentName === 'sports') {
            result = await runSportsAgent(userMessage);
        } else {
            result = await runChatAgent(userMessage, imageBase64, chatMemory, longTermMemories);
        }

        const answer = result.answer || 'לא הצלחתי לגבש תשובה.';

        console.log(`⏱️ ${(Date.now() - startTime) / 1000}s | Agent: ${agentName}`);

        chatMemory.push({ role: 'user', text: userMessage });
        chatMemory.push({ role: 'jarvis', text: answer });
        if (chatMemory.length > 10) chatMemory = chatMemory.slice(chatMemory.length - 10);

        const audioBase64 = await generateSpeech(answer);
        res.json({ answer, audio: audioBase64 });

    } catch (err) {
        console.error('Route Error:', err.message);
        res.status(500).json({ answer: 'שגיאת מערכת פנימית.' });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 JARVIS ONLINE | MULTI-AGENT v2 | PORT: ${PORT}`);
});
