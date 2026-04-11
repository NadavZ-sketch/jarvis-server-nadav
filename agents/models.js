require('dotenv').config();
const axios = require('axios');

// ─── Gemini (Google) — for live search agents (chat, sports) ───────────────
const GEMINI_MODEL = 'gemini-2.5-flash-lite';
const GOOGLE_KEY = process.env.GOOGLE_API_KEY;
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';
const GEMINI_URL = `${GEMINI_BASE}/${GEMINI_MODEL}:generateContent?key=${GOOGLE_KEY}`;

// ─── Groq — primary cloud (free, fast, OpenAI-compatible) ─────────────────
const GROQ_URL   = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_MODEL = 'llama-3.3-70b-versatile';

// ─── DeepSeek — fallback (OpenAI-compatible) ───────────────────────────────
const DEEPSEEK_URL   = 'https://api.deepseek.com/chat/completions';
const DEEPSEEK_MODEL = 'deepseek-chat';

// Local Ollama override (optional — set OLLAMA_URL in .env to use local model)
const OLLAMA_URL   = process.env.OLLAMA_URL;
const OLLAMA_MODEL = 'gemma4:e4b';

async function callGemma4(messages, useLocal = true) {
    const msgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    // ── 1. Local Ollama (only if useLocal is enabled AND OLLAMA_URL is set) ──
    if (useLocal && OLLAMA_URL) {
        try {
            const response = await axios.post(`${OLLAMA_URL}/v1/chat/completions`, {
                model: OLLAMA_MODEL, messages: msgs, stream: false
            }, { timeout: 8000 });
            return response.data.choices[0].message.content.trim();
        } catch (ollamaErr) {
            console.warn('⚠️ Ollama unreachable, falling back to Groq:', ollamaErr.message);
        }
    }

    // ── 2. Groq (free, fast) ──
    try {
        const response = await axios.post(GROQ_URL, {
            model: GROQ_MODEL, messages: msgs, max_tokens: 800
        }, {
            timeout: 10000,
            headers: {
                'Authorization': `Bearer ${process.env.GROQ_API_KEY}`,
                'Content-Type': 'application/json'
            }
        });
        return response.data.choices[0].message.content.trim();
    } catch (groqErr) {
        const detail = groqErr.response?.data ? JSON.stringify(groqErr.response.data) : groqErr.message;
        console.warn('⚠️ Groq failed, falling back to DeepSeek:', detail);
    }

    // ── 3. DeepSeek fallback ──
    try {
        const response = await axios.post(DEEPSEEK_URL, {
            model: DEEPSEEK_MODEL, messages: msgs, max_tokens: 800
        }, {
            timeout: 10000,
            headers: {
                'Authorization': `Bearer ${process.env.DEEPSEEK_API_KEY}`,
                'Content-Type': 'application/json'
            }
        });
        return response.data.choices[0].message.content.trim();
    } catch (deepseekErr) {
        const detail = deepseekErr.response?.data ? JSON.stringify(deepseekErr.response.data) : deepseekErr.message;
        console.warn('⚠️ DeepSeek failed, falling back to Gemini:', detail);
    }

    // ── 4. Gemini final fallback ──
    const prompt = msgs.map(m => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`).join('\n');
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }]
    }, { timeout: 10000 });
    return response.data.candidates[0].content.parts[0].text.trim();
}

// ─── Gemini with Google Search grounding (real-time data) ─────────────────────

async function callGeminiWithSearch(prompt) {
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }],
        tools: [{ google_search: {} }]
    }, { timeout: 10000 });
    return response.data.candidates[0].content.parts[0].text.trim();
}

// ─── Gemini Vision (image + text) ─────────────────────────────────────────────

function detectMimeType(base64) {
    if (base64.startsWith('/9j/'))  return 'image/jpeg';
    if (base64.startsWith('iVBOR')) return 'image/png';
    if (base64.startsWith('UklGR')) return 'image/webp';
    return 'image/jpeg';
}

async function callGeminiVision(prompt, imageBase64) {
    const response = await axios.post(GEMINI_URL, {
        contents: [{
            parts: [
                { text: prompt },
                { inline_data: { mime_type: detectMimeType(imageBase64), data: imageBase64 } }
            ]
        }]
    }, { timeout: 10000 });
    return response.data.candidates[0].content.parts[0].text.trim();
}

module.exports = { GEMINI_URL, callGemma4, callGeminiWithSearch, callGeminiVision };
