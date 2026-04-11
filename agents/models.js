require('dotenv').config();
const axios = require('axios');

// ─── Change model here to switch for all agents ────────────────────────────
const GEMINI_MODEL = 'gemini-2.5-flash-lite';
// ──────────────────────────────────────────────────────────────────────────

const key = process.env.GOOGLE_API_KEY;
const BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

const GEMINI_URL = `${BASE}/${GEMINI_MODEL}:generateContent?key=${key}`;

// Simple Gemini call for agents that don't need Google Search
async function callGemma4(prompt) {
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }]
    });
    return response.data.candidates[0].content.parts[0].text.trim();
}

module.exports = { GEMINI_URL, callGemma4 };
