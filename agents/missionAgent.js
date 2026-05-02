// Mission orchestrator: drives a mission through clarifying → planning →
// awaiting_approval → executing → done. The same flow serves AI proposals,
// manual backlog items, and "create an agent" requests.
//
// Each user message hitting POST /missions/:id/message is routed through
// runMissionTurn, which inspects current state and decides:
//   - ask the next clarifying question, OR
//   - emit the structured plan and flip to awaiting_approval, OR
//   - acknowledge feedback during execution.

require('dotenv').config();
const { callGemma4 } = require('./models');
const store          = require('../missionStore');

// ─── System-prompt fragments ──────────────────────────────────────────────────

function sourceLabel(source) {
    switch (source) {
        case 'proposal': return 'הצעה אוטומטית מ-Backlog AI';
        case 'manual':   return 'פריט שהמשתמש הוסיף ידנית';
        case 'factory':  return 'בקשה ליצור אייג\'נט חדש';
        default:         return 'משימה';
    }
}

function factoryClarifyHints() {
    return [
        'אם הבקשה היא ליצור אייג\'נט חדש, חובה לוודא לפני התוכנית את הפרטים הבאים:',
        '• שם תפקידי קצר (במה האייג\'נט מתמחה)',
        '• מילות מפתח / triggers שיפעילו אותו ("רשימת קריאה", "סטטוס מכונית")',
        '• מקורות מידע: API חיצוני, DB מקומי, חישוב פנימי, או רק טקסט מ-LLM',
        '• היקף: אישי לנדב או גם למשתמשים אחרים בעתיד',
        '• דוגמת שימוש אחת לפחות (כיצד נדב יבקש ממנו דבר)',
    ].join('\n');
}

function buildClarifyPrompt(mission) {
    const convo = (mission.conversation || []).map(m =>
        `${m.role === 'user' ? 'נדב' : 'Jarvis'}: ${m.text}`
    ).join('\n') || '(עדיין אין שיחה)';

    const factoryHints = mission.source === 'factory' ? '\n' + factoryClarifyHints() + '\n' : '';

    return `אתה Jarvis, עוזר אישי בעברית. אתה מנהל "משימה פעילה" — תהליך מובנה של בירור → תכנון → אישור → ביצוע.

מקור המשימה: ${sourceLabel(mission.source)}
כותרת: ${mission.title || '(לא מוגדרת)'}
תיאור מקורי: ${mission.origin || '(לא מוגדר)'}
${factoryHints}
מצב נוכחי: בירור (clarifying)

שיחה עד כה:
${convo}

המטרה שלך עכשיו:
1. אם חסרים פרטים קריטיים להגדרת תוכנית — שאל שאלת בירור אחת ממוקדת בלבד (משפט אחד, בעברית טבעית).
2. אם יש מספיק מידע כדי לגבש מטרה ותוכנית — החזר במקום זאת את ה-tag הבא בלבד: <READY_TO_PLAN/>

חוקים:
- שאלה אחת בלבד בכל הודעה. אל תשאל סדרת שאלות.
- אל תכתוב תוכנית או שלבים בשלב הזה — רק שאלת בירור או ה-tag.
- היה ידידותי, ישיר, ובלי הקדמות.
- אל תחזור על שאלות שכבר נענו בשיחה.

ההודעה הבאה שלך:`;
}

