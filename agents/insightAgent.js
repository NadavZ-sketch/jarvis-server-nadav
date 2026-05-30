require('dotenv').config();
const { callGemma4 } = require('./models');
const { runManusTask, isManusConfigured } = require('./manusAgent');

const BUCKET_LABELS = { morning: 'בוקר (06-12)', afternoon: 'צהריים (12-17)', evening: 'ערב (17-22)', night: 'לילה (22-06)' };

// ─── Pattern analysis (pure JS, no LLM) ──────────────────────────────────────

function analyzePatterns(data) {
    const userMsgs = data.chats.filter(c => c.role === 'user');

    // Time-of-day distribution (Jerusalem offset: UTC+3)
    const buckets = { morning: 0, afternoon: 0, evening: 0, night: 0 };
    userMsgs.forEach(m => {
        if (!m.created_at) return;
        const h = (new Date(m.created_at).getUTCHours() + 3) % 24;
        if      (h >= 6  && h < 12) buckets.morning++;
        else if (h >= 12 && h < 17) buckets.afternoon++;
        else if (h >= 17 && h < 22) buckets.evening++;
        else                         buckets.night++;
    });

    // Feature usage detection
    const featurePatterns = {
        'משימות':           /משימ|הוסף|מחק.*משימ|רשימ/i,
        'תזכורות':          /תזכיר|תזכורת/i,
        'כדורגל / ספורט':  /כדורגל|פרמייר|שחקן|ליג/i,
        'שליחת הודעות':    /שלח|ווצאפ|מייל ל/i,
        'ניסוח טקסטים':    /נסח|כתוב לי|עזור לכתוב/i,
        'שמירת זיכרונות':  /זכור ש|שמור ש|תזכור ש/i,
        'שיחה כללית':      /.+/,  // catch-all, counted last
    };

    const featureUsage = {};
    userMsgs.forEach(m => {
        const text = m.text || '';
        let matched = false;
        for (const [feat, pat] of Object.entries(featurePatterns)) {
            if (feat !== 'שיחה כללית' && pat.test(text)) {
                featureUsage[feat] = (featureUsage[feat] || 0) + 1;
                matched = true;
                break;
            }
        }
        if (!matched) featureUsage['שיחה כללית'] = (featureUsage['שיחה כללית'] || 0) + 1;
    });

    // Peak bucket
    const peakBucket = Object.entries(buckets).sort((a, b) => b[1] - a[1])[0][0];

    // Top features (excluding catch-all for display)
    const topFeatures = Object.entries(featureUsage)
        .filter(([f]) => f !== 'שיחה כללית')
        .sort((a, b) => b[1] - a[1])
        .slice(0, 4)
        .map(([f, n]) => `${f} (${n} פעמים)`);

    return {
        totalMessages:    userMsgs.length,
        buckets,
        peakBucket,
        featureUsage,
        topFeatures,
        pendingTasks:     data.tasks.length,
        memoriesCount:    data.memories.length,
        contactsCount:    data.contacts.length,
        firedReminders:   data.reminders.filter(r => r.fired).length,
        activeReminders:  data.reminders.filter(r => !r.fired).length,
        recentSample:     userMsgs.slice(0, 12).map(m => (m.text || '').slice(0, 100)),
    };
}

// ─── LLM prompt ───────────────────────────────────────────────────────────────

