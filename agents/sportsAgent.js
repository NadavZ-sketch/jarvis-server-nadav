require('dotenv').config();
const axios = require('axios');
const { GEMINI_URL } = require('./models');

const SPORTS_PROMPT = `You are a Premier League football expert assistant for Nadav.
Use Google Search to find the latest, most current information about English Premier League (EPL) football.
Search for real-time data: current standings, recent match results, upcoming fixtures, top scorers, team news.
Always answer in Hebrew (עברית). Be specific with scores, dates, and statistics.

User question: `;

async function runSportsAgent(userMessage) {
    try {
        const response = await axios.post(GEMINI_URL, {
            contents: [{ parts: [{ text: SPORTS_PROMPT + userMessage }] }],
            tools: [{ googleSearch: {} }]
        });

        // Google Search may return multiple parts — find the text one
        const parts = response.data.candidates[0].content.parts;
        const textPart = parts.find(p => typeof p.text === 'string' && p.text.trim().length > 0);
        const answer = textPart ? textPart.text.trim() : 'לא הצלחתי למצוא מידע עדכני על הפרמייר ליג.';

        console.log('⚽ SportsAgent answered');
        return { answer };

    } catch (err) {
        console.error('SportsAgent Error:', err.response ? JSON.stringify(err.response.data, null, 2) : err.message);
    }

    return { answer: 'סליחה נדב, לא הצלחתי להביא נתוני כדורגל כרגע.' };
}

module.exports = { runSportsAgent };
