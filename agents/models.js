require('dotenv').config();
const axios = require('axios');

// ─── Change model here to switch for all agents ────────────────────────────
const GEMINI_MODEL = 'gemini-2.5-flash-lite';
// ──────────────────────────────────────────────────────────────────────────

const key = process.env.GOOGLE_API_KEY;
const BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

const GEMINI_URL = `${BASE}/${GEMINI_MODEL}:generateContent?key=${key}`;

// HuggingFace Inference API — separate quota from Google
// Free models: mistralai/Mistral-7B-Instruct-v0.3 | Qwen/Qwen2.5-72B-Instruct
const HF_MODEL = 'mistralai/Mistral-7B-Instruct-v0.3';
const HF_URL = 'https://api-inference.huggingface.co/v1/chat/completions';

async function callGemma4(prompt) {
    // Primary: HuggingFace (separate quota)
    try {
        const response = await axios.post(
            HF_URL,
            {
                model: HF_MODEL,
                messages: [{ role: 'user', content: prompt }],
                max_tokens: 500,
                stream: false
            },
            {
                headers: {
                    'Authorization': `Bearer ${process.env.HF_TOKEN}`,
                    'Content-Type': 'application/json'
                }
            }
        );
        return response.data.choices[0].message.content.trim();
    } catch (hfErr) {
        console.warn(`⚠️ HF failed (${hfErr.response?.status ?? hfErr.message}), falling back to Gemini`);
    }

    // Fallback: Gemini
    const geminiResponse = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }]
    });
    return geminiResponse.data.candidates[0].content.parts[0].text.trim();
}

module.exports = { GEMINI_URL, callGemma4 };
