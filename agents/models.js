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
const HF_URL       = 'https://router.huggingface.co/hf-inference/v1/chat/completions';
const HF_MODEL     = 'google/gemma-4-27b-it';

async function callGemma4(messages) {
    // messages: array of { role, content } OR a plain string (converted below)
    const msgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    if (OLLAMA_URL) {
        // ── Local Ollama ──
        const response = await axios.post(`${OLLAMA_URL}/v1/chat/completions`, {
            model: OLLAMA_MODEL,
            messages: msgs,
            stream: false
        });
        return response.data.choices[0].message.content.trim();
    }

    // ── Cloud: HuggingFace (separate quota from Google) ──
    const response = await axios.post(HF_URL, {
        model: HF_MODEL,
        messages: msgs,
        max_tokens: 1024,
        stream: false
    }, {
        headers: {
            'Authorization': `Bearer ${process.env.HF_TOKEN}`,
            'Content-Type': 'application/json'
        }
    });
    return response.data.choices[0].message.content.trim();
}

module.exports = { GEMINI_URL, callGemma4 };
