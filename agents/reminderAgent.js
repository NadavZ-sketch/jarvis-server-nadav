require('dotenv').config();
const axios = require('axios');

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${process.env.GOOGLE_API_KEY}`;

function buildReminderPrompt(userMessage) {
    const now = new Date();
    const isoNow = now.toLocaleString('sv-SE', { timeZone: 'Asia/Jerusalem' }).replace(' ', 'T');

    return `You are a reminder time parser. The user wants to set a reminder.
Current date and time in Jerusalem (Israel): ${isoNow}+03:00

Extract:
1. reminderText — what the reminder is about (in Hebrew, as the user stated it)
2. scheduledTime — the exact ISO 8601 timestamp when the reminder should fire

Return ONLY a JSON object:
{"reminderText": "...", "scheduledTime": "YYYY-MM-DDTHH:MM:SS+03:00"}

Rules:
- "מחר" means tomorrow, same time of day unless a time is specified
- "בעוד שעה" means now + 1 hour
- "בעוד X דקות" means now + X minutes
- "ב-15:00" or "בשעה 15:00" means today at 15:00 Jerusalem time (or tomorrow if already past)
- "ביום שישי" means the coming Friday
- Always use +03:00 for Israel timezone

User message: ${userMessage}`;
}

async function runReminderAgent(userMessage, supabase) {
    try {
        const response = await axios.post(GEMINI_URL, {
            contents: [{ parts: [{ text: buildReminderPrompt(userMessage) }] }]
        });

        let aiText = response.data.candidates[0].content.parts[0].text;
        const lastOpen  = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');

        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in reminderAgent response');

        const parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        const { reminderText, scheduledTime } = parsed;

        if (!reminderText || !scheduledTime) throw new Error('Missing fields in reminderAgent JSON');

        const fireDate = new Date(scheduledTime);
        if (isNaN(fireDate.getTime())) throw new Error(`Invalid scheduledTime: ${scheduledTime}`);

        console.log(`⏰ ReminderAgent: "${reminderText}" at ${scheduledTime}`);

        const { error } = await supabase
            .from('reminders')
            .insert([{ text: reminderText, scheduled_time: scheduledTime }]);

        if (error) throw error;

        const fireLocal = fireDate.toLocaleString('he-IL', {
            timeZone: 'Asia/Jerusalem',
            weekday: 'long',
            day: 'numeric',
            month: 'long',
            hour: '2-digit',
            minute: '2-digit'
        });

        return { answer: `בסדר נדב, אזכיר לך "${reminderText}" ב${fireLocal}.` };

    } catch (err) {
        console.error('ReminderAgent Error:', err.message);
        return { answer: 'הייתה בעיה בהגדרת התזכורת, נסה שוב.' };
    }
}

module.exports = { runReminderAgent };
