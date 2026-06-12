const { sanitizeLike, nowJerusalem, todayISODate, extractJSON } = require('./utils');
const { parseRecurrence, RECURRENCE_LABELS } = require('./reminderAgent');
require('dotenv').config();
const { callGemma4 } = require('./models');
const obsidianSync   = require('../services/obsidianSync');
const pinecone       = require('../services/pineconeMemory');

// ─── Date helpers (Jerusalem TZ) ─────────────────────────────────────────────
// nowJerusalem / todayISODate now live in ./utils (shared across agents).

function formatDate(isoDate) {
    if (!isoDate) return null;
    return new Date(isoDate).toLocaleDateString('he-IL', {
        timeZone: 'Asia/Jerusalem',
        weekday: 'long',
        day: 'numeric',
        month: 'long',
    });
}

// Advance a YYYY-MM-DD date by one recurrence interval. Returns YYYY-MM-DD.
// For recurring tasks with no stored due_date, advances from today.
function nextDueDate(isoDate, recurrence) {
    const base = isoDate ? new Date(`${isoDate}T00:00:00`) : nowJerusalem();
    if (recurrence === 'daily')   base.setDate(base.getDate() + 1);
    else if (recurrence === 'weekly')  base.setDate(base.getDate() + 7);
    else if (recurrence === 'monthly') base.setMonth(base.getMonth() + 1);
    else return null;
    return `${base.getFullYear()}-${String(base.getMonth() + 1).padStart(2, '0')}-${String(base.getDate()).padStart(2, '0')}`;
}

// ─── Category keyword classifier (fast path, no LLM call) ────────────────────

const CATEGORY_KEYWORDS = {
    work:      /פגישה|ישיבה|מייל|אימייל|דוח|דו"ח|לקוח|מנהל|עובד|עמית|משרד|עבודה|פרזנטציה|מצגת|קולגה|הגשה|ספק|שותף|גיוס|ראיון|משכורת|חוזה|הסכם|לקוחות|פרויקט עסקי/i,
    personal:  /רופא|רופאה|בריאות|משפחה|ילד|ילדה|חבר|חברה|ספורט|כושר|חדר כושר|אוכל|תזונה|טיול|חופשה|שיניים|תרופה|ביגוד|ניקיון|שטיפה|ביקור|יום הולדת|לימודים|קורס|אוניברסיטה|בית ספר/i,
    financial: /כסף|תשלום|חשבון|חוב|הלוואה|השקעה|מניה|ביטוח|מס|ארנונה|חשמל|גז|מים|ויזה|אשראי|בנק|קנייה|רכישה|תקציב|הוצאה|הכנסה|שכר דירה|משכנתא|פנסיה|קרן|ריבית/i,
    project:   /פרויקט|פרוייקט|אפליקציה|אפ|קוד|פיתוח|דיזיין|עיצוב|אתר|בסיס נתונים|מסד נתונים|API|שרת|מוצר|MVP|ספרינט|sprint|גיטהאב|github|פיצ'ר|feature|באג|bug|ריפקטור|deploy|배포|הרצה|CI/i,
};

const CATEGORY_META = {
    work:      { label: 'עבודה',   emoji: '💼' },
    personal:  { label: 'אישי',    emoji: '👤' },
    financial: { label: 'פיננסי',  emoji: '💰' },
    project:   { label: 'פרויקט', emoji: '🚀' },
    general:   { label: 'כללי',    emoji: '📌' },
};

function classifyCategory(text) {
    if (!text) return 'general';
    for (const [cat, rx] of Object.entries(CATEGORY_KEYWORDS)) {
        if (rx.test(text)) return cat;
    }
    return 'general';
}

// ─── LLM Prompt ───────────────────────────────────────────────────────────────

