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

// ── Option extraction: read signals from the user's free-text request ──────
// Inspired by the React UI's advanced strategy panel — but applied automatically
// from natural language instead of requiring the user to toggle switches.
function parseOptions(userMessage) {
    const msg = userMessage.toLowerCase();
    return {
        // Target model → affects whether we use XML tags or bold markdown headings
        targetClaude: /claude|קלוד|xml/i.test(msg),
        // Prompt engineering techniques
        fewShot:    /דוגמ|few.?shot|example|לדוגמ|instance/i.test(msg),
        constraints:/אל ת|לא ת|ללא|אסור|הגבל|constrain|negative|קו אדום|avoid|without/i.test(msg),
        scratchpad: /חשוב שלב|step.?by.?step|scratchpad|chain.?of.?thought|cot|נמק|פרט את/i.test(msg),
        chaining:   /שרשור|שלבים|שני פרומפט|מספר פרומפט|pipeline|chain|מורכב מאוד|complex/i.test(msg),
        multiRole:  /\+|ו?גם|יחד עם|שילוב.*תפקיד|multi.?persona/i.test(msg),
    };
}

// ── Build the dynamic system instruction based on detected options ──────────
function buildCreateSystemPrompt(opts) {
    const structureRule = opts.targetClaude
        ? `השתמש בתגיות XML להפרדת סעיפים (<role>, <context>, <instructions>, <output_format>, <constraints>). זה קריטי — Claude מותאם ל-XML ומבצע הנחיות XML-structured טוב יותר.`
        : `השתמש בכותרות מודגשות בעברית (למשל: **תפקיד:**, **מטרה:**, **הנחיות:**). אל תשתמש ב-XML.`;

    const fewShotRule = opts.fewShot
        ? `✅ חובה: ייצר ושתול 1-2 דוגמאות פלט (few-shot examples) שממחישות תוצאה טובה. הצג אותן תחת כותרת "דוגמאות:".`
        : '';

    const constraintRule = opts.constraints
        ? `✅ חובה: כלול סעיף "אילוצים / מה לא לעשות:" עם לפחות 3 קווים אדומים ברורים.`
        : '';

    const scratchpadRule = opts.scratchpad
        ? `✅ חובה: הוסף בסוף הפרומפט הנחיה מפורשת: "לפני תשובתך הסופית, פתח אזור חשיבה (<thinking> או ###) ונתח את הבעיה שלב אחר שלב."`
        : '';

    const chainingRule = opts.chaining
        ? `✅ חובה: אל תייצר פרומפט אחד ארוך! חלק את המשימה לשרשרת פרומפטים (Prompt Chain) עם כותרות: "פרומפט 1:", "פרומפט 2:" וכו׳.`
        : '';

    const multiRoleRule = opts.multiRole
        ? `✅ שים לב: יש לשלב יותר מפרסונה אחת. הצג אותן כ"צוות מומחים" ולא כאדם אחד כדי למנוע בלבול אצל המודל.`
        : '';

    const techApplied = [
        opts.fewShot ? 'few-shot examples' : '',
        opts.constraints ? 'negative constraints' : '',
        opts.scratchpad ? 'CoT scratchpad' : '',
        opts.chaining ? 'prompt chaining' : '',
        opts.multiRole ? 'multi-persona blending' : '',
    ].filter(Boolean);

    return {
        system: `אתה "Prompt Architect" — מהנדס פרומפטים ברמת מומחה-על.
מטרתך: לבנות פרומפטים אטומי-טעויות, ברורים ומדויקים.

─── כללי מבנה ───
${structureRule}
${fewShotRule}
${constraintRule}
${scratchpadRule}
${chainingRule}
${multiRoleRule}

─── כללים נוספים (תמיד) ───
- הוסף "נתיב מילוט" — הנחיות כיצד לנהוג במקרי קצה לא צפויים.
- פרסונה ברורה: "אתה X עם ניסיון של Y שנים ב-Z..."
- הנחיות ממוספרות, לא פסקאות גוש.
- פורמט פלט מוגדר במדויק.

─── פורמט תגובה (קשיח) ───
<strategy>
[ניתוח 3-4 משפטים: מהי הגישה שנבחרה ולמה, אילו טכניקות מיושמות]
</strategy>
<prompt>
[הפרומפט הסופי המלא — מוכן להעתקה]
</prompt>`,
        techApplied,
    };
}

