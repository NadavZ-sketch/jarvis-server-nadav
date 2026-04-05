const express = require('express');
const cors = require('cors');
const Anthropic = require('@anthropic-ai/sdk');
const OpenAI = require('openai');
const Groq = require('groq-sdk');
require('dotenv').config();

const { detectIntent, INTENTS } = require('./src/engines/intentEngine');
const { buildSystemPrompt } = require('./src/engines/personalityEngine');
const tasksRouter = require('./src/routes/tasks');
const { addToHistory, getRecentHistory, getFullMemory } = require('./src/memory/memoryManager');

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
    const { message } = req.body;

    // זיהוי כוונה
    const intentResult = detectIntent(message);

    // טעינת היסטוריה
    const recentHistory = getRecentHistory(10);
    const historyMessages = recentHistory.map(h => ({
      role: h.role,
      content: h.content,
    }));

    // בניית הודעות
    const messages = [
      ...historyMessages,
      { role: 'user', content: message },
    ];

    // System prompt חכם
    const systemPrompt = buildSystemPrompt(intentResult.intent, 'default');

    // קריאה ל-LLM
    const reply = await callLLM(messages, systemPrompt);

    // שמירה בזיכרון
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

// נקודת קצה - סטטוס
app.get('/status', (req, res) => {
  res.json({
    status: 'online',
    provider: process.env.LLM_PROVIDER || 'groq',
    version: '1.0.0',
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
  const { saveMemory } = require('./src/memory/memoryManager');
  saveMemory(memory);
  res.json({ success: true, settings: memory.settings });
});

// נקודת קצה - זיכרון
app.get('/memory', (req, res) => {
  const memory = getFullMemory();
  res.json({
    success: true,
    memory: memory,
  });
});

// הפעלת השרת
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`✅ MyAssistant Server running on http://localhost:${PORT}`);
  console.log(`🤖 LLM Provider: ${process.env.LLM_PROVIDER || 'groq'}`);
  console.log(`🧠 Intent Engine: active`);
  console.log(`💾 Memory Manager: active`);
});