require('dotenv').config();
const { callGemma4 } = require('./models');
const obsidianSync   = require('../services/obsidianSync');

const TASK_PROMPT = `You are a task management AI. Analyze the Hebrew user message and extract the intent.
Allowed intents: 'add', 'list', 'delete', 'complete'.
- 'complete': user says they finished/completed a task (e.g. סיימתי, עשיתי, השלמתי, סמן כבוצע)
- 'delete': user explicitly wants to remove a task without completing it
Return ONLY a JSON object: {"intent": "add|list|delete|complete", "taskDetails": "the task text to add/delete/complete, or empty string for list"}

User message: `;

async function runTaskAgent(userMessage, supabase, useLocal = true) {
    try {
        const aiText = await callGemma4(TASK_PROMPT + userMessage, useLocal);

        const lastOpen = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');

        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in task agent response');

        let parsed;
        try {
            parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        } catch {
            return { answer: 'לא הצלחתי לעבד את הבקשה, נסה לנסח אחרת.' };
        }
        console.log('📋 TaskAgent:', parsed);

        if (parsed.intent === 'add') {
            await supabase.from('tasks').insert([{ content: parsed.taskDetails }]);
            obsidianSync.dbToVault('tasks', { content: parsed.taskDetails });
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

        if (parsed.intent === 'complete') {
            const { data } = await supabase
                .from('tasks')
                .delete()
                .ilike('content', `%${parsed.taskDetails}%`)
                .select();
            if (data && data.length > 0) return { answer: `כל הכבוד! סיימת את: "${data[0].content}" ✓` };
            return { answer: 'לא מצאתי משימה כזו. נסה לציין את שם המשימה.' };
        }

        return { answer: 'לא הכרתי את הכוונה. נסה: "הוסף משימה", "רשימת משימות", "מחק משימה" או "סיימתי".' };

    } catch (err) {
        console.error('TaskAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בעיבוד המשימה, נסה שוב.' };
}

module.exports = { runTaskAgent };