function buildInsightPrompt(analysis, memoriesText, userName) {
    // Detect clearly unused features to highlight in tips
    const unused = [];
    if (!analysis.featureUsage['ניסוח טקסטים'])   unused.push('ניסוח הודעות בסגנון שלך ("נסח לי...")');
    if (!analysis.featureUsage['שמירת זיכרונות'])  unused.push('שמירת עובדות אישיות ("זכור ש...")');
    if (!analysis.featureUsage['שליחת הודעות'])    unused.push('שליחת WhatsApp/מייל ישירות מג\'רביס');
    if (analysis.contactsCount === 0)               unused.push('שמירת אנשי קשר לשליחה מהירה');
    unused.push('ניתוח תמונות — שלח תמונה עם שאלה');
    unused.push('יצירת אייג\'נטים מותאמים ("צור לי אייג\'נט ש...")');

    const bucketsStr = Object.entries(analysis.buckets)
        .filter(([, n]) => n > 0)
        .map(([b, n]) => `${BUCKET_LABELS[b]}: ${n} הודעות`)
        .join(' | ');

    return `אתה יועץ פרודוקטיביות אישי חכם. נתח את נתוני השימוש הבאים של ${userName} ב-Jarvis ותן תובנות מעשיות.

═══ נתוני שימוש אמיתיים ═══
סה"כ הודעות שנשלחו: ${analysis.totalMessages}
פעילות לפי שעות: ${bucketsStr || 'אין נתוני זמן'}
זמן שיא: ${BUCKET_LABELS[analysis.peakBucket] || '—'}
נושאים עיקריים: ${analysis.topFeatures.join(', ') || 'שיחה כללית בלבד'}
משימות ממתינות ברשימה: ${analysis.pendingTasks}
זיכרונות שמורים על ${userName}: ${analysis.memoriesCount}
אנשי קשר שמורים: ${analysis.contactsCount}
תזכורות שהופעלו: ${analysis.firedReminders} | פעילות כעת: ${analysis.activeReminders}

═══ דוגמאות מ-12 ההודעות האחרונות ═══
${analysis.recentSample.map((m, i) => `${i + 1}. "${m}"`).join('\n') || 'אין היסטוריה'}

═══ מה ש-Jarvis יודע על ${userName} ═══
${memoriesText}

═══ יכולות שנראה שלא בשימוש ═══
${unused.map(u => `• ${u}`).join('\n')}

══════════════════════════════

כתוב תשובה בעברית בלבד, בשני חלקים מובנים:

**חלק א — תובנות על ההתנהלות שלך (3-4 תובנות):**
התייחס לנתונים האמיתיים: מתי ${userName} הכי פעיל, מה הוא עושה הרבה, מה אפשר לשפר בשגרת היום, האם יש backlog של משימות שצובר...
היה ספציפי ואישי — לא תובנות גנריות.

**חלק ב — 3-4 טיפים ל-Jarvis שכדאי לנסות:**
לכל טיפ: שם הפיצ'ר, משפט הסבר, ודוגמה בדיוק איך לכתוב.
בחר רק את הטיפים הרלוונטיים ביותר ל${userName} לפי הנתונים.`;
}

