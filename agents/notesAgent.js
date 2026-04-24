const { sanitizeLike } = require('./utils');
require('dotenv').config();
const { callGemma4 }  = require('./models');
const obsidianSync    = require('../services/obsidianSync');

// ── Supabase table required ────────────────────────────────────────────────────
// CREATE TABLE notes (
//   id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
//   title       text DEFAULT '',
//   content     text NOT NULL,
//   created_at  timestamptz DEFAULT now()
// );
// ─────────────────────────────────────────────────────────────────────────────

const NOTES_PROMPT = `אתה עוזר הערות. נתח את בקשת המשתמש בעברית.
Allowed intents: 'add', 'list', 'search', 'delete'.
- 'add': שמור הערה/פתק חדש
- 'list': הצג את כל ההערות
- 'search': חפש הערה לפי תוכן
- 'delete': מחק הערה
Return ONLY valid JSON: {"intent":"add|list|search|delete","content":"note text or search query","title":"short title or empty string"}

User message: `;

async function runNotesAgent(userMessage, supabase, useLocal = true) {
    try {
        const aiText = await callGemma4(NOTES_PROMPT + userMessage, useLocal);

        const lastOpen  = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');
        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in response');

        const parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        console.log('📝 NotesAgent:', parsed);

        if (parsed.intent === 'add') {
            const { data: inserted } = await supabase.from('notes').insert([{
                title:   parsed.title   || '',
                content: parsed.content || userMessage,
            }]).select().single();
            if (inserted) obsidianSync.dbToVault('notes', inserted);
            const label = parsed.title ? ` "${parsed.title}"` : '';
            return { answer: `שמרתי את ההערה${label} 📝` };
        }

        if (parsed.intent === 'list') {
            const { data } = await supabase
                .from('notes')
                .select('*')
                .order('created_at', { ascending: false })
                .limit(10);
            if (!data || data.length === 0) return { answer: 'אין לך הערות שמורות.' };
            const list = data.map((n, i) => {
                const preview = n.title || n.content.slice(0, 40);
                return `${i + 1}. ${preview}`;
            }).join('\n');
            return { answer: `ההערות שלך:\n${list}` };
        }

        if (parsed.intent === 'search') {
            const q = parsed.content;
            const { data } = await supabase
                .from('notes')
                .select('*')
                .or(`title.ilike.%${sanitizeLike(q)}%,content.ilike.%${sanitizeLike(q)}%`)
                .limit(5);
            if (!data || data.length === 0) return { answer: `לא מצאתי הערות עם "${q}".` };
            const found = data.map((n, i) =>
                `${i + 1}. ${n.title || ''}: ${n.content.slice(0, 80)}`
            ).join('\n');
            return { answer: `מצאתי ${data.length} הערות:\n${found}` };
        }

        if (parsed.intent === 'delete') {
            const q = parsed.content || parsed.title;
            if (!q) return { answer: 'איזו הערה למחוק?' };
            const { data } = await supabase
                .from('notes')
                .delete()
                .or(`title.ilike.%${sanitizeLike(q)}%,content.ilike.%${sanitizeLike(q)}%`)
                .select();
            if (data && data.length > 0) return { answer: 'ההערה נמחקה ✓' };
            return { answer: 'לא מצאתי הערה למחוק.' };
        }

        return { answer: 'לא הבנתי. נסה "תרשום לי..." או "הצג הערות".' };
    } catch (err) {
        console.error('NotesAgent error:', err.message);
        return { answer: 'שגיאה בעיבוד בקשת ההערות.' };
    }
}

module.exports = { runNotesAgent };
