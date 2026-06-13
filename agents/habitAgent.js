const { nowJerusalem, todayISODate, extractJSON } = require('./utils');
require('dotenv').config();
const { callGemma4 } = require('./models');

// ── Supabase tables required (see migrations/20260606_create_habits.sql) ────────
//   habits      (id, name, schedule, active, created_at)
//   habit_logs  (id, habit_id, date, done, created_at)  UNIQUE(habit_id, date)
// ───────────────────────────────────────────────────────────────────────────────

const HABIT_PROMPT = (today) => `You are a habit-tracking AI for a Hebrew personal assistant. Analyze the user message and extract the intent.
Allowed intents: 'add', 'log', 'status', 'list', 'delete'.
- 'add': user wants to start tracking a new habit (e.g. "אני רוצה להתחיל לעקוב אחרי שתיית מים", "תוסיף הרגל ריצה כל בוקר")
- 'log': user reports they did a habit today (e.g. "התאמנתי היום", "שתיתי מים", "עשיתי מדיטציה")
- 'status': user asks about a habit's streak/progress (e.g. "מה הרצף שלי בריצה?", "כמה ימים ברצף התאמנתי?")
- 'list': user wants to see all tracked habits (e.g. "מה ההרגלים שלי", "הצג הרגלים")
- 'delete': user wants to stop tracking a habit (e.g. "תפסיק לעקוב אחרי ריצה", "מחק הרגל מדיטציה")

For 'add': put the habit name in habitName, and optional schedule ('daily'|'weekly'|'monthly') in schedule (default 'daily').
For 'log', 'status', 'delete': put the habit name (or best guess) in habitName.

Today is ${today}.

Return ONLY a JSON object (no explanation):
{"intent": "add|log|status|list|delete", "habitName": "habit name or empty", "schedule": "daily|weekly|monthly"}

User message: `;

// Count consecutive days (ending today or yesterday) that have a completed log.
function computeStreak(logDates) {
    const set = new Set(logDates);
    let streak = 0;
    const cursor = nowJerusalem();
    cursor.setHours(0, 0, 0, 0);

    const iso = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

    // Allow the streak to be "alive" if today isn't logged yet but yesterday is.
    if (!set.has(iso(cursor))) cursor.setDate(cursor.getDate() - 1);

    while (set.has(iso(cursor))) {
        streak++;
        cursor.setDate(cursor.getDate() - 1);
    }
    return streak;
}

async function findHabit(habits, nameHint) {
    const data = await habits.findActiveByName(nameHint);
    return (data && data.length) ? data : null;
}

async function runHabitAgent(userMessage, repos, useLocal = true, settings = {}) {
    const userName = settings.userName || 'נדב';
    const habitsRepo = repos.habits;

    try {
        const today = todayISODate();
        const aiText = await callGemma4(HABIT_PROMPT(today) + userMessage, useLocal, 150);
        const parsed = extractJSON(aiText);
        if (!parsed) return { answer: 'לא הצלחתי להבין את הבקשה לגבי ההרגל, נסה לנסח אחרת.' };
        console.log('🔁 HabitAgent:', parsed);

        if (parsed.intent === 'add') {
            const name = (parsed.habitName || '').trim();
            if (!name) return { answer: 'איזה הרגל תרצה להתחיל לעקוב אחריו?' };
            const validSched = new Set(['daily', 'weekly', 'monthly']);
            const schedule = validSched.has(parsed.schedule) ? parsed.schedule : 'daily';

            const { error } = await habitsRepo.add({ name, schedule });
            if (error) {
                console.error('HabitAgent insert error:', error.message);
                return { answer: 'הייתה בעיה בשמירת ההרגל. ודא שהטבלה קיימת ונסה שוב.' };
            }
            const schedLabel = schedule === 'daily' ? 'יומי' : schedule === 'weekly' ? 'שבועי' : 'חודשי';
            return {
                answer: `💪 מעולה ${userName}! התחלתי לעקוב אחרי ההרגל "${name}" (${schedLabel}). דווח לי כל פעם שתעשה אותו ואני אספור לך את הרצף.`,
                action: { type: 'navigate', target: 'habits', label: 'פתח הרגלים' },
            };
        }

        if (parsed.intent === 'log') {
            const matches = await findHabit(habitsRepo, parsed.habitName);
            if (!matches) return { answer: 'לא מצאתי הרגל כזה. תרצה שאתחיל לעקוב אחריו? אמור "תוסיף הרגל ..."' };
            if (matches.length > 1) {
                const list = matches.map((h, i) => `${i + 1}. ${h.name}`).join('\n');
                return { answer: `על איזה הרגל מדובר?\n${list}` };
            }
            const habit = matches[0];

            // Upsert today's log (UNIQUE habit_id+date keeps it idempotent).
            const { error } = await habitsRepo.logToday(habit.id, today);
            if (error) console.error('HabitAgent log error:', error.message);

            const streak = computeStreak(await habitsRepo.doneDates(habit.id));
            const fire = streak >= 3 ? ' 🔥' : '';
            return { answer: `✅ רשמתי "${habit.name}" להיום. הרצף שלך: ${streak} ימים${fire}. כל הכבוד ${userName}!` };
        }

        if (parsed.intent === 'status') {
            const matches = await findHabit(habitsRepo, parsed.habitName);
            if (!matches) return { answer: 'לא מצאתי הרגל כזה. אמור "מה ההרגלים שלי" כדי לראות את כולם.' };
            const habit = matches[0];
            const dates = await habitsRepo.doneDates(habit.id);
            const streak = computeStreak(dates);
            const fire = streak >= 3 ? ' 🔥' : '';
            return { answer: `📊 "${habit.name}": רצף נוכחי ${streak} ימים${fire}, סה"כ ${dates.length} ימים שתועדו.` };
        }

        if (parsed.intent === 'list') {
            const habits = await habitsRepo.listActive();
            if (!habits || habits.length === 0) {
                return { answer: `אין לך הרגלים במעקב כרגע ${userName}. אמור "תוסיף הרגל ..." כדי להתחיל.` };
            }
            const lines = [];
            for (const h of habits) {
                const streak = computeStreak(await habitsRepo.doneDates(h.id));
                const fire = streak >= 3 ? ' 🔥' : '';
                lines.push(`• ${h.name} — רצף ${streak} ימים${fire}`);
            }
            return { answer: `🔁 *ההרגלים שלך:*\n${lines.join('\n')}` };
        }

        if (parsed.intent === 'delete') {
            const matches = await findHabit(habitsRepo, parsed.habitName);
            if (!matches) return { answer: 'לא מצאתי הרגל כזה למחוק.' };
            if (matches.length > 1) {
                const list = matches.map((h, i) => `${i + 1}. ${h.name}`).join('\n');
                return { answer: `איזה הרגל להפסיק לעקוב?\n${list}` };
            }
            await habitsRepo.deactivate(matches[0].id);
            return { answer: `הפסקתי לעקוב אחרי ההרגל "${matches[0].name}".` };
        }

        return { answer: 'לא הבנתי. נסה: "תוסיף הרגל ריצה", "התאמנתי היום", "מה הרצף שלי", או "מה ההרגלים שלי".' };
    } catch (err) {
        console.error('HabitAgent Error:', err.message);
        return { answer: 'הייתה בעיה בעיבוד בקשת ההרגל, נסה שוב.' };
    }
}

module.exports = { runHabitAgent, computeStreak };
