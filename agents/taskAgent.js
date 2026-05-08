const { sanitizeLike } = require('./utils');
require('dotenv').config();
const { callGemma4 } = require('./models');
const obsidianSync   = require('../services/obsidianSync');

const TASK_PROMPT = `You are a task management AI. Analyze the Hebrew user message and extract the intent.
Allowed intents: 'add', 'list', 'delete', 'complete'.
- 'complete': user says they finished/completed a task (e.g. סיימתי, עשיתי, השלמתי, סמן כבוצע)
- 'delete': user explicitly wants to remove a task without completing it
Return ONLY a JSON object: {"intent": "add|list|delete|complete", "taskDetails": "the task text to add/delete/complete, or empty string for list"}

User message: `;

async function runTaskAgent(userMessage, supabase, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';

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
            return { answer: `מעולה ${userName}, הוספתי את המשימה: ${parsed.taskDetails}` };
        }

        if (parsed.intent === 'list') {
            const { data } = await supabase.from('tasks').select('*');
            if (!data || data.length === 0) return { answer: `אין לך משימות כרגע ${userName}, אתה חופשי.` };
            const list = data.map((t, i) => `${i + 1}. ${t.content}`).join('. ');
            return { answer: `הנה המשימות שלך ${userName}: ${list}` };
        }

        if (parsed.intent === 'delete') {
            const { data: matches } = await supabase
                .from('tasks')
                .select('id, content')
                .ilike('content', `%${sanitizeLike(parsed.taskDetails)}%`);
            if (!matches || matches.length === 0) return { answer: 'לא מצאתי משימה כזו למחוק.' };
            if (matches.length > 1) {
                const list = matches.map((t, i) => `${i + 1}. ${t.content}`).join('\n');
                return { answer: `מצאתי ${matches.length} משימות תואמות. תוכל להיות יותר ספציפי?\n${list}` };
            }
            await supabase.from('tasks').delete().eq('id', matches[0].id);
            return { answer: `מחקתי את המשימה: ${matches[0].content}` };
        }

        if (parsed.intent === 'complete') {
            const { data: matches } = await supabase
                .from('tasks')
                .select('id, content')
                .ilike('content', `%${sanitizeLike(parsed.taskDetails)}%`)
                .eq('done', false);
            if (!matches || matches.length === 0) return { answer: 'לא מצאתי משימה כזו. נסה לציין את שם המשימה.' };
            if (matches.length > 1) {
                const list = matches.map((t, i) => `${i + 1}. ${t.content}`).join('\n');
                return { answer: `מצאתי ${matches.length} משימות תואמות. על איזו מהן?\n${list}` };
            }
            await supabase.from('tasks').update({ done: true }).eq('id', matches[0].id);
            return { answer: `כל הכבוד ${userName}! סיימת את: "${matches[0].content}" ✓` };
        }

        return { answer: 'לא הכרתי את הכוונה. נסה: "הוסף משימה", "רשימת משימות", "מחק משימה" או "סיימתי".' };

    } catch (err) {
        console.error('TaskAgent Error:', err.message);
    }

    return { answer: 'הייתה בעיה בעיבוד המשימה, נסה שוב.' };
}

module.exports = { runTaskAgent };