function buildPlanPrompt(mission) {
    const convo = (mission.conversation || []).map(m =>
        `${m.role === 'user' ? 'נדב' : 'Jarvis'}: ${m.text}`
    ).join('\n') || '(אין שיחה)';

    const factoryHint = mission.source === 'factory'
        ? '\nהמשימה היא יצירת אייג\'נט. תוכנית טובה כוללת: עיצוב הספק (שם/תכלית/triggers), כתיבת קוד הבסיס, הרצת דמו, הצגה לאישור והוספה ל-registry.\n'
        : '';

    return `אתה Jarvis. נדב סיים את שלב הבירור על משימה פעילה. עכשיו תתכנן.

מקור המשימה: ${sourceLabel(mission.source)}
כותרת: ${mission.title || '(לא מוגדרת)'}
תיאור מקורי: ${mission.origin}
${factoryHint}
שיחת הבירור:
${convo}

החזר JSON תקני בלבד (ללא markdown, ללא הסבר):
{
  "goal": "משפט אחד שמסכם את המטרה הסופית בעברית",
  "steps": [
    { "text": "תיאור שלב מעשי בעברית, פעולה אחת בכל שלב", "why": "למה השלב הזה חשוב, משפט קצר" }
  ]
}

חוקים:
- 3 עד 7 שלבים. לא פחות, לא יותר.
- כל שלב בר-ביצוע: פעולה ספציפית, לא הכרזה כללית.
- העדף שלבים שניתנים לסימון "בוצע" עצמאית.
- אל תכלול שלב "הצגה לאישור" — האישור מטופל אוטומטית במערכת.

JSON:`;
}

function buildExecutionAckPrompt(mission, userMessage) {
    const convo = (mission.conversation || []).slice(-6).map(m =>
        `${m.role === 'user' ? 'נדב' : 'Jarvis'}: ${m.text}`
    ).join('\n');

    const stepsRemaining = (mission.plan || [])
        .filter(s => s.status !== 'done')
        .map((s, i) => `${i + 1}. ${s.text}`)
        .join('\n') || '(כל השלבים בוצעו)';

    return `אתה Jarvis. אתה כרגע באמצע ביצוע משימה פעילה: "${mission.title}".

מטרה: ${mission.goal || mission.origin}

שלבים שנותרו:
${stepsRemaining}

שיחה אחרונה:
${convo}
נדב: ${userMessage}

ענה בקצרה (1-3 משפטים בעברית). אם נדב מבקש שינוי בתוכנית — הסכם ותציין שעודכן. אם הוא מבקש סטטוס — תן עדכון תמציתי. אל תפרט מחדש את כל התוכנית.`;
}

// ─── Main turn handler ────────────────────────────────────────────────────────

async function runMissionTurn(missionId, userMessage, settings = {}) {
    const useLocal = settings.useLocalModel === true;
    let mission = store.getMission(missionId);
    if (!mission) return { error: 'mission not found' };

    // Append user message first so it's part of context
    if (userMessage && userMessage.trim()) {
        mission = store.appendMessage(missionId, 'user', userMessage.trim());
    }

    // Cancelled / done missions don't generate further turns
    if (['done', 'cancelled'].includes(mission.status)) {
        return { mission, jarvisReply: null };
    }

    if (mission.status === 'clarifying') {
        const reply = await callGemma4(buildClarifyPrompt(mission), useLocal);
        const text  = (reply || '').trim();

        if (/<READY_TO_PLAN\s*\/?>/i.test(text)) {
            // Transition straight to planning
            mission = store.updateMission(missionId, { status: 'planning' });
            return planMission(missionId, settings);
        }

        // Strip any accidental tag fragments
        const cleaned = text.replace(/<READY_TO_PLAN\s*\/?>/gi, '').trim()
            || 'איזה פרט נוסף תרצה שאתחשב בו?';
        mission = store.appendMessage(missionId, 'jarvis', cleaned);
        return { mission, jarvisReply: cleaned };
    }

    if (mission.status === 'planning') {
        // User sent a message while we're regenerating; treat as extra clarification
        return planMission(missionId, settings);
    }

    if (mission.status === 'awaiting_approval') {
        // User typed a message instead of pressing approve/regenerate.
        // Treat it as feedback and bounce back to clarifying so Jarvis can refine.
        mission = store.updateMission(missionId, { status: 'clarifying' });
        const ack = 'הבנתי, נחזור לשלב הבירור כדי לדייק את התוכנית.';
        mission = store.appendMessage(missionId, 'jarvis', ack);
        return { mission, jarvisReply: ack };
    }

    // executing | paused — free-form ack
    const reply = await callGemma4(buildExecutionAckPrompt(mission, userMessage || ''), useLocal);
    const cleaned = (reply || 'קיבלתי.').trim();
    mission = store.appendMessage(missionId, 'jarvis', cleaned);
    return { mission, jarvisReply: cleaned };
}

