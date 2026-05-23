require('dotenv').config();
const { callGemma4 } = require('./models');

/* ── Supabase table (run once) ────────────────────────────────────────────
   CREATE TABLE user_prompts (
     id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
     title      text NOT NULL,
     prompt     text NOT NULL,
     category   text DEFAULT 'general',
     created_at timestamptz DEFAULT now()
   );
 ─────────────────────────────────────────────────────────────────────────── */

// ── Intent detection (fast, no API call) ──────────────────────────────────
const INTENT_PATTERNS = {
    list:     /רשימת פרומפטים|הצג פרומפטים|פרומפטים שמורים|כל הפרומפטים|הפרומפטים שלי/i,
    save:     /שמור.*פרומפט|שמור.*הנחיה|save.*prompt/i,
    evaluate: /הערך.*פרומפט|בדוק.*פרומפט|נתח.*פרומפט|ניקוד.*פרומפט|כמה טוב.*פרומפט|evaluate.*prompt/i,
    refine:   /שפר.*פרומפט|שדרג.*פרומפט|שפר.*הנחיה|תקן.*פרומפט|שפר את זה|שפר אותו|refine.*prompt|improve.*prompt/i,
};

function detectIntent(userMessage) {
    for (const [intent, pattern] of Object.entries(INTENT_PATTERNS)) {
        if (pattern.test(userMessage)) return intent;
    }
    return 'create';
}

// ── Create: build a complete prompt from a use-case description ────────────
async function createPrompt(userMessage, useLocal) {
    const systemPrompt = `אתה מומחה הנדסת פרומפטים (Prompt Engineering) עם ניסיון ב-Claude, GPT-4 ו-Gemini.
תפקידך: לקבל תיאור של מקרה שימוש וליצור פרומפט מקצועי, ברור ואפקטיבי.

עקרונות שאתה מיישם בכל פרומפט שאתה בונה:
1. פרסונה/תפקיד ברור ("אתה X עם ניסיון ב-Y...")
2. הקשר ומטרה מוגדרים היטב
3. הנחיות ספציפיות, ממוספרות
4. פורמט פלט מדויק (מה ה-AI אמור להחזיר)
5. אילוצים ומגבלות (מה לא לעשות)
6. Chain-of-thought אם הבעיה מורכבת ("חשוב שלב אחר שלב...")
7. דוגמאות (few-shot) כשיש ערך ממשי

פורמט התגובה חייב להיות:
📋 **[כותרת הפרומפט]**

\`\`\`
[הפרומפט המלא כאן — מוכן להעתקה]
\`\`\`

💡 **מה בניתי ולמה:** [הסבר קצר 2-3 משפטים על הבחירות שעשית]`;

    const answer = await callGemma4([
        { role: 'system', content: systemPrompt },
        { role: 'user', content: `בנה פרומפט מקצועי עבור: ${userMessage}` },
    ], useLocal, 1200);

    return { answer, action: { type: 'prompt_created' } };
}

// ── Refine: improve an existing prompt ────────────────────────────────────
async function refinePrompt(userMessage, useLocal) {
    const systemPrompt = `אתה מומחה הנדסת פרומפטים. קיבלת פרומפט קיים לשיפור.

שפר אותו על ידי:
1. הוספת פרסונה ברורה אם חסרה
2. ביטול עמימות — כל הנחיה חייבת להיות חד-משמעית
3. הגדרת פורמט פלט אם לא קיים
4. הוספת Chain-of-thought אם הבעיה מורכבת
5. הסרת כפילויות ומיותרות
6. הוספת דוגמאות (few-shot) אם עוזרות

פורמט התגובה:
✅ **הפרומפט המשופר:**

\`\`\`
[פרומפט משופר כאן]
\`\`\`

🔄 **השינויים שעשיתי:**
- [שינוי 1 — למה]
- [שינוי 2 — למה]`;

    const answer = await callGemma4([
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userMessage },
    ], useLocal, 1200);

    return { answer };
}

