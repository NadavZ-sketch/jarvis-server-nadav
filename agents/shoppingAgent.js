const { sanitizeLike } = require('./utils');
require('dotenv').config();

// ── Supabase table required ────────────────────────────────────────────────────
// CREATE TABLE shopping_items (
//   id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
//   item        text NOT NULL,
//   done        boolean DEFAULT false,
//   created_at  timestamptz DEFAULT now()
// );
// ─────────────────────────────────────────────────────────────────────────────

// Regex-based intent parser — no LLM needed for simple CRUD classification.
function _parseIntent(msg) {
    const m = msg.trim();

    // list
    if (/מה יש ברשימה|הצג רשימ|ראה רשימ|רשימת קניות|מה ברשימה|מה צריך לקנות|כל הרשימה/i.test(m)) {
        return { intent: 'list', item: '' };
    }

    // delete / mark-bought
    const delMatch = m.match(/(?:מחק|הסר|הורד|סיימתי לקנות|קניתי|מחקי|הסירי)\s+(?:את\s+)?(.+)/i);
    if (delMatch) return { intent: 'delete', item: delMatch[1].replace(/\s+מהרשימה$/i, '').trim() };

    // add — strip leading verb, strip trailing "לרשימה"
    const addMatch = m.match(/^(?:הוסף|תוסיף|קנה|תקנה|הכנס|תכניס|צריך|צריכה|נצטרך)\s+(?:את\s+)?(.+?)(?:\s+לרשימה)?$/i);
    if (addMatch) return { intent: 'add', item: addMatch[1].trim() };

    // "X לרשימה" shorthand
    const toListMatch = m.match(/^(.+?)\s+לרשימה$/i);
    if (toListMatch) return { intent: 'add', item: toListMatch[1].trim() };

    // fallback — treat whole message as item name to add
    return { intent: 'add', item: m };
}

async function runShoppingAgent(userMessage, supabase, useLocal = true) {
    try {
        const parsed = _parseIntent(userMessage);

        if (parsed.intent === 'add') {
            await supabase.from('shopping_items').insert([{ item: parsed.item }]);
            return { answer: `הוספתי "${parsed.item}" לרשימת הקניות ✅` };
        }

        if (parsed.intent === 'list') {
            const { data } = await supabase
                .from('shopping_items')
                .select('*')
                .eq('done', false)
                .order('created_at', { ascending: true });
            if (!data || data.length === 0) return { answer: 'רשימת הקניות ריקה 🛒' };
            const list = data.map((s, i) => `${i + 1}. ${s.item}`).join('\n');
            return { answer: `רשימת הקניות שלך:\n${list}` };
        }

        if (parsed.intent === 'delete') {
            if (!parsed.item) {
                // Delete all done items or ask for clarification
                return { answer: 'מה תרצה להסיר מהרשימה?' };
            }
            const { data } = await supabase
                .from('shopping_items')
                .delete()
                .ilike('item', `%${sanitizeLike(parsed.item)}%`)
                .select();
            if (data && data.length > 0) return { answer: `הסרתי "${data[0].item}" מהרשימה ✓` };
            return { answer: 'לא מצאתי את הפריט ברשימה.' };
        }

        return { answer: 'לא הבנתי. נסה "הוסף חלב לרשימה" או "מה יש ברשימת הקניות".' };
    } catch (err) {
        console.error('ShoppingAgent error:', err.message);
        return { answer: 'שגיאה בעיבוד בקשת הקניות.' };
    }
}

module.exports = { runShoppingAgent };
