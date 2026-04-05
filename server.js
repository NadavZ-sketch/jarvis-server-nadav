const express = require('express');
const cors = require('cors');
const Anthropic = require('@anthropic-ai/sdk');
const OpenAI = require('openai');
const Groq = require('groq-sdk');
require('dotenv').config();

const { detectIntent, INTENTS } = require('./src/engines/intentEngine');
const { buildSystemPrompt } = require('./src/engines/personalityEngine');
const tasksRouter = require('./src/routes/tasks');
const { addToHistory, getRecentHistory, getFullMemory, saveMemory } = require('./src/memory/memoryManager');

const app = express();
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
}));
app.use(express.json());
app.use(express.static('.'));
app.use('/app', express.static('./my_assistant_app/build/web'));
app.use('/tasks', tasksRouter);

// LLM Adapter
const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });

async function callLLM(messages, systemPrompt = '') {
  const provider = process.env.LLM_PROVIDER || 'groq';

  if (provider === 'anthropic') {
    const response = await anthropic.messages.create({
      model: 'claude-opus-4-5',
      max_tokens: 1024,
      system: systemPrompt,
      messages: messages,
    });
    return response.content[0].text;

  } else if (provider === 'openai') {
    const allMessages = systemPrompt
      ? [{ role: 'system', content: systemPrompt }, ...messages]
      : messages;
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      max_tokens: 1024,
      messages: allMessages,
    });
    return response.choices[0].message.content;

  } else {
    const allMessages = systemPrompt
      ? [{ role: 'system', content: systemPrompt }, ...messages]
      : messages;
    const response = await groq.chat.completions.create({
      model: 'llama-3.3-70b-versatile',
      max_tokens: 1024,
      messages: allMessages,
    });
    return response.choices[0].message.content;
  }
}

// נקודת קצה - Chat
app.post('/chat', async (req, res) => {
  try {
    const { message, language = 'he' } = req.body;

    const intentResult = detectIntent(message);

    const recentHistory = getRecentHistory(10);
    const historyMessages = recentHistory.map(h => ({
      role: h.role,
      content: h.content,
    }));

    const messages = [
      ...historyMessages,
      { role: 'user', content: message },
    ];

    const langInstruction = language === 'en'
      ? 'Always respond in English.'
      : 'תמיד ענה בעברית.';

    const systemPrompt = buildSystemPrompt(intentResult.intent, 'default') + '\n' + langInstruction;

    const reply = await callLLM(messages, systemPrompt);

    addToHistory('user', message);
    addToHistory('assistant', reply);

    res.json({
      success: true,
      reply: reply,
      intent: intentResult.intent,
      provider: process.env.LLM_PROVIDER || 'groq',
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// נקודת קצה - TTS
app.post('/tts', async (req, res) => {
  try {
    const { text, language = 'he' } = req.body;

    const voiceId = language === 'en'
      ? 'EXAVITQu4vr4xnSDxMaL'
      : 'XrExE9yKIg1WjnnlVkGX';

    const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
      method: 'POST',
      headers: {
        'xi-api-key': process.env.ELEVENLABS_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        text: text,
        model_id: 'eleven_multilingual_v2',
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
        },
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      return res.status(500).json({ success: false, error });
    }

    res.setHeader('Content-Type', 'audio/mpeg');
    const buffer = await response.arrayBuffer();
    res.send(Buffer.from(buffer));

  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// נקודת קצה - סטטוס
app.get('/status', (req, res) => {
  res.json({
    status: 'online',
    provider: process.env.LLM_PROVIDER || 'groq',
    version: '1.0.0',
  });
});

// נקודת קצה - זיכרון
app.get('/memory', (req, res) => {
  const memory = getFullMemory();
  res.json({
    success: true,
    memory: memory,
  });
});

// נקודת קצה - קבלת הגדרות
app.get('/settings', (req, res) => {
  const memory = getFullMemory();
  res.json({
    success: true,
    settings: memory.settings || {
      provider: process.env.LLM_PROVIDER || 'groq',
      personality: 'default',
      assistantName: 'MyAssistant',
      language: 'he',
    },
  });
});

// נקודת קצה - שמירת הגדרות
app.post('/settings', (req, res) => {
  const { provider, personality, assistantName, language } = req.body;
  const memory = getFullMemory();
  memory.settings = { provider, personality, assistantName, language };
  saveMemory(memory);
  res.json({ success: true, settings: memory.settings });
});

// הפעלת השרת
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ MyAssistant Server running on http://localhost:${PORT}`);
  console.log(`🤖 LLM Provider: ${process.env.LLM_PROVIDER || 'groq'}`);
  console.log(`🧠 Intent Engine: active`);
  console.log(`💾 Memory Manager: active`);
});