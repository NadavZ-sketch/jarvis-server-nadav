/*
 * Project Management Agent
 *
 * Required Supabase tables (run once in Supabase SQL editor):
 *
 *   CREATE TABLE IF NOT EXISTS projects (
 *     id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
 *     name        text NOT NULL,
 *     description text,
 *     status      text DEFAULT 'active'
 *                   CHECK (status IN ('active','paused','completed','archived')),
 *     priority    text DEFAULT 'medium'
 *                   CHECK (priority IN ('low','medium','high','critical')),
 *     start_date  date,
 *     due_date    date,
 *     color       text DEFAULT '#6366f1',
 *     created_at  timestamptz DEFAULT now(),
 *     updated_at  timestamptz DEFAULT now()
 *   );
 *
 *   CREATE TABLE IF NOT EXISTS project_milestones (
 *     id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
 *     project_id   uuid REFERENCES projects(id) ON DELETE CASCADE,
 *     title        text NOT NULL,
 *     due_date     date,
 *     completed    boolean DEFAULT false,
 *     completed_at timestamptz,
 *     created_at   timestamptz DEFAULT now()
 *   );
 *
 *   ALTER TABLE tasks      ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id) ON DELETE SET NULL;
 *   ALTER TABLE reminders  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id) ON DELETE SET NULL;
 *   ALTER TABLE notes      ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id) ON DELETE SET NULL;
 */

require('dotenv').config();
const { callGemma4 } = require('./models');

function nowJerusalem() {
    return new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
}

