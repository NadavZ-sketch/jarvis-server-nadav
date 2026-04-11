require('dotenv').config();

const HE_DAYS = { 'ראשון': 0, 'שני': 1, 'שלישי': 2, 'רביעי': 3, 'חמישי': 4, 'שישי': 5, 'שבת': 6 };

function nowJerusalem() {
    // Returns a Date object representing "now" in Jerusalem time
    return new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }));
}

function toISO(date) {
    const pad = n => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:00+03:00`;
}

function extractReminderText(msg) {
    // Remove the scheduling part and return what to remind about
    return msg
        .replace(/תזכיר לי\s*/i, '')
        .replace(/תזכור לי\s*/i, '')
        .replace(/תוסיף תזכורת\s*/i, '')
        .replace(/בעוד \d+ (דקות?|שעות?|שעה)/g, '')
        .replace(/מחר/g, '')
        .replace(/ב-?\d{1,2}:\d{2}/g, '')
        .replace(/בשעה \d{1,2}:\d{2}/g, '')
        .replace(/ביום (ראשון|שני|שלישי|רביעי|חמישי|שישי|שבת)/g, '')
        .replace(/\s+/g, ' ')
        .trim() || msg.trim();
}

function parseTime(msg) {
    const now = nowJerusalem();

    // בעוד X דקות
    const minsMatch = msg.match(/בעוד\s+(\d+)\s+דקות?/);
    if (minsMatch) {
        const d = new Date(now);
        d.setMinutes(d.getMinutes() + parseInt(minsMatch[1]));
        return d;
    }

    // בעוד X שעות / בעוד שעה
    const hoursMatch = msg.match(/בעוד\s+(\d+)?\s*שעות?/);
    if (hoursMatch) {
        const d = new Date(now);
        d.setHours(d.getHours() + parseInt(hoursMatch[1] || '1'));
        return d;
    }

    // ב-HH:MM או בשעה HH:MM
    const timeMatch = msg.match(/(?:ב-?|בשעה\s*)(\d{1,2}):(\d{2})/);
    const hasTime = timeMatch !== null;
    const targetHour = hasTime ? parseInt(timeMatch[1]) : now.getHours();
    const targetMin  = hasTime ? parseInt(timeMatch[2]) : now.getMinutes();

    // מחר
    if (/מחר/.test(msg)) {
        const d = new Date(now);
        d.setDate(d.getDate() + 1);
        d.setHours(targetHour, targetMin, 0);
        return d;
    }

    // ביום X (שני, שלישי...)
    const dayMatch = msg.match(/ביום\s+(ראשון|שני|שלישי|רביעי|חמישי|שישי|שבת)/);
    if (dayMatch) {
        const targetDay = HE_DAYS[dayMatch[1]];
        const d = new Date(now);
        let diff = targetDay - d.getDay();
        if (diff <= 0) diff += 7;
        d.setDate(d.getDate() + diff);
        d.setHours(targetHour, targetMin, 0);
        return d;
    }

    // ב-HH:MM היום (או מחר אם כבר עבר)
    if (hasTime) {
        const d = new Date(now);
        d.setHours(targetHour, targetMin, 0);
        if (d <= now) d.setDate(d.getDate() + 1); // אם כבר עבר — מחר
        return d;
    }

    return null;
}

async function runReminderAgent(userMessage, supabase) {
    try {
        const fireDate = parseTime(userMessage);
        if (!fireDate) throw new Error('Could not parse time from message');

        const reminderText = extractReminderText(userMessage);
        const scheduledTime = toISO(fireDate);

        console.log(`⏰ ReminderAgent: "${reminderText}" at ${scheduledTime}`);

        const { error } = await supabase
            .from('reminders')
            .insert([{ text: reminderText, scheduled_time: scheduledTime }]);

        if (error) throw error;

        const fireLocal = fireDate.toLocaleString('he-IL', {
            timeZone: 'Asia/Jerusalem',
            weekday: 'long',
            day: 'numeric',
            month: 'long',
            hour: '2-digit',
            minute: '2-digit'
        });

        return { answer: `בסדר, אזכיר לך "${reminderText}" ב${fireLocal}.` };

    } catch (err) {
        console.error('ReminderAgent Error:', err.message);
        return { answer: 'לא הצלחתי להבין את מועד התזכורת. נסה למשל: "תזכיר לי בעוד 30 דקות לשתות מים"' };
    }
}

module.exports = { runReminderAgent };
