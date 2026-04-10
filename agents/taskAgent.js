require('dotenv').config();
const axios = require('axios');

const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=${process.env.GOOGLE_API_KEY}`;

const TASK_PROMPT = `You are a task management AI. Analyze the Hebrew user message and extract the intent.
Allowed intents: 'add', 'list', 'delete'.
Return ONLY a JSON object: {"intent": "add|list|delete", "taskDetails": "the task text to add or delete, or empty string for list"}

User message: `;

async function runTaskAgent(userMessage, supabase) {
    try {
        const response = await axios.post(GEMINI_URL, {
            contents: [{ parts: [{ text: TASK_PROMPT + userMessage }] }]
        });

        let aiText = response.data.candidates[0].content.parts[0].text;
        const lastOpen = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');

        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in task agent response');

        const parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        console.log('📋 TaskAgent:', parsed);

        if (parsed.intent === 'add') {
            await supabase.from('tasks').insert([{ content: parsed.taskDetails }]);
            return { answer: `מעולה, הוספתי את המשימה: ${parsed.taskDetails}` };
        }

        if (parsed.intent === 'list') {
            const { data } = await supabase.from('tasks').select('*');
            if (!data || data.length === 0) return { answer: 'אין לך משימות כרגע, אתה חופשי.' };
            const list = data.map((t, i) => `${i + 1}. ${t.content}`).join('. ');
            return { answer: `הנה המשימות שלך: ${list}` };
        }

        if (parsed.intent === 'delete') {
            const { data } = await supabase
                .from('tasks')
                .delete()
                .ilike('content', `%${parsed.taskDetails}%`)
                .select();
            if (data && data.length > 0) return { answer: `מחקתי את המשימה: ${data[0].content}` };
            return { answer: 'לא מצאתי משימה כזו למחוק.' };
        }

    } catch (err) {
        console.error('TaskAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בעיבוד המשימה, נסה שוב.' };
}

module.exports = { runTaskAgent };