// ── Parse strategy + prompt from LLM output ───────────────────────────────
function parseStrategyAndPrompt(rawText) {
    const strategyMatch = rawText.match(/<strategy>([\s\S]*?)<\/strategy>/i);
    const promptMatch   = rawText.match(/<prompt>([\s\S]*?)<\/prompt>/i);
    return {
        strategy: strategyMatch?.[1]?.trim() || '',
        prompt:   promptMatch?.[1]?.trim() || rawText.trim(),
    };
}

// ── Format the final answer presented to the user ─────────────────────────
function formatCreateAnswer(title, strategy, prompt, techApplied) {
    const techLine = techApplied.length > 0
        ? `\n⚙️ **טכניקות שיושמו:** ${techApplied.join(' · ')}`
        : '';

    const strategyBlock = strategy
        ? `\n🧠 **אסטרטגיה:** ${strategy}\n`
        : '';

    return `📋 **${title || 'הפרומפט שלך'}**
${strategyBlock}${techLine}

\`\`\`
${prompt}
\`\`\``;
}

// ── Create: build a complete prompt from a use-case description ────────────
async function createPrompt(userMessage, useLocal) {
    const opts = parseOptions(userMessage);
    const { system, techApplied } = buildCreateSystemPrompt(opts);

    const raw = await callGemma4([
        { role: 'system', content: system },
        { role: 'user',   content: `בנה פרומפט מקצועי עבור המקרה הבא:\n\n${userMessage}` },
    ], useLocal, 1400);

    const { strategy, prompt } = parseStrategyAndPrompt(raw);

    // Extract title: first meaningful line of the prompt
    const titleLine = prompt.split('\n').find(l => l.trim().length > 3) || 'הפרומפט שלך';
    const title = titleLine.replace(/^[#*\-<>]+/, '').slice(0, 50).trim();

    return {
        answer: formatCreateAnswer(title, strategy, prompt, techApplied),
        action: { type: 'prompt_created' },
    };
}

// ── Refine: Evaluate & Repair methodology ────────────────────────────────
// Inspired by the React component's "improvePrompt" — not just "improve",
// but explicitly find logical holes then patch them.
async function refinePrompt(userMessage, useLocal) {
    const opts = parseOptions(userMessage);
    const structInstr = opts.targetClaude
        ? 'השתמש בתגיות XML כנדרש ב-Claude.'
        : 'השתמש בכותרות מודגשות בעברית. אל תשתמש ב-XML.';

    const system = `אתה מהנדס פרומפטים המיישם שיטת "Evaluate & Repair".

שלב 1 — הערכה: מצא בפרומפט הנתון:
- עמימות (מה יכול להתפרש בטעות?)
- חורים לוגיים (מה לא הוגדר ויגרום לסטייה?)
- פרסונה חלשה / חסרת הקשר
- היעדר פורמט פלט ברור
- היעדר נתיב מילוט למקרי קצה

שלב 2 — תיקון: שכתב את הפרומפט כך שיהיה אטום לכשלים שמצאת.
${structInstr}

פורמט תגובה:
🔍 **חורים שמצאתי:**
- [חור 1]
- [חור 2]

✅ **הפרומפט לאחר Evaluate & Repair:**

\`\`\`
[הפרומפט המתוקן]
\`\`\``;

    const answer = await callGemma4([
        { role: 'system', content: system },
        { role: 'user',   content: userMessage },
    ], useLocal, 1400);

    return { answer };
}

// ── Evaluate: score and critique a prompt ─────────────────────────────────
async function evaluatePrompt(userMessage, useLocal) {
    const system = `אתה מעריך פרומפטים מקצועי. נתח את הפרומפט שניתן לך לפי חמישה קריטריונים (ציון 1-10):

1. **בהירות** — האם ההנחיות ברורות וחד-משמעיות?
2. **ספציפיות** — האם המטרה מוגדרת מספיק?
3. **מבנה** — האם יש פרסונה, הנחיות ממוספרות, ופורמט פלט?
4. **שלמות** — האם יש הקשר מספק ונתיב מילוט?
5. **יעילות** — האם הפרומפט תמציתי אך מלא (ללא עודפות)?

פורמט תגובה:
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

💡 **המלצות ספציפיות לשיפור:**
- ...`;

    const answer = await callGemma4([
        { role: 'system', content: system },
        { role: 'user',   content: `הערך את הפרומפט הבא:\n\n${userMessage}` },
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
    } catch {
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

module.exports = { runPromptAgent, detectIntent, parseOptions };