function todayISO() {
    const d = nowJerusalem();
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

function formatDate(iso) {
    if (!iso) return null;
    return new Date(iso).toLocaleDateString('he-IL', {
        timeZone: 'Asia/Jerusalem',
        day: 'numeric',
        month: 'long',
        year: 'numeric',
    });
}

const STATUS_LABELS = {
    active: '🟢 פעיל',
    paused: '⏸️ מושהה',
    completed: '✅ הושלם',
    archived: '📦 בארכיון',
};

const PRIORITY_LABELS = {
    low: '🟢 נמוכה',
    medium: '🟡 בינונית',
    high: '🔴 גבוהה',
    critical: '🚨 קריטית',
};

const PROJECT_PROMPT = `You are a project management AI for a Hebrew personal assistant. Analyze the Hebrew user message and extract the intent.

Allowed intents:
- 'create': user wants to create a new project
- 'list': user wants to see all projects or active projects
- 'view': user wants details/status of a specific project
- 'update': user wants to change project status, priority, or name
- 'delete': user wants to delete/remove a project
- 'add_task': user wants to add a task to a project
- 'add_milestone': user wants to add a milestone/checkpoint to a project
- 'complete_milestone': user wants to mark a milestone as done
- 'insight': user asks for AI analysis, tips, or progress insights
- 'briefing': user wants a full overview / morning briefing of all projects
- 'link_reminder': user wants to set a reminder for a project deadline
- 'plan_sprint': user wants to plan the next sprint, asks what tasks to put in the sprint
- 'detect_conflicts': user asks about scheduling conflicts, overlapping deadlines across projects

Priority rules:
- "דחוף", "קריטי", "ASAP" → "critical"
- "חשוב מאוד", "עדיפות גבוהה" → "high"
- "חשוב", "בינוני" → "medium"
- "לא דחוף", "נמוכה" → "low"

Status rules:
- "הושלם", "סיימתי", "סגור" → "completed"
- "השהה", "עצור", "פשז" → "paused"
- "ארכיון", "ארכב" → "archived"
- "הפעל", "המשך", "פתח" → "active"

Return ONLY a valid JSON object (no explanation):
{
  "intent": "...",
  "projectName": "project name or search term or empty string",
  "description": "project description or empty string",
  "status": "active|paused|completed|archived or null",
  "priority": "low|medium|high|critical or null",
  "dueDate": "YYYY-MM-DD or null",
  "startDate": "YYYY-MM-DD or null",
  "color": "#hex or null",
  "taskText": "task content if add_task, else empty string",
  "milestoneText": "milestone title if add/complete milestone, else empty string",
  "milestoneDue": "YYYY-MM-DD or null"
}

User message: `;

async function findProject(supabase, nameHint) {
    if (!nameHint) return null;
    const { data } = await supabase
        .from('projects')
        .select('*')
        .ilike('name', `%${nameHint.trim()}%`)
        .limit(5);
    return data || [];
}

async function computeProgress(supabase, projectId) {
    const [{ data: tasks }, { data: milestones }] = await Promise.all([
        supabase.from('tasks').select('done').eq('project_id', projectId),
        supabase.from('project_milestones').select('completed').eq('project_id', projectId),
    ]);

    const allItems = [...(tasks || []), ...(milestones || [])];
    if (allItems.length === 0) return 0;
    const done = allItems.filter(i => i.done || i.completed).length;
    return Math.round((done / allItems.length) * 100);
}

// Deterministic weekly briefing — builds a Hebrew summary of active projects
// with progress bars and deadline urgency. Makes NO LLM call (zero tokens).
// Shared by the projectAgent 'briefing' intent and the GET /projects/briefing endpoint.
async function buildProjectsBriefing(supabase, userName = 'נדב') {
    const { data: projects } = await supabase
        .from('projects')
        .select('*')
        .in('status', ['active', 'paused'])
        .order('priority', { ascending: false });

    if (!projects || projects.length === 0) {
        return { answer: `אין פרויקטים פעילים כרגע ${userName}. בוא ניצור אחד!` };
    }

    const today = new Date(todayISO());
    let answer = `📋 *ברייפינג פרויקטים — ${new Date().toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem', weekday: 'long', day: 'numeric', month: 'long' })}*\n\n`;

    for (const p of projects) {
        const progress = await computeProgress(supabase, p.id);
        const bar = '█'.repeat(Math.round(progress / 10)) + '░'.repeat(10 - Math.round(progress / 10));
        const daysLeft = p.due_date ? Math.ceil((new Date(p.due_date) - today) / 86400000) : null;
        const urgency = daysLeft !== null && daysLeft <= 3 ? ' 🚨' : daysLeft !== null && daysLeft <= 7 ? ' ⚠️' : '';

        answer += `*${p.name}*${urgency}\n`;
        answer += `${bar} ${progress}%`;
        if (daysLeft !== null) {
            answer += daysLeft < 0
                ? ` | ⚠️ חרג ב-${Math.abs(daysLeft)} ימים`
                : ` | עוד ${daysLeft} ימים`;
        }
        answer += `\n\n`;
    }

    return { answer, action: { type: 'navigate', target: 'projects', label: 'פתח פרויקטים' } };
}

async function runProjectAgent(userMessage, supabase, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';

    try {
        // Intent extraction returns a small fixed-shape JSON object; cap output
        // tokens to avoid the 800-token default on this high-frequency call.
        const aiText = await callGemma4(PROJECT_PROMPT + userMessage, useLocal, 200);

        const open = aiText.lastIndexOf('{');
        const close = aiText.lastIndexOf('}');
        if (open === -1 || close === -1) throw new Error('No JSON in projectAgent response');

        let parsed;
        try {
            parsed = JSON.parse(aiText.substring(open, close + 1));
        } catch {
            return { answer: 'לא הצלחתי לעבד את הבקשה, נסה לנסח אחרת.' };
        }

        console.log('📁 ProjectAgent:', parsed);
        const { intent } = parsed;

        // ── CREATE ──────────────────────────────────────────────────────────────
        if (intent === 'create') {
            if (!parsed.projectName) {
                return { answer: 'כדי ליצור פרויקט אני צריך שם. למשל: "צור פרויקט אפליקציה חדשה"' };
            }
            const insertData = {
                name: parsed.projectName,
                description: parsed.description || null,
                status: parsed.status || 'active',
                priority: parsed.priority || 'medium',
                start_date: parsed.startDate || todayISO(),
                due_date: parsed.dueDate || null,
                color: parsed.color || '#6366f1',
            };
            const { data: newProject, error } = await supabase
                .from('projects')
                .insert([insertData])
                .select()
                .single();

            if (error) throw error;

            let answer = `📁 יצרתי פרויקט חדש: *${parsed.projectName}*\n`;
            if (parsed.description) answer += `📝 ${parsed.description}\n`;
            answer += `📊 עדיפות: ${PRIORITY_LABELS[insertData.priority]}\n`;
            if (insertData.due_date) answer += `📅 תאריך יעד: ${formatDate(insertData.due_date)}\n`;
            answer += `\n💡 עכשיו אתה יכול להוסיף משימות ואבני דרך לפרויקט!`;

            return {
                answer,
                action: { type: 'navigate', target: 'projects', label: 'פתח פרויקטים', projectId: newProject?.id },
            };
        }

        // ── LIST ─────────────────────────────────────────────────────────────────
        if (intent === 'list') {
            const { data: projects } = await supabase
                .from('projects')
                .select('*')
                .not('status', 'eq', 'archived')
                .order('created_at', { ascending: false });

            if (!projects || projects.length === 0) {
                return { answer: `אין לך פרויקטים פעילים ${userName}. תרצה ליצור פרויקט חדש? פשוט תגיד "צור פרויקט [שם]"` };
            }

            const byStatus = { active: [], paused: [], completed: [] };
            for (const p of projects) {
                if (byStatus[p.status]) byStatus[p.status].push(p);
                else byStatus.active.push(p);
            }

            let answer = `📁 *הפרויקטים שלך (${projects.length}):*\n\n`;

            if (byStatus.active.length > 0) {
                answer += `*פעילים (${byStatus.active.length}):*\n`;
                for (const p of byStatus.active) {
                    const due = p.due_date ? ` | 📅 ${formatDate(p.due_date)}` : '';
                    const prio = PRIORITY_LABELS[p.priority] || '';
                    answer += `• ${p.name}${due} | ${prio}\n`;
                }
            }
            if (byStatus.paused.length > 0) {
                answer += `\n*מושהים (${byStatus.paused.length}):*\n`;
                byStatus.paused.forEach(p => { answer += `• ${p.name}\n`; });
            }
            if (byStatus.completed.length > 0) {
                answer += `\n*הושלמו (${byStatus.completed.length}):*\n`;
                byStatus.completed.forEach(p => { answer += `• ${p.name} ✅\n`; });
            }

            return { answer, action: { type: 'navigate', target: 'projects', label: 'פתח פרויקטים' } };
        }

        // ── VIEW ──────────────────────────────────────────────────────────────────
        if (intent === 'view') {
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) {
                return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}". תרצה לראות רשימת כל הפרויקטים?` };
            }
            if (matches.length > 1) {
                const list = matches.map((p, i) => `${i+1}. ${p.name}`).join('\n');
                return { answer: `מצאתי ${matches.length} פרויקטים תואמים:\n${list}\n\nעל איזה מהם?` };
            }

            const p = matches[0];
            const [{ data: milestones }, { data: tasks }] = await Promise.all([
                supabase.from('project_milestones').select('*').eq('project_id', p.id).order('due_date'),
                supabase.from('tasks').select('content,done,due_date').eq('project_id', p.id).order('created_at'),
            ]);

            const progress = await computeProgress(supabase, p.id);
            const progressBar = '█'.repeat(Math.round(progress / 10)) + '░'.repeat(10 - Math.round(progress / 10));

            let answer = `📁 *${p.name}*\n`;
            answer += `${STATUS_LABELS[p.status] || p.status} | ${PRIORITY_LABELS[p.priority] || p.priority}\n`;
            if (p.description) answer += `📝 ${p.description}\n`;
            answer += `\n📊 התקדמות: ${progressBar} ${progress}%\n`;
            if (p.due_date) answer += `📅 תאריך יעד: ${formatDate(p.due_date)}\n`;

            if (milestones && milestones.length > 0) {
                answer += `\n🏁 *אבני דרך (${milestones.filter(m => m.completed).length}/${milestones.length}):*\n`;
                milestones.forEach(m => {
                    const icon = m.completed ? '✅' : '⬜';
                    const due = m.due_date ? ` (${formatDate(m.due_date)})` : '';
                    answer += `${icon} ${m.title}${due}\n`;
                });
            }

            const openTasks = (tasks || []).filter(t => !t.done);
            const doneTasks = (tasks || []).filter(t => t.done);
            if (tasks && tasks.length > 0) {
                answer += `\n✅ *משימות (${doneTasks.length}/${tasks.length} הושלמו):*\n`;
                openTasks.slice(0, 5).forEach(t => { answer += `• ${t.content}\n`; });
                if (openTasks.length > 5) answer += `...ועוד ${openTasks.length - 5} משימות פתוחות\n`;
            }

            return { answer, action: { type: 'navigate', target: 'projects', label: 'פתח בדשבורד', projectId: p.id } };
        }

        // ── UPDATE ────────────────────────────────────────────────────────────────
        if (intent === 'update') {
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}".` };
            if (matches.length > 1) {
                const list = matches.map((p, i) => `${i+1}. ${p.name}`).join('\n');
                return { answer: `מצאתי ${matches.length} פרויקטים:\n${list}\n\nעל איזה מהם לעדכן?` };
            }

            const p = matches[0];
            const updates = { updated_at: new Date().toISOString() };
            if (parsed.status) updates.status = parsed.status;
            if (parsed.priority) updates.priority = parsed.priority;
            if (parsed.dueDate) updates.due_date = parsed.dueDate;
            if (parsed.description) updates.description = parsed.description;

            await supabase.from('projects').update(updates).eq('id', p.id);

            let answer = `✅ עדכנתי את הפרויקט *${p.name}*\n`;
            if (updates.status) answer += `• סטטוס: ${STATUS_LABELS[updates.status]}\n`;
            if (updates.priority) answer += `• עדיפות: ${PRIORITY_LABELS[updates.priority]}\n`;
            if (updates.due_date) answer += `• תאריך יעד: ${formatDate(updates.due_date)}\n`;

            return { answer };
        }

        // ── DELETE ────────────────────────────────────────────────────────────────
        if (intent === 'delete') {
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}".` };
            if (matches.length > 1) {
                const list = matches.map((p, i) => `${i+1}. ${p.name}`).join('\n');
                return { answer: `מצאתי ${matches.length} פרויקטים:\n${list}\n\nאיזה למחוק?` };
            }

            await supabase.from('projects').delete().eq('id', matches[0].id);
            return { answer: `🗑️ מחקתי את הפרויקט *${matches[0].name}* ואת כל אבני הדרך שלו.` };
        }

        // ── ADD TASK ──────────────────────────────────────────────────────────────
        if (intent === 'add_task') {
            if (!parsed.taskText) return { answer: 'מה המשימה שרוצה להוסיף לפרויקט?' };
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}".` };

            const p = matches[0];
            await supabase.from('tasks').insert([{
                content: parsed.taskText,
                project_id: p.id,
                priority: parsed.priority || 'medium',
                due_date: parsed.dueDate || null,
            }]);

            return { answer: `✅ הוספתי משימה לפרויקט *${p.name}*:\n• ${parsed.taskText}` };
        }

        // ── ADD MILESTONE ─────────────────────────────────────────────────────────
        if (intent === 'add_milestone') {
            if (!parsed.milestoneText) return { answer: 'מה אבן הדרך שרוצה להוסיף?' };
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}".` };

            const p = matches[0];
            await supabase.from('project_milestones').insert([{
                project_id: p.id,
                title: parsed.milestoneText,
                due_date: parsed.milestoneDue || null,
            }]);

            let answer = `🏁 הוספתי אבן דרך לפרויקט *${p.name}*:\n• ${parsed.milestoneText}`;
            if (parsed.milestoneDue) answer += `\n📅 תאריך: ${formatDate(parsed.milestoneDue)}`;
            return { answer };
        }

        // ── COMPLETE MILESTONE ────────────────────────────────────────────────────
        if (intent === 'complete_milestone') {
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}".` };

            const p = matches[0];
            const { data: milestones } = await supabase
                .from('project_milestones')
                .select('id, title')
                .eq('project_id', p.id)
                .eq('completed', false)
                .ilike('title', `%${parsed.milestoneText || ''}%`);

            if (!milestones || milestones.length === 0) {
                return { answer: 'לא מצאתי אבן דרך פתוחה כזו. אולי כבר הושלמה?' };
            }

            await supabase.from('project_milestones')
                .update({ completed: true, completed_at: new Date().toISOString() })
                .eq('id', milestones[0].id);

            const progress = await computeProgress(supabase, p.id);
            return { answer: `🏁 סיימת את אבן הדרך *${milestones[0].title}* בפרויקט ${p.name}!\n📊 התקדמות כוללת: ${progress}%` };
        }

        // ── INSIGHT ───────────────────────────────────────────────────────────────
        if (intent === 'insight') {
            const { data: projects } = await supabase
                .from('projects')
                .select('*')
                .eq('status', 'active');

            if (!projects || projects.length === 0) {
                return { answer: 'אין פרויקטים פעילים לנתח.' };
            }

            const projectsWithProgress = await Promise.all(
                projects.map(async p => {
                    const progress = await computeProgress(supabase, p.id);
                    return { ...p, progress };
                })
            );

            const today = new Date(todayISO());
            const overdue = projectsWithProgress.filter(p => p.due_date && new Date(p.due_date) < today && p.status === 'active');
            const nearDeadline = projectsWithProgress.filter(p => {
                if (!p.due_date || p.status !== 'active') return false;
                const days = Math.ceil((new Date(p.due_date) - today) / 86400000);
                return days >= 0 && days <= 7;
            });
            const slowProgress = projectsWithProgress.filter(p => p.progress < 30 && p.status === 'active');

            let answer = `💡 *תובנות על הפרויקטים שלך:*\n\n`;
            answer += `📊 סה"כ פרויקטים פעילים: ${projects.length}\n`;
            answer += `📈 ממוצע התקדמות: ${Math.round(projectsWithProgress.reduce((s, p) => s + p.progress, 0) / projects.length)}%\n\n`;

            if (overdue.length > 0) {
                answer += `🔴 *פרויקטים שחרגו מהתאריך:*\n`;
                overdue.forEach(p => { answer += `• ${p.name} (${formatDate(p.due_date)})\n`; });
                answer += '\n';
            }
            if (nearDeadline.length > 0) {
                answer += `⚠️ *דדליין בשבוע הקרוב:*\n`;
                nearDeadline.forEach(p => {
                    const days = Math.ceil((new Date(p.due_date) - today) / 86400000);
                    answer += `• ${p.name} — עוד ${days} ימים (${p.progress}% הושלם)\n`;
                });
                answer += '\n';
            }
            if (slowProgress.length > 0) {
                answer += `🐢 *התקדמות איטית (פחות מ-30%):*\n`;
                slowProgress.forEach(p => { answer += `• ${p.name} — ${p.progress}%\n`; });
                answer += '\n';
            }

            const best = [...projectsWithProgress].sort((a, b) => b.progress - a.progress)[0];
            if (best) answer += `🌟 *הפרויקט המתקדם ביותר:* ${best.name} (${best.progress}%)`;

            return { answer };
        }

        // ── BRIEFING ──────────────────────────────────────────────────────────────
        if (intent === 'briefing') {
            return await buildProjectsBriefing(supabase, userName);
        }

        // ── LINK REMINDER ─────────────────────────────────────────────────────────
        if (intent === 'link_reminder') {
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}".` };

            const p = matches[0];
            const reminderTime = parsed.dueDate
                ? `${parsed.dueDate}T09:00:00+03:00`
                : p.due_date ? `${p.due_date}T09:00:00+03:00` : null;

            if (!reminderTime) return { answer: 'לא מצאתי תאריך לתזכורת. ציין תאריך ספציפי.' };

            await supabase.from('reminders').insert([{
                text: `פרויקט "${p.name}" — בדוק התקדמות`,
                scheduled_time: reminderTime,
                project_id: p.id,
            }]);

            return { answer: `⏰ הגדרתי תזכורת לפרויקט *${p.name}* ב-${formatDate(parsed.dueDate || p.due_date)} בשעה 09:00` };
        }

        // ── PLAN SPRINT ───────────────────────────────────────────────────────
        if (intent === 'plan_sprint') {
            const matches = await findProject(supabase, parsed.projectName);
            if (!matches.length) return { answer: `לא מצאתי פרויקט בשם "${parsed.projectName}".` };
            const p = matches[0];

            const { data: backlog } = await supabase
                .from('tasks')
                .select('id, content, story_points, priority')
                .eq('project_id', p.id)
                .is('sprint_id', null)
                .eq('done', false);

            if (!backlog || backlog.length === 0) {
                return { answer: `הבאקלוג של פרויקט *${p.name}* ריק — אין משימות לספרינט.` };
            }

            const taskList = backlog.map(t => `- "${t.content}" (עדיפות: ${t.priority || 'medium'}, נקודות: ${t.story_points || '?'})`).join('\n');
            const sprintPrompt = `הבאקלוג של פרויקט "${p.name}":\n${taskList}\n\nתכנן ספרינט של 2 שבועות. אילו משימות לכלול? הצע מטרת ספרינט ואומדן נקודות לכל משימה. החזר JSON: {"goal":"...","tasks":[{"id":"...","content":"...","points":N}]}`;

            const raw = await callGemma4(sprintPrompt, useLocal, 600);
            const match = raw.match(/\{[\s\S]*\}/);
            let plan = null;
            if (match) { try { plan = JSON.parse(match[0]); } catch (_) {} }

            if (!plan) return { answer: 'לא הצלחתי לתכנן את הספרינט. נסה שוב.' };

            let answer = `📋 *תכנון ספרינט לפרויקט ${p.name}:*\n\n`;
            answer += `🎯 מטרה: ${plan.goal}\n\n`;
            answer += `📌 משימות מוצעות:\n`;
            (plan.tasks || []).forEach(t => { answer += `• ${t.content} — ${t.points} נקודות\n`; });

            return { answer };
        }

        // ── DETECT CONFLICTS ──────────────────────────────────────────────────
        if (intent === 'detect_conflicts') {
            const today = new Date(todayISO());
            const twoWeeksOut = new Date(today);
            twoWeeksOut.setDate(twoWeeksOut.getDate() + 14);

            const { data: upcomingTasks } = await supabase
                .from('tasks')
                .select('content, due_date, project_id')
                .not('due_date', 'is', null)
                .eq('done', false)
                .gte('due_date', todayISO())
                .lte('due_date', twoWeeksOut.toISOString().slice(0, 10));

            const { data: upcomingMilestones } = await supabase
                .from('project_milestones')
                .select('title, due_date, project_id')
                .not('due_date', 'is', null)
                .eq('completed', false)
                .gte('due_date', todayISO())
                .lte('due_date', twoWeeksOut.toISOString().slice(0, 10));

            const byDate = {};
            for (const t of (upcomingTasks || [])) {
                const d = t.due_date;
                if (!byDate[d]) byDate[d] = [];
                byDate[d].push(t.content);
            }
            for (const m of (upcomingMilestones || [])) {
                const d = m.due_date;
                if (!byDate[d]) byDate[d] = [];
                byDate[d].push(`🏁 ${m.title}`);
            }

            const conflicts = Object.entries(byDate)
                .filter(([, items]) => items.length >= 3)
                .sort(([a], [b]) => a.localeCompare(b));

            if (conflicts.length === 0) {
                return { answer: '✅ לא מצאתי קונפליקטים בלוח הזמנים לשבועיים הקרובים.' };
            }

            let answer = `⚠️ *קונפליקטים בלוח הזמנים — שבועיים קרובים:*\n\n`;
            for (const [date, items] of conflicts) {
                answer += `📅 ${formatDate(date)} (${items.length} דדליינים):\n`;
                items.forEach(i => { answer += `  • ${i}\n`; });
                answer += '\n';
            }
            answer += '💡 שקול לפזר חלק מהמשימות לתאריכים אחרים.';

            return { answer };
        }

        return { answer: 'לא הבנתי מה לעשות עם הפרויקט. נסה: "צור פרויקט", "הצג פרויקטים", "מה הסטטוס של פרויקט X", "הוסף משימה לפרויקט", "תובנות פרויקטים".' };

    } catch (err) {
        console.error('ProjectAgent Error:', err.message);
        return { answer: 'הייתה בעיה בעיבוד הבקשה, נסה שוב.' };
    }
}

module.exports = { runProjectAgent, buildProjectsBriefing };