const TASK_PROMPT = (today) => `You are a task management AI. Analyze the Hebrew user message and extract the intent.
Allowed intents: 'add', 'list', 'delete', 'complete', 'suggest', 'today', 'recategorize'.
- 'add': user wants to create a new task
- 'complete': user says they finished/completed a task (e.g. סיימתי, עשיתי, השלמתי, סמן כבוצע)
- 'delete': user explicitly wants to remove a task without completing it
- 'list': user wants to see all tasks
- 'suggest': user asks for help or recommendations about tasks
- 'today': user asks what they have today or what's due today
- 'recategorize': user wants to change the category of an existing task (e.g. "תעביר את X לעבודה", "שנה את המשימה Y לפיננסי", "תסווג את Z כפרויקט")

Date parsing (today is ${today}):
- "מחר" → tomorrow's date
- "ביום שישי/שני/..." → next occurrence of that weekday
- "בשבוע הבא" → 7 days from today
- "ב-15" or "ב-15 לחודש" → 15th of current month (next month if already passed)
- "עוד X ימים" → X days from today

Priority rules:
- "דחוף", "חשוב מאוד", "עדיפות גבוהה", "ASAP" → "high"
- "חשוב", "בינוני", "עדיפות בינונית" → "medium"
- "לא דחוף", "נמוך", "כשיש זמן", "בזמן פנוי" → "low"

Recurrence rules — detect if the task repeats on a fixed interval:
- "כל יום", "יומי" → "daily"
- "כל שבוע", "שבועי", "כל יום ראשון/שני/..." → "weekly"
- "כל חודש", "חודשי" → "monthly"
- otherwise → null (one-time task)

Category rules — classify the task into ONE of: work, personal, financial, project, general:
- "work": meetings, emails, reports, clients, office, business tasks
- "personal": health, family, friends, sport, errands, education
- "financial": payments, bills, banking, investments, budget, insurance
- "project": coding, design, development, apps, software, product
- "general": everything else

For 'recategorize': put the task name (without the category word) in taskDetails, and the target category in category.

Return ONLY a JSON object (no explanation):
{"intent": "add|list|delete|complete|suggest|today|recategorize", "taskDetails": "task text or empty", "dueDate": "YYYY-MM-DD or null", "priority": "high|medium|low|null", "category": "work|personal|financial|project|general", "recurrence": "daily|weekly|monthly|null"}

User message: `;

