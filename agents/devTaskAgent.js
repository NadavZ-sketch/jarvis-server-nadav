require('dotenv').config();
const fs   = require('fs');
const path = require('path');
const { callGemma4 } = require('./models');

const PENDING_FILE = path.join(__dirname, '..', 'capability_gap_pending.json');
const BACKLOG_FILE = path.join(__dirname, '..', 'backlog.json');

// ─── Pending helpers (mirrors agentFactoryAgent pattern) ──────────────────────

async function savePendingGap(data) {
    await fs.promises.writeFile(PENDING_FILE, JSON.stringify(data, null, 2));
}

async function loadPendingGap() {
    try { return JSON.parse(await fs.promises.readFile(PENDING_FILE, 'utf8')); } catch { return null; }
}

async function clearPendingGap() {
    try { await fs.promises.unlink(PENDING_FILE); } catch { /* ok */ }
}

// ─── Backlog helper ───────────────────────────────────────────────────────────

async function saveDevTask(taskData) {
    let backlog = { proposals: [], proposals_history: [], items: [], dev_tasks: [], ranking_version: 'mvp-v1', _nextId: 1, _lastGenerated: null };
    try {
        backlog = JSON.parse(await fs.promises.readFile(BACKLOG_FILE, 'utf8'));
    } catch { /* use defaults */ }

    if (!Array.isArray(backlog.dev_tasks)) backlog.dev_tasks = [];

    const newTask = {
        id: `dt_${Date.now()}`,
        title: taskData.title,
        userRequest: taskData.userRequest,
        actionDescription: taskData.actionDescription,
        claudePrompt: taskData.claudePrompt,
        status: 'open',
        createdAt: new Date().toISOString().slice(0, 10),
    };

    backlog.dev_tasks.push(newTask);
    await fs.promises.writeFile(BACKLOG_FILE, JSON.stringify(backlog, null, 2));
    return newTask;
}

// ─── Capability gap detection ─────────────────────────────────────────────────

async function detectCapabilityGap(userMessage, agentAnswer) {
    const prompt = `אתה מנתח תשובות של עוזר אישי בשם ג'רוויס.

הודעת משתמש: "${userMessage}"
תשובת ג'רוויס: "${agentAnswer.slice(0, 400)}"

האם המצב הוא שהמשתמש ביקש לבצע פעולה אקטיבית (לא רק שאלה או שיחה), וג'רוויס ענה שהוא לא יכול לבצע אותה, לא תומך בה, או שאין לו את היכולת?

דוגמאות לפעולות שג'רוויס לא יכול: שליחת SMS, הזמנת מונית, קניה אונליין, פתיחת אפליקציה, ניהול יומן Google, תשלום, שליחת הודעת WhatsApp ישירות, וכד'.

ענה JSON בלבד, ללא שום טקסט נוסף:
{
  "isGap": true/false,
  "actionDescription": "תיאור קצר בעברית של מה המשתמש ביקש לעשות",
  "capabilityTitle": "שם קצר ליכולת החסרה (עד 5 מילים)"
}`;

    try {
        const raw = await callGemma4(prompt, false, 200);
        const text = typeof raw === 'string' ? raw : (raw?.answer || raw?.content || JSON.stringify(raw));
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (!jsonMatch) return { isGap: false };
        const parsed = JSON.parse(jsonMatch[0]);
        return {
            isGap: parsed.isGap === true,
            actionDescription: parsed.actionDescription || '',
            capabilityTitle: parsed.capabilityTitle || '',
        };
    } catch {
        return { isGap: false };
    }
}

// ─── Claude prompt generation ─────────────────────────────────────────────────

function generateClaudePrompt(userMessage, gapDetails) {
    const { actionDescription, capabilityTitle } = gapDetails;

    return `## בקשת משתמש מקורית
"${userMessage}"

## מה צריך לבנות
${actionDescription}

יכולת חסרה: **${capabilityTitle}**

## קבצים לשינוי
- \`agents/router.js\` — הוספת intent חדש + מילות מפתח בעברית ב-KEYWORDS וב-VALID_INTENTS
- \`agents/[newAgent].js\` — agent חדש שמטפל בבקשה (חתימה: \`runXAgent(userMessage, supabase, useLocal, settings)\` → \`{ answer, action? }\`)
- \`server.js\` — import + case חדש ב-dispatch chain (שורות 553–622)

## Integration Points
- חתימת פונקציה: \`async function runXAgent(userMessage, supabase, useLocal, settings)\` → \`{ answer: string, action?: object }\`
- ניתוב: הוסף ל-\`VALID_INTENTS\` ול-\`LLM_CLASSIFY_PROMPT\` ב-router.js
- אם נדרש Supabase: הגדר טבלה חדשה ב-Supabase ועדכן README עם שם הטבלה
- אם נדרש API חיצוני: הוסף ל-.env.example את שמות המשתנים

## קובץ בדיקות
\`tests/unit/[newAgent].test.js\`

## קריטריוני קבלה
- המשתמש יכול לבקש "${capabilityTitle}" ולקבל תשובה מעשית
- הבקשה מנותבת נכון על-ידי router.js (keyword path ו-LLM fallback)
- קיים test unit בסיסי שמדמה את ה-agent`;
}

// ─── Confirmation flow ────────────────────────────────────────────────────────

const YES_PATTERN = /^(כן|אשר|בסדר|אוקי|יאללה|כן בבקשה|כן תשמור|שמור|תוסיף|הוסף)/i;
const NO_PATTERN  = /^(לא|בטל|לא צריך|לא עכשיו|דלג|תדלג)/i;

async function handleConfirmation(userMessage) {
    const pending = await loadPendingGap();
    if (!pending) return null;

    if (YES_PATTERN.test(userMessage.trim())) {
        const claudePrompt = generateClaudePrompt(pending.userRequest, pending.gapDetails);
        const saved = await saveDevTask({
            title: pending.gapDetails.capabilityTitle,
            userRequest: pending.userRequest,
            actionDescription: pending.gapDetails.actionDescription,
            claudePrompt,
        });
        await clearPendingGap();

        return {
            answer: [
                `✅ נוספה משימת פיתוח: **${saved.title}**`,
                '',
                '📋 **פרומפט לקלוד:**',
                '```',
                claudePrompt,
                '```',
            ].join('\n'),
            skipTts: true,
        };
    }

    if (NO_PATTERN.test(userMessage.trim())) {
        await clearPendingGap();
        return { answer: 'בסדר, לא שמרתי משימת פיתוח.' };
    }

    return null;
}

module.exports = {
    detectCapabilityGap,
    generateClaudePrompt,
    savePendingGap,
    loadPendingGap,
    clearPendingGap,
    saveDevTask,
    handleConfirmation,
    YES_PATTERN,
    NO_PATTERN,
};
