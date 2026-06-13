require('dotenv').config();
const obsidianSync    = require('../services/obsidianSync');

// ── Supabase table required ────────────────────────────────────────────────────
// CREATE TABLE notes (
//   id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
//   title       text DEFAULT '',
//   content     text NOT NULL,
//   created_at  timestamptz DEFAULT now()
// );
// ─────────────────────────────────────────────────────────────────────────────

// Regex-based intent parser — no LLM needed for simple CRUD classification.
function _parseIntent(msg) {
    const m = msg.trim();

    // list
    if (/הצג הערות|מה כתבת|הערות שלי|פתקים שלי|כל ההערות|הראה הערות|רשימת הערות|הצג פתקים/i.test(m)) {
        return { intent: 'list', content: '', title: '' };
    }

    // search
    if (/חפש הערה|חפש בהערות|חפש פתק|חפש ב/i.test(m)) {
        const q = m.replace(/^(?:חפש\s+(?:הערה|בהערות|פתק|ב)?)\s*/i, '').trim();
        return { intent: 'search', content: q, title: '' };
    }

    // delete
    if (/מחק הערה|הסר הערה|מחק פתק|הסר פתק/i.test(m)) {
        const q = m.replace(/^(?:מחק|הסר)\s+(?:הערה|פתק)?\s*/i, '').trim();
        return { intent: 'delete', content: q, title: '' };
    }

    // add — strip leading verb, rest is note content
    const content = m.replace(/^(?:תרשום לי|רשום לי|שמור פתק|שמור הערה|הוסף הערה|הוסף פתק|כתוב פתק|תכתוב פתק)\s*/i, '').trim();
    return { intent: 'add', content: content || m, title: '' };
}

async function runNotesAgent(userMessage, repos, useLocal = true) {
    const notes = repos.notes;
    try {
        const parsed = _parseIntent(userMessage);

        if (parsed.intent === 'add') {
            const inserted = await notes.add({
                title:   parsed.title   || '',
                content: parsed.content || userMessage,
            });
            if (inserted) obsidianSync.dbToVault('notes', inserted);
            const label = parsed.title ? ` "${parsed.title}"` : '';
            return {
                answer: `שמרתי את ההערה${label} 📝`,
                action: { type: 'navigate', target: 'notes', label: 'פתח הערות' },
            };
        }

        if (parsed.intent === 'list') {
            const data = await notes.listRecent(10);
            if (!data || data.length === 0) return { answer: 'אין לך הערות שמורות.' };
            const list = data.map((n, i) => {
                const preview = n.title || n.content.slice(0, 40);
                return `${i + 1}. ${preview}`;
            }).join('\n');
            return { answer: `ההערות שלך:\n${list}` };
        }

        if (parsed.intent === 'search') {
            const q = parsed.content;
            const data = await notes.search(q);
            if (!data || data.length === 0) return { answer: `לא מצאתי הערות עם "${q}".` };
            const found = data.map((n, i) =>
                `${i + 1}. ${n.title || ''}: ${n.content.slice(0, 80)}`
            ).join('\n');
            return { answer: `מצאתי ${data.length} הערות:\n${found}` };
        }

        if (parsed.intent === 'delete') {
            const q = parsed.content || parsed.title;
            if (!q) return { answer: 'איזו הערה למחוק?' };
            const data = await notes.deleteMatching(q);
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