// ── Evaluate: score and critique a prompt ─────────────────────────────────
async function evaluatePrompt(userMessage, useLocal) {
    const systemPrompt = `אתה מעריך פרומפטים מקצועי. נתח את הפרומפט שניתן לך.

הערך לפי חמישה קריטריונים (ציון 1-10 לכל אחד):
1. **בהירות** — האם ההנחיות ברורות וחד-משמעיות?
2. **ספציפיות** — האם המטרה מוגדרת מספיק?
3. **מבנה** — האם יש פרסונה, הנחיות, ופורמט פלט?
4. **שלמות** — האם יש מספיק הקשר?
5. **יעילות** — האם הפרומפט תמציתי אך מלא?

פורמט התגובה:
📊 **הערכת הפרומפט:**

| קריטריון | ציון | הערה |
|---------|------|------|
| בהירות | X/10 | ... |
| ספציפיות | X/10 | ... |
| מבנה | X/10 | ... |
| שלמות | X/10 | ... |
| יעילות | X/10 | ... |

**ציון כולל: X/50**

🔴 **חסרונות עיקריים:**
- ...

🟢 **נקודות חוזקה:**
- ...

💡 **המלצות לשיפור:**
- ...`;

    const answer = await callGemma4([
        { role: 'system', content: systemPrompt },
        { role: 'user', content: `הערך את הפרומפט הבא:\n\n${userMessage}` },
    ], useLocal, 1000);

    return { answer };
}

// ── Save: extract and persist a prompt to Supabase ────────────────────────
async function savePrompt(userMessage, supabase, useLocal) {
    const extractInstruction = `Extract the prompt title and the exact prompt text from the message below.
Return ONLY valid JSON (no extra text):
{"title": "short descriptive title in Hebrew", "prompt": "the exact prompt text", "category": "coding|writing|analysis|creative|general"}

Message: ${userMessage}`;

    let title = 'פרומפט ללא שם';
    let promptText = userMessage;
    let category = 'general';

    try {
        const extracted = await callGemma4(extractInstruction, useLocal, 200);
        const o = extracted.indexOf('{');
        const c = extracted.lastIndexOf('}');
        if (o !== -1 && c !== -1) {
            const parsed = JSON.parse(extracted.substring(o, c + 1));
            title = parsed.title || title;
            promptText = parsed.prompt || promptText;
            category = parsed.category || category;
        }
    } catch (parseErr) {
        console.warn('PromptAgent save: JSON parse failed, using raw message');
    }

    try {
        await supabase.from('user_prompts').insert([{ title, prompt: promptText, category }]);
        return {
            answer: `✅ שמרתי את הפרומפט **"${title}"** בהצלחה!`,
            action: { type: 'navigate', target: 'prompts', label: 'פתח פרומפטים' },
        };
    } catch (dbErr) {
        console.warn('PromptAgent: DB save failed:', dbErr.message);
        return {
            answer: `✅ הפרומפט מוכן (השמירה לא הצליחה — העתיקו ידנית):\n\n\`\`\`\n${promptText}\n\`\`\``,
        };
    }
}

// ── List: show saved prompts from Supabase ────────────────────────────────
async function listPrompts(supabase) {
    try {
        const { data, error } = await supabase
            .from('user_prompts')
            .select('id, title, category, created_at')
            .order('created_at', { ascending: false })
            .limit(10);

        if (error) throw error;
        if (!data || data.length === 0) {
            return { answer: 'אין לך פרומפטים שמורים עדיין.\n\nתגיד לי "צור פרומפט ל..." ואבנה לך אחד!' };
        }

        const list = data.map((p, i) => {
            const cat = p.category && p.category !== 'general' ? ` _(${p.category})_` : '';
            const date = new Date(p.created_at).toLocaleDateString('he-IL');
            return `${i + 1}. **${p.title}**${cat} — ${date}`;
        }).join('\n');

        return { answer: `📋 **הפרומפטים השמורים שלך:**\n\n${list}` };
    } catch (err) {
        console.warn('PromptAgent list: DB error:', err.message);
        return { answer: 'לא הצלחתי לטעון את רשימת הפרומפטים. נסה שוב.' };
    }
}

// ── Main entry point ───────────────────────────────────────────────────────
async function runPromptAgent(userMessage, supabase, useLocal, settings = {}) {
    try {
        const useLocalModel = settings.useLocalModel ?? useLocal;
        const intent = detectIntent(userMessage);

        console.log(`🎨 PromptAgent: intent="${intent}" ← "${userMessage.slice(0, 60)}"`);

        switch (intent) {
            case 'list':     return await listPrompts(supabase);
            case 'save':     return await savePrompt(userMessage, supabase, useLocalModel);
            case 'evaluate': return await evaluatePrompt(userMessage, useLocalModel);
            case 'refine':   return await refinePrompt(userMessage, useLocalModel);
            default:         return await createPrompt(userMessage, useLocalModel);
        }
    } catch (err) {
        console.error('PromptAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי לעבד את הבקשה. נסה שוב.' };
    }
}

module.exports = { runPromptAgent, detectIntent };
