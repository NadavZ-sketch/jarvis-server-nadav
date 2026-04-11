require('dotenv').config();
const axios = require('axios');

// ─── Gemini (Google) — for live search agents (chat, sports) ───────────────
const GEMINI_MODEL = 'gemini-2.5-flash-lite';
const GOOGLE_KEY = process.env.GOOGLE_API_KEY;
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';
const GEMINI_URL = `${GEMINI_BASE}/${GEMINI_MODEL}:generateContent?key=${GOOGLE_KEY}`;

// ─── Gemma 4 — Local (Ollama) or Cloud (HuggingFace) ──────────────────────
// Set OLLAMA_URL in .env to use local Ollama (e.g. http://localhost:11434)
// If not set, falls back to HuggingFace API (needs HF_TOKEN)
const OLLAMA_URL   = process.env.OLLAMA_URL;
const OLLAMA_MODEL = 'gemma4:e4b';
async function callGemma4(messages) {
    const prompt = typeof messages === 'string'
        ? messages
        : messages.map(m => m.content).join('\n');

    if (OLLAMA_URL) {
        // ── Local: Ollama (Gemma 4 on your machine) ──
        const msgs = typeof messages === 'string'
            ? [{ role: 'user', content: messages }]
            : messages;
        const response = await axios.post(`${OLLAMA_URL}/v1/chat/completions`, {
            model: OLLAMA_MODEL,
            messages: msgs,
            stream: false
        });
        return response.data.choices[0].message.content.trim();
    }

    // ── Cloud: Gemini (reminder is now pure JS so quota usage is low) ──
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }]
    });
    return response.data.candidates[0].content.parts[0].text.trim();
}

module.exports = { GEMINI_URL, callGemma4 };