async function runTaskAgent(userMessage, supabase, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';

    try {
        const today = todayISODate();
        const aiText = await callGemma4(TASK_PROMPT(today) + userMessage, useLocal);

        const parsed = extractJSON(aiText);
        if (!parsed) {
            return { answer: 'לא הצלחתי לעבד את הבקשה, נסה לנסח אחרת.' };
        }
        console.log('📋 TaskAgent:', parsed);

        if (parsed.intent === 'add') {
            if (!parsed.taskDetails || parsed.taskDetails.trim().length < 3) {
                return { answer: 'מה המשימה? תאר בקצרה מה צריך לעשות.' };
            }
            // Category: prefer LLM output; fall back to keyword classifier
            const validCats = new Set(['work', 'personal', 'financial', 'project', 'general']);
            const category = validCats.has(parsed.category)
                ? parsed.category
                : classifyCategory(parsed.taskDetails);

            // Recurrence: prefer LLM output; fall back to keyword detection.
            const validRec = new Set(['daily', 'weekly', 'monthly']);
            const recurrence = validRec.has(parsed.recurrence)
                ? parsed.recurrence
                : parseRecurrence(userMessage);

            const insertData = { content: parsed.taskDetails, category };
            if (parsed.dueDate) insertData.due_date = parsed.dueDate;
            if (parsed.priority && parsed.priority !== 'null') insertData.priority = parsed.priority;
            if (recurrence) insertData.recurrence = recurrence;

            // Graceful insert: drop optional columns that may not exist yet and retry.
            const { error: insertErr } = await supabase.from('tasks').insert([insertData]);
            if (insertErr) {
                if (/column "(category|recurrence)"/.test(insertErr.message || '')) {
                    const { category: _c, recurrence: _r, ...rowMinimal } = insertData;
                    await supabase.from('tasks').insert([rowMinimal]);
                } else {
                    console.error('TaskAgent insert error:', insertErr.message);
                }
            }
            obsidianSync.dbToVault('tasks', { content: parsed.taskDetails, category });

            const catMeta = CATEGORY_META[category] || CATEGORY_META.general;
            let answer = `מעולה ${userName}, הוספתי את המשימה: ${parsed.taskDetails}`;
            answer += `\n${catMeta.emoji} קטגוריה: ${catMeta.label}`;
            if (parsed.dueDate) {
                answer += `\n📅 תאריך יעד: ${formatDate(parsed.dueDate)}`;
            }
            if (parsed.priority === 'high') answer += '\n🔴 עדיפות: גבוהה';
            else if (parsed.priority === 'medium') answer += '\n🟡 עדיפות: בינונית';
            else if (parsed.priority === 'low') answer += '\n🟢 עדיפות: נמוכה';
            if (recurrence) answer += `\n🔁 חוזר: ${RECURRENCE_LABELS[recurrence]}`;

            if (parsed.dueDate) {
                answer += '\n\n💡 האם תרצה שאזכיר לך לפני? (כן / לא — אפשר גם "כן, שעתיים לפני")';
                return { answer, pendingAction: { type: 'auto_reminder', taskContent: parsed.taskDetails, dueDate: parsed.dueDate } };
            }

            return { answer, action: { type: 'navigate', target: 'tasks', label: 'פתח משימות' } };
        }

        if (parsed.intent === 'today') {
            const tomorrow = new Date(nowJerusalem());
            tomorrow.setDate(tomorrow.getDate() + 1);
            const tomorrowISO = `${tomorrow.getFullYear()}-${String(tomorrow.getMonth()+1).padStart(2,'0')}-${String(tomorrow.getDate()).padStart(2,'0')}`;

            const { data: todayTasks } = await supabase
                .from('tasks')
                .select('*')
                .eq('done', false)
                .lte('due_date', tomorrowISO)
                .order('due_date', { ascending: true });

            const { data: overdue } = await supabase
                .from('tasks')
                .select('*')
                .eq('done', false)
                .lt('due_date', today);

            const dueTodayItems = (todayTasks || []).filter(t => t.due_date === today);
            const dueTomorrow = (todayTasks || []).filter(t => t.due_date === tomorrowISO);
            const overdueItems = overdue || [];

            if (dueTodayItems.length === 0 && overdueItems.length === 0 && dueTomorrow.length === 0) {
                return { answer: `אין לך משימות דחופות להיום ${userName}! יום נקי 🎉` };
            }

            let answer = `📋 *המשימות שלך להיום:*\n`;

            if (overdueItems.length > 0) {
                answer += `\n🔴 *פג תוקף (${overdueItems.length}):*\n`;
                overdueItems.forEach((t, i) => {
                    answer += `${i + 1}. ${t.content}${t.due_date ? ` (היה ל-${formatDate(t.due_date)})` : ''}\n`;
                });
            }

            if (dueTodayItems.length > 0) {
                answer += `\n📅 *להיום (${dueTodayItems.length}):*\n`;
                dueTodayItems.forEach((t, i) => {
                    const prio = t.priority === 'high' ? ' 🔴' : t.priority === 'medium' ? ' 🟡' : '';
                    const catEmoji = (t.category && CATEGORY_META[t.category]) ? CATEGORY_META[t.category].emoji + ' ' : '';
                    answer += `${i + 1}. ${catEmoji}${t.content}${prio}\n`;
                });
            }

            if (dueTomorrow.length > 0) {
                answer += `\n📆 *מחר (${dueTomorrow.length}):*\n`;
                dueTomorrow.forEach((t, i) => { answer += `${i + 1}. ${t.content}\n`; });
            }

            return { answer };
        }

        if (parsed.intent === 'list') {
            const { data } = await supabase.from('tasks').select('*').order('due_date', { ascending: true, nullsFirst: false });
            if (!data || data.length === 0) return { answer: `אין לך משימות כרגע ${userName}, אתה חופשי. בואו נוצור משהו? 💡` };

            const pending = data.filter(t => !t.done);
            const completed = data.filter(t => t.done);

            let answer = `📋 *המשימות שלך (${pending.length} פתוחות, ${completed.length} בוצעו):*\n\n`;

            if (pending.length > 0) {
                // Group by category for better readability
                const grouped = {};
                pending.forEach(t => {
                    const cat = t.category && CATEGORY_META[t.category] ? t.category : 'general';
                    (grouped[cat] = grouped[cat] || []).push(t);
                });

                const catOrder = ['work', 'project', 'financial', 'personal', 'general'];
                const usedCats = catOrder.filter(c => grouped[c]);
                const hasCats = usedCats.some(c => c !== 'general') || (grouped.general?.length > 0 && usedCats.length > 1);

                if (hasCats) {
                    usedCats.forEach(cat => {
                        const meta = CATEGORY_META[cat];
                        answer += `*${meta.emoji} ${meta.label}:*\n`;
                        grouped[cat].forEach((t, i) => {
                            const prio = t.priority === 'high' ? ' 🔴' : t.priority === 'medium' ? ' 🟡' : '';
                            const due = t.due_date ? ` | 📅 ${formatDate(t.due_date)}` : '';
                            const rec = t.recurrence ? ' 🔁' : '';
                            answer += `  ${i + 1}. ${t.content}${prio}${rec}${due}\n`;
                        });
                        answer += '\n';
                    });
                } else {
                    pending.forEach((t, i) => {
                        const prio = t.priority === 'high' ? ' 🔴' : t.priority === 'medium' ? ' 🟡' : '';
                        const due = t.due_date ? ` | 📅 ${formatDate(t.due_date)}` : '';
                        const rec = t.recurrence ? ' 🔁' : '';
                        answer += `${i + 1}. ${t.content}${prio}${rec}${due}\n`;
                    });
                }
            }

            if (pending.length > 3) {
                answer += `💡 *הצעה:* אתה עם ${pending.length} משימות פתוחות. תרצה לסיים אחת מהן או להפריד לחלקים קטנים יותר?`;
            }

            return { answer };
        }

        if (parsed.intent === 'delete') {
            const { data: matches } = await supabase
                .from('tasks')
                .select('id, content')
                .ilike('content', `%${sanitizeLike(parsed.taskDetails)}%`);
            if (!matches || matches.length === 0) return { answer: 'לא מצאתי משימה כזו למחוק.' };
            if (matches.length > 1) {
                const list = matches.map((t, i) => `${i + 1}. ${t.content}`).join('\n');
                return { answer: `מצאתי ${matches.length} משימות תואמות. תוכל להיות יותר ספציפי?\n${list}` };
            }
            await supabase.from('tasks').delete().eq('id', matches[0].id);
            return { answer: `מחקתי את המשימה: ${matches[0].content}` };
        }

        if (parsed.intent === 'recategorize') {
            const validCats = new Set(['work', 'personal', 'financial', 'project', 'general']);
            const category = validCats.has(parsed.category) ? parsed.category : null;
            if (!category) {
                return { answer: 'לא הבנתי לאיזו קטגוריה להעביר. נסה: עבודה / אישי / פיננסי / פרויקט / כללי.' };
            }

            const { data: matches } = await supabase
                .from('tasks')
                .select('id, content')
                .ilike('content', `%${sanitizeLike(parsed.taskDetails)}%`)
                .eq('done', false);
            if (!matches || matches.length === 0) return { answer: 'לא מצאתי משימה כזו לעדכן.' };
            if (matches.length > 1) {
                const list = matches.map((t, i) => `${i + 1}. ${t.content}`).join('\n');
                return { answer: `מצאתי ${matches.length} משימות תואמות. על איזו מהן?\n${list}` };
            }

            const { error: updErr } = await supabase.from('tasks').update({ category }).eq('id', matches[0].id);
            const catMeta = CATEGORY_META[category];
            if (updErr) {
                if (/column "category"/.test(updErr.message || '')) {
                    return { answer: 'עמודת הקטגוריה עוד לא קיימת במסד הנתונים. הרץ את המיגרציה ונסה שוב.' };
                }
                console.error('TaskAgent recategorize error:', updErr.message);
                return { answer: 'הייתה בעיה בעדכון הקטגוריה, נסה שוב.' };
            }
            return { answer: `עדכנתי את "${matches[0].content}" ל${catMeta.emoji} ${catMeta.label}.` };
        }

        if (parsed.intent === 'complete') {
            const { data: matches } = await supabase
                .from('tasks')
                .select('id, content, category, priority, recurrence, due_date')
                .ilike('content', `%${sanitizeLike(parsed.taskDetails)}%`)
                .eq('done', false);
            if (!matches || matches.length === 0) return { answer: 'לא מצאתי משימה כזו. נסה לציין את שם המשימה.' };
            if (matches.length > 1) {
                const list = matches.map((t, i) => `${i + 1}. ${t.content}`).join('\n');
                return { answer: `מצאתי ${matches.length} משימות תואמות. על איזו מהן?\n${list}` };
            }

            const completed = matches[0];
            await supabase.from('tasks').update({ done: true }).eq('id', completed.id);

            // Recurring task: spawn the next occurrence with an advanced due date.
            let recurNote = '';
            if (completed.recurrence) {
                const nextDue = nextDueDate(completed.due_date, completed.recurrence);
                const nextRow = { content: completed.content, recurrence: completed.recurrence };
                if (completed.category) nextRow.category = completed.category;
                if (completed.priority) nextRow.priority = completed.priority;
                if (nextDue) nextRow.due_date = nextDue;
                const { error: recurErr } = await supabase.from('tasks').insert([nextRow]);
                if (!recurErr) {
                    recurNote = `\n\n🔁 משימה חוזרת (${RECURRENCE_LABELS[completed.recurrence]}) — יצרתי את המופע הבא${nextDue ? ` ל-${formatDate(nextDue)}` : ''}.`;
                }
            }

            const { data: remaining } = await supabase
                .from('tasks')
                .select('content, due_date')
                .eq('done', false)
                .limit(1);

            let nextSuggestion = '';
            if (remaining && remaining.length > 0) {
                nextSuggestion = `\n\n💡 *משימה הבאה:* ${remaining[0].content}`;
            }

            return { answer: `כל הכבוד ${userName}! סיימת את: "${completed.content}" ✓${recurNote}${nextSuggestion}` };
        }

        if (parsed.intent === 'suggest') {
            const { data } = await supabase.from('tasks').select('*').order('created_at', { ascending: false }).limit(5);

            if (!data || data.length === 0) {
                return { answer: `אין לך משימות כרגע ${userName}. יוצר משימה יכול לעזור לך לארגן את היום. מה אתה צריך לעשות?` };
            }

            const pending = data.filter(t => !t.done);
            let contextualHint = '';
            if (pinecone.isReady() && pending.length > 0) {
                try {
                    const relevantMemories = await pinecone.searchMemories(pending[0].content, 3);
                    if (relevantMemories && relevantMemories.length > 0) {
                        contextualHint = `\n• בהקשר קודם: ${relevantMemories[0]}`;
                    }
                } catch (_) {}
            }

            const timeBasedSuggestions = [
                'בוא נעבוד על משימה לפני שמתחיל הערב?',
                'יש לך זמן כדי לסיים משימה עכשיו?',
                'המשימה הזו לוקחת יותר מידי זמן - תרצה לפרק אותה?',
            ];
            const randomSuggestion = timeBasedSuggestions[Math.floor(Math.random() * timeBasedSuggestions.length)];

            return {
                answer: `💡 *הצעות חכמות:*\n` +
                    `• אתה עם ${pending.length} משימות פתוחות\n` +
                    `• ${randomSuggestion}\n` +
                    `• בואו נהפוך את זה לדברים קטנים יותר וקל יותר לעשות?${contextualHint}`
            };
        }

        return { answer: 'לא הכרתי את הכוונה. נסה: "הוסף משימה", "רשימת משימות", "מה יש לי היום", "מחק משימה", "סיימתי" או "תן לי הצעות".' };

    } catch (err) {
        console.error('TaskAgent Error:', err.message);
        const isDb = /supabase|PGRST/i.test(err.message || '');
        return {
            answer: isDb
                ? 'מסד הנתונים לא זמין — המשימה לא נשמרה. נסה שוב.'
                : 'הייתה בעיה בעיבוד המשימה, נסה לנסח אחרת.',
            suggestions: isDb ? ['נסה שוב'] : ['נסח מחדש'],
        };
    }
}

module.exports = { runTaskAgent, classifyCategory, CATEGORY_META };
