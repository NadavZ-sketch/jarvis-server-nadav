require('dotenv').config();
const { callGemma4 } = require('./models');

// ── Supabase table required ────────────────────────────────────────────────────
// CREATE TABLE shopping_items (
//   id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
//   item        text NOT NULL,
//   done        boolean DEFAULT false,
//   created_at  timestamptz DEFAULT now()
// );
// ─────────────────────────────────────────────────────────────────────────────

const SHOPPING_PROMPT = `אתה עוזר רשימת קניות. נתח את בקשת המשתמש בעברית.
Allowed intents: 'add', 'list', 'delete'.
- 'add': המשתמש רוצה להוסיף פריט לרשימה
- 'list': המשתמש רוצה לראות את הרשימה
- 'delete': המשתמש רוצה למחוק/להסיר פריט שנקנה
Return ONLY valid JSON: {"intent":"add|list|delete","item":"item name or empty string"}

User message: `;

async function runShoppingAgent(userMessage, supabase, useLocal = true) {
    try {
        const aiText = await callGemma4(SHOPPING_PROMPT + userMessage, useLocal);

        const lastOpen  = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');
        if (lastOpen === -1 || lastClose === -1) throw new Error('No JSON in response');

        const parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        console.log('🛒 ShoppingAgent:', parsed);

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
                .ilike('item', `%${parsed.item}%`)
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
