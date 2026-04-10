require('dotenv').config();
const axios = require('axios');

const key = process.env.GOOGLE_API_KEY;
const BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

// Gemini 2.5 Flash — Google Search support (chatAgent, sportsAgent)
const GEMINI_25_URL = `${BASE}/gemini-2.5-flash:generateContent?key=${key}`;

// Gemma 4 via HuggingFace Inference API — separate quota from Google
// Change model ID here if needed: gemma-4-2b-it / gemma-4-12b-it / gemma-4-27b-it
const HF_MODEL = 'google/gemma-4-27b-it';
const HF_URL = 'https://api-inference.huggingface.co/v1/chat/completions';

async function callGemma4(prompt) {
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
}

module.exports = { GEMINI_25_URL, callGemma4 };