function profileSuggestions(profile) {
    if (!profile) return '';
    return `
═══ פרופיל משתמש (להתאמה אישית) ═══
טון דיבור מועדף: ${profile.speaking_tone || 'friendly'}
שעות מועדפות: ${(profile.preferred_hours || []).join(', ') || 'לא הוגדר'}
תחומי עניין: ${(profile.interests || []).join(', ') || 'לא הוגדר'}
משימות חוזרות: ${(profile.recurring_tasks || []).join(', ') || 'לא הוגדר'}
`;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function runInsightAgent(userMessage, supabase, useLocal, settings = {}) {
    const userName = settings.userName || 'נדב';

    try {
        console.log('🔍 InsightAgent: fetching usage data...');

        // 1. Fetch all tables in parallel
        const [chatsRes, tasksRes, memoriesRes, remindersRes, contactsRes] = await Promise.all([
            supabase.from('chat_history').select('role,text,created_at').order('created_at', { ascending: false }).limit(200),
            supabase.from('tasks').select('content,created_at'),
            supabase.from('memories').select('content'),
            supabase.from('reminders').select('text,scheduled_time,fired').limit(50),
            supabase.from('contacts').select('name'),
        ]);

        // Fail only if the two critical tables are unreachable
        if (chatsRes.error || memoriesRes.error) {
            return { answer: 'לא הצלחתי לגשת לנתונים. בדוק את חיבור Supabase.' };
        }

        const data = {
            chats:     chatsRes.data     || [],
            tasks:     tasksRes.data     || [],
            memories:  memoriesRes.data  || [],
            reminders: remindersRes.data || [],
            contacts:  contactsRes.data  || [],
        };

        // 2. Analyze patterns (pure JS)
        const analysis = analyzePatterns(data);
        console.log(`🔍 InsightAgent: ${analysis.totalMessages} messages analyzed`);

        if (analysis.totalMessages < 3) {
            return {
                answer: `עדיין אין מספיק היסטוריה כדי לנתח דפוסים, ${userName}.\nהשתמש ב-Jarvis עוד קצת ואז חזור לבקש תובנות!`,
            };
        }

        // 3. Build prompt + call LLM (always cloud for quality; optionally offload to Manus)
        const memoriesText = data.memories.map(m => `- ${m.content}`).join('\n') || 'אין זיכרונות שמורים';
        const profile = settings.userProfile || null;
        const prompt = buildInsightPrompt(analysis, memoriesText, userName) + profileSuggestions(profile) +
            '\nהתאם את ההצעות לפרופיל הזה ותן לפחות טיפ אחד שנוגע לתחומי העניין/משימות החוזרות.';

        let answer;
        const useManusOffload = process.env.MANUS_OFFLOAD_INSIGHT === 'true' && isManusConfigured();
        if (useManusOffload) {
            console.log('🔍 InsightAgent: offloading analysis to Manus');
            const result = await runManusTask(prompt);
            answer = result.answer;
        } else {
            answer = await callGemma4(prompt, false);
        }

        return { answer };

    } catch (err) {
        console.error('InsightAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי לנתח את הנתונים. נסה שוב.' };
    }
}

// ─── Day-plan optimization (on-the-fly, reuses analyzePatterns) ──────────────

const PEAK_WINDOWS = {
    morning:   { label: 'בוקר',   start: 9,  end: 12 },
    afternoon: { label: 'צהריים', start: 13, end: 16 },
    evening:   { label: 'ערב',    start: 18, end: 21 },
    night:     { label: 'לילה',   start: 22, end: 24 },
};

// Derive the productivity peak window from chat-history patterns.
// Returns null when there isn't enough history to be meaningful.
function peakWindowFromPatterns(patterns) {
    if (!patterns || patterns.totalMessages < 12) return null;
    const active = Object.values(patterns.buckets || {}).filter(n => n > 0).length;
    if (active === 0) return null;
    return PEAK_WINDOWS[patterns.peakBucket] || PEAK_WINDOWS.morning;
}

function buildDayPlanPrompt(scoredItems, peakWindow, load, userName) {
    const top = scoredItems.slice(0, 8).map((it, i) => {
        const kind = it.type === 'reminder' ? 'תזכורת' : 'משימה';
        const when = it.type === 'reminder'
            ? `(${new Date(it.scheduled_time).toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit' })})`
            : (it.due_date ? `(יעד: ${it.due_date})` : '(ללא תאריך)');
        return `${i + 1}. [${it.quadrant}] ${kind}: "${it.title}" ${when} — ציון ${it.score}`;
    }).join('\n');

    const peakStr = peakWindow
        ? `${peakWindow.label} (${peakWindow.start}:00–${peakWindow.end}:00)`
        : 'לא ידוע (היסטוריה דלה)';

    const loadStr = load.status === 'overload'
        ? `עומס יתר! נדרשות ${load.mustDoMinutes} דק׳ אך נותרו רק ${load.capacityMinutes} דק׳ ביום.`
        : load.status === 'tight'
            ? `העומס צפוף (${load.mustDoMinutes}/${load.capacityMinutes} דק׳).`
            : `העומס סביר (${load.mustDoMinutes}/${load.capacityMinutes} דק׳).`;

    return `אתה מתכנן-יום אישי חכם עבור ${userName}. להלן המשימות והתזכורות של היום, כבר ממוינות לפי דחיפות (רביעים: now=עכשיו, plan=לתכנן, quick=מהיר, later=מאוחר).

חלון הפרודוקטיביות של ${userName}: ${peakStr}
מצב העומס: ${loadStr}

הפריטים:
${top || 'אין פריטים'}

כתוב בעברית בלבד, קצר וענייני (עד 4 משפטים):
- במה כדאי להתחיל עכשיו ולמה.
- אם יש עומס יתר — אילו פריטי "later" כדאי לדחות למחר.
- נצל את חלון הפרודוקטיביות למשימות הכבדות.
אל תוסיף כותרות או רשימות — פסקה אחת זורמת.`;
}

// Produces a Hebrew schedule narrative. Degrades gracefully when the LLM is
// unavailable: returns ai_available:false with no narrative (the deterministic
// ordering from priorityEngine is still valid on its own).
async function optimizeDayPlan(scoredItems, patterns, load, settings = {}) {
    const userName = settings.userName || 'נדב';
    const peakWindow = peakWindowFromPatterns(patterns);

    if (!scoredItems || scoredItems.length === 0) {
        return { narrative: '', peak_window: peakWindow, ai_available: false };
    }

    try {
        const prompt = buildDayPlanPrompt(scoredItems, peakWindow, load, userName);
        const narrative = await callGemma4(prompt, false, 400);
        return { narrative: (narrative || '').trim(), peak_window: peakWindow, ai_available: true };
    } catch (err) {
        console.error('optimizeDayPlan LLM error:', err.message);
        return { narrative: '', peak_window: peakWindow, ai_available: false };
    }
}

module.exports = { runInsightAgent, analyzePatterns, optimizeDayPlan, peakWindowFromPatterns };
