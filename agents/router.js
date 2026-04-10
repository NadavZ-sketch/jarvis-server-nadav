require('dotenv').config();
const axios = require('axios');

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=${process.env.GOOGLE_API_KEY}`;

// Keyword-based fast routing — no Gemini call needed for obvious cases
// ORDER MATTERS: reminder must be before memory to avoid תזכיר לי conflict
const KEYWORDS = {
    task:     /משימ|הוסף משימ|מחק משימ|רשימת משימ|הראה משימ|כל המשימ/i,
    reminder: /תזכיר לי|הזכר לי|תזכורת|להזכיר לי/i,
    memory:   /זכור ש|תזכור ש|שמור ש|מה אתה יודע|מה זכרת|ספר לי עליי|מה שמרת/i,
    sports:   /כדורגל|פרמייר|ליג|מאמן|קבוצ|שחקן|גול|ניצחון|הפסד|תוצא|טבלה|דירוג|העברות|ארסנל|צ'לסי|מנצ'סטר|ליברפול|טוטנהאם|אסטון|ניוקאסל|ברייטון|everton|arsenal|chelsea|liverpool|premier league|epl/i,
};

const CLASSIFY_PROMPT = `You are an intent classifier. Given a Hebrew or English user message, classify it into exactly one of these four categories:

- task: adding, listing, checking, deleting, or completing tasks or todo items
- reminder: user wants to be reminded of something at a specific future time
- memory: saving personal information, facts about the user, or things to remember about Nadav
- sports: any question about football, soccer, Premier League, EPL, matches, scores, standings, fixtures, teams, or players
- chat: everything else including weather, general questions, conversation, advice, image analysis

Reply with ONLY the single lowercase word. No punctuation, no explanation.

User message: `;

async function classifyIntent(userMessage) {
    // Fast path: keyword match (saves a Gemini API call)
    for (const [intent, pattern] of Object.entries(KEYWORDS)) {
        if (pattern.test(userMessage)) {
            console.log(`🧭 Router (keyword): "${intent}" ← "${userMessage.slice(0, 50)}"`);
            return intent;
        }
    }

    // No keyword match → default to chat (saves a Gemini API call)
    console.log(`🧭 Router (default): "chat" ← "${userMessage.slice(0, 50)}"`);
    return 'chat';
}

module.exports = { classifyIntent };
