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
// ─── Gemma 4 via HuggingFace ──────────────────────────────────────────────
const HF_URL   = 'https://router.huggingface.co/hf-inference/v1/chat/completions';
const HF_MODEL = 'google/gemma-4-27b-it';

// Local Ollama override (optional — set OLLAMA_URL in .env to use local model)
const OLLAMA_URL   = process.env.OLLAMA_URL;
const OLLAMA_MODEL = 'gemma4:e4b';

async function callGemma4(messages) {
    const msgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    // ── 1. Local Ollama (if running locally) ──
    if (OLLAMA_URL) {
        const response = await axios.post(`${OLLAMA_URL}/v1/chat/completions`, {
            model: OLLAMA_MODEL, messages: msgs, stream: false
        });
        return response.data.choices[0].message.content.trim();
    }

    // ── 2. HuggingFace Gemma 4 (cloud, separate quota from Google) ──
    try {
        const response = await axios.post(HF_URL, {
            model: HF_MODEL, messages: msgs, max_tokens: 800, stream: false
        }, {
            headers: {
                'Authorization': `Bearer ${process.env.HF_TOKEN}`,
                'Content-Type': 'application/json'
            }
        });
        return response.data.choices[0].message.content.trim();
    } catch (hfErr) {
        console.warn('⚠️ HuggingFace failed, falling back to Gemini:', hfErr.message);
        // ── 3. Gemini fallback ──
        const prompt = msgs.map(m => m.content).join('\n');
        const response = await axios.post(GEMINI_URL, {
            contents: [{ parts: [{ text: prompt }] }]
        });
        return response.data.candidates[0].content.parts[0].text.trim();
    }
}

module.exports = { GEMINI_URL, callGemma4 };
