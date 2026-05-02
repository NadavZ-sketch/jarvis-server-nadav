// Local executor: turns an approved mission plan into actionable artefacts the
// user can pick up immediately, without needing any external execution agent.
//
// What it does on `run`:
//   1. Inserts each plan step into Supabase `tasks` (tagged with the mission
//      id in the task content so it shows up in the standard tasks list).
//   2. Generates a single Claude Code prompt for the whole mission via the
//      same LLM chain used by /dashboard/generate-prompt — stored on the
//      mission's executorState so the mobile screen can show a "copy prompt"
//      button.
//
// Step status is updated by /missions/:id/steps/:stepId — the user marks
// each step done from the Active Mission screen (or it can be triggered by
// other side-effects in the future).

const { callGemma4 } = require('../models');

function buildPromptForClaudeCode(mission) {
    const stepLines = (mission.plan || [])
        .map((s, i) => `${i + 1}. ${s.text}${s.why ? `  // ${s.why}` : ''}`)
        .join('\n');

    return `אתה מומחה בכתיבת הוראות מדויקות ל-Claude Code (עוזר הקוד של Anthropic).

הקשר פרויקט Jarvis:
- אפליקציית Flutter (ממשק עברית RTL) עם ORB קולי, צ'אט, משימות, תזכורות, פתקים, קניות, לוח שנה
- שרת Node.js (server.js) עם 17+ אייג'נטים בתיקיית agents/ (router.js, chatAgent.js, taskAgent.js וכו')
- Supabase כ-DB, Pinecone לזיכרון סמנטי, LLMs (Groq → DeepSeek → Gemini כ-fallback)
- קבצים מרכזיים: server.js, jarvis_mobile/lib/main.dart, agents/router.js, agents/models.js

משימה פעילה (mission #${mission.id}, מקור: ${mission.source}):
כותרת: ${mission.title}
מטרה: ${mission.goal || mission.origin}

תוכנית מאושרת:
${stepLines}

כתוב פרומפט מפורט ל-Claude Code שהמפתח יוכל להדביק ישירות כדי לממש את כל המשימה. הפרומפט צריך:
- להיות ישיר ומעשי ללא הקדמות — כאילו כותבים הוראות לעוזר קוד
- לציין קבצים ספציפיים לשינוי (עם נתיבים)
- לפרט שינויים בצד שרת ו/או Flutter לפי הצורך
- לכלול endpoints חדשים, widgets, schemas — כל מה שנחוץ למימוש מלא
- לסיים בהוראת בדיקה / וידוא

כתוב את הפרומפט בעברית, מוכן להדבקה ב-Claude Code:`;
}

async function run(mission, { supabase } = {}) {
    const out = { tasks: [], prompt: null, errors: [] };

    // Factory missions: actually build the agent rather than generate a
    // Claude Code prompt. The factory module does design → code → demo →
    // pending.json. The user then confirms via the mission chat ("כן").
    if (mission.source === 'factory') {
        try {
            const factory = require('../agentFactoryAgent');
            const result  = await factory.buildAgentFromMission(mission, supabase, false);
            out.factory = {
                agentName:   result.entry?.name || null,
                displayName: result.entry?.displayName || null,
                summary:     result.answer,
            };
            if (result.error) out.errors.push(result.error);
        } catch (e) {
            out.errors.push(`factory build failed: ${e.message}`);
        }
        // Mark all plan steps complete — the factory pipeline handled them
        // atomically. The user still needs to confirm the agent via chat.
        if (Array.isArray(mission.plan)) {
            out.completedSteps = mission.plan.map(s => s.id);
        }
        return out;
    }

    // 1. Insert plan steps as tasks (tagged with mission id in content)
    if (supabase && Array.isArray(mission.plan)) {
        for (const step of mission.plan) {
            try {
                const tag = `[משימה #${mission.id}] `;
                const content = `${tag}${step.text}`;
                const { data, error } = await supabase
                    .from('tasks')
                    .insert([{ content, done: false }])
                    .select()
                    .single();
                if (error) {
                    out.errors.push(`task insert failed for step ${step.id}: ${error.message}`);
                } else if (data) {
                    out.tasks.push({ stepId: step.id, taskId: data.id });
                }
            } catch (e) {
                out.errors.push(`task insert exception: ${e.message}`);
            }
        }
    }

    // 2. Generate the Claude Code prompt for the whole mission
    try {
        const promptText = await callGemma4(buildPromptForClaudeCode(mission), false, 1500);
        out.prompt = (promptText || '').trim();
    } catch (e) {
        out.errors.push(`prompt generation failed: ${e.message}`);
    }

    return out;
}

module.exports = { run };