// ─── Plan generation (called when transitioning to awaiting_approval) ────────

async function planMission(missionId, settings = {}) {
    const useLocal = settings.useLocalModel === true;
    let mission = store.getMission(missionId);
    if (!mission) return { error: 'mission not found' };

    const raw = await callGemma4(buildPlanPrompt(mission), useLocal);
    const match = (raw || '').match(/\{[\s\S]*"goal"[\s\S]*"steps"[\s\S]*\}/);

    if (!match) {
        const fallback = 'לא הצלחתי לגבש תוכנית. תוכל לתאר שוב בקצרה את המטרה?';
        mission = store.updateMission(missionId, { status: 'clarifying' });
        mission = store.appendMessage(missionId, 'jarvis', fallback);
        return { mission, jarvisReply: fallback };
    }

    let parsed;
    try { parsed = JSON.parse(match[0]); }
    catch {
        const fallback = 'התוכנית שלי הגיעה בפורמט לא תקין. בוא ננסה שוב — מהי המטרה הסופית במשפט אחד?';
        mission = store.updateMission(missionId, { status: 'clarifying' });
        mission = store.appendMessage(missionId, 'jarvis', fallback);
        return { mission, jarvisReply: fallback };
    }

    const goal  = String(parsed.goal || '').trim() || mission.title;
    const steps = Array.isArray(parsed.steps) ? parsed.steps : [];
    if (steps.length === 0) {
        const fallback = 'לא הצלחתי לפרק את המשימה לשלבים. תרצה לתאר שוב מה התוצאה הרצויה?';
        mission = store.updateMission(missionId, { status: 'clarifying' });
        mission = store.appendMessage(missionId, 'jarvis', fallback);
        return { mission, jarvisReply: fallback };
    }

    mission = store.setPlan(missionId, steps, goal);
    mission = store.updateMission(missionId, { status: 'awaiting_approval' });

    const stepsList = mission.plan.map((s, i) => `${i + 1}. ${s.text}`).join('\n');
    const summary = [
        `🎯 **המטרה:** ${mission.goal}`,
        '',
        '📋 **התוכנית שלי:**',
        stepsList,
        '',
        'אם זה נראה לך — אשר ואני מתחיל. אם תרצה לדייק — תכתוב לי מה לשנות.',
    ].join('\n');
    mission = store.appendMessage(missionId, 'jarvis', summary);
    return { mission, jarvisReply: summary };
}

// ─── Initial seed: generate Jarvis's opening clarifying question ─────────────
// Called immediately after createMission so the user lands in chat with content.

async function seedMission(missionId, settings = {}) {
    const useLocal = settings.useLocalModel === true;
    let mission = store.getMission(missionId);
    if (!mission) return { error: 'mission not found' };
    if (mission.conversation && mission.conversation.length > 0) {
        return { mission, jarvisReply: null };  // already seeded
    }

    const reply = await callGemma4(buildClarifyPrompt(mission), useLocal);
    const text  = (reply || '').trim();

    if (/<READY_TO_PLAN\s*\/?>/i.test(text)) {
        // Rare: model thinks it has enough already from origin. Skip clarify.
        mission = store.updateMission(missionId, { status: 'planning' });
        return planMission(missionId, settings);
    }

    const cleaned = text.replace(/<READY_TO_PLAN\s*\/?>/gi, '').trim()
        || `בוא נתחיל. ${mission.origin ? `הבנתי ש"${mission.origin}". ` : ''}איזה פרט מרכזי חשוב לך שאתחשב בו?`;
    mission = store.appendMessage(missionId, 'jarvis', cleaned);
    return { mission, jarvisReply: cleaned };
}

module.exports = { runMissionTurn, planMission, seedMission };
