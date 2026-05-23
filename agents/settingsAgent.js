const { callGemma4 } = require('./models');

const VALID_PERSONALITIES = ['friendly', 'formal', 'concise', 'humorous'];
const PERSONALITY_HE = { friendly: 'ידידותי', formal: 'רשמי', concise: 'קצר ולעניין', humorous: 'הומוריסטי' };
const VALID_GENDERS   = ['male', 'female'];

// Parse a settings change request and return { updates, summary } or null.
function parseSettingsIntent(msg) {
    const updates = {};
    const parts = [];

    // Personality
    if (/ידידות/i.test(msg))         { updates.personality = 'friendly';  parts.push('אופי: ידידותי'); }
    else if (/רשמי/i.test(msg))      { updates.personality = 'formal';    parts.push('אופי: רשמי'); }
    else if (/קצר|לעניין/i.test(msg)){ updates.personality = 'concise';   parts.push('אופי: קצר ולעניין'); }
    else if (/הומור|מצחיק/i.test(msg)){ updates.personality = 'humorous'; parts.push('אופי: הומוריסטי'); }

    // Voice speed
    if (/דבר.*יותר.*לאט|האט|לאט.*יותר|מדבר.*מהר/i.test(msg)) {
        updates.ttsSpeed = 'slower'; parts.push('קצב דיבור: איטי יותר');
    } else if (/דבר.*יותר.*מהר|האץ|מהר.*יותר|מדבר.*לאט/i.test(msg)) {
        updates.ttsSpeed = 'faster'; parts.push('קצב דיבור: מהיר יותר');
    }

    // Voice on/off
    if (/בטל קול|כבה קול|ללא קול|בלי קול|שתוק/i.test(msg)) {
        updates.voiceEnabled = false; parts.push('קול: כבוי');
    } else if (/הפעל קול|אפשר קול|הדלק קול|דבר בקול/i.test(msg)) {
        updates.voiceEnabled = true; parts.push('קול: פעיל');
    }

    // Response length
    if (/תשובות קצרות|ענה קצר|קצר יותר/i.test(msg))  { updates.responseLength = 'short';  parts.push('אורך תשובה: קצר'); }
    if (/תשובות ארוכות|ענה ארוך|מפורט יותר/i.test(msg)){ updates.responseLength = 'long';   parts.push('אורך תשובה: ארוך'); }

    // Name changes
    const nameMatch = msg.match(/שנה.*שם.*ל[- ]?["«]?([א-תa-zA-Z ]{2,20})["»]?/i)
                   || msg.match(/קרא לי ([א-תa-zA-Z ]{2,20})/i);
    if (nameMatch) { updates.userName = nameMatch[1].trim(); parts.push(`שמך: ${updates.userName}`); }

    const assistantMatch = msg.match(/שנה.*שם.*עוזר.*ל[- ]?["«]?([א-תa-zA-Z ]{2,20})["»]?/i)
                        || msg.match(/קרא לעצמך ([א-תa-zA-Z ]{2,20})/i);
    if (assistantMatch) { updates.assistantName = assistantMatch[1].trim(); parts.push(`שם עוזר: ${updates.assistantName}`); }

    if (Object.keys(updates).length === 0) return null;
    return { updates, summary: parts.join(', ') };
}

async function runSettingsAgent(userMessage, supabase, useLocal, settings) {
    const parsed = parseSettingsIntent(userMessage);

    if (parsed) {
        // Resolve relative ttsSpeed changes against current value
        const current = typeof settings?.ttsSpeed === 'number' ? settings.ttsSpeed : 0.7;
        if (parsed.updates.ttsSpeed === 'slower') {
            parsed.updates.ttsSpeed = Math.max(0.3, parseFloat((current - 0.15).toFixed(2)));
        } else if (parsed.updates.ttsSpeed === 'faster') {
            parsed.updates.ttsSpeed = Math.min(1.0, parseFloat((current + 0.15).toFixed(2)));
        }

        const name = settings?.assistantName || 'ג\'רוויס';
        return {
            answer: `בוצע! עדכנתי: ${parsed.summary}. השינויים יכנסו לתוקף מיד.`,
            action: { type: 'settings_update', data: parsed.updates },
        };
    }

    // Show current settings summary
    if (/מה.*הגדרות|הגדרות.*נוכחיות|הגדרות.*שלי|מה.*מוגדר/i.test(userMessage)) {
        const personality = PERSONALITY_HE[settings?.personality] || settings?.personality || 'ידידותי';
        const voice = settings?.voiceEnabled ? 'פעיל' : 'כבוי';
        const length = { short: 'קצר', medium: 'בינוני', long: 'ארוך' }[settings?.responseLength] || 'בינוני';
        const answer = `ההגדרות הנוכחיות שלי:\n• שם: ${settings?.userName || 'נדב'}\n• אופי: ${personality}\n• קול: ${voice}\n• אורך תשובה: ${length}`;
        return { answer };
    }

    // Fallback — ask LLM to extract the intent in Hebrew
    const prompt = `המשתמש ביקש לשנות הגדרות: "${userMessage}"
אפשרויות: אופי (ידידותי/רשמי/קצר ולעניין/הומוריסטי), קצב דיבור, קול (פועל/כבוי), אורך תשובה (קצר/בינוני/ארוך), שם משתמש.
אם אינך מבין מה לשנות, ענה בעברית ובקש הבהרה קצרה.`;
    const answer = await callGemma4(prompt, useLocal);
    return { answer };
}

module.exports = { runSettingsAgent };
