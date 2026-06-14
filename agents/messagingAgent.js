require('dotenv').config();
const { callGemma4 } = require('./models');

async function findContact(name, contacts) {
    const nameLower = name.trim().toLowerCase();
    const data = await contacts.searchByName(nameLower);
    if (!data || data.length === 0) return null;
    return data.find(c =>
        c.name.toLowerCase().includes(nameLower) ||
        (c.aliases && c.aliases.some(a => a.toLowerCase().includes(nameLower)))
    ) || null;
}

async function runMessagingAgent(userMessage, repos, useLocal = true, settings = {}) {
    const contacts = repos.contacts;
    try {
        const parsePrompt = `Parse this Hebrew message and return valid JSON only (no markdown, no explanation):
{
  "action": "send" or "save_contact",
  "channel": "whatsapp" or "email" or null,
  "recipient_name": "name, or 'self' if the user is sending to themselves, or null",
  "recipient_phone": "phone number digits only or null",
  "recipient_email": "email address if explicitly mentioned or null",
  "message_intent": "what the user wants to communicate in Hebrew or null",
  "urls": ["any URLs or links found in the message, empty array if none"]
}

If the user says "שלח לי", "שלח לעצמי", "תשלח לי", or is clearly requesting something be sent to themselves, set recipient_name to "self".
Message: "${userMessage}"`;

        const raw = await callGemma4(parsePrompt, useLocal);
        let parsed;
        try {
            const jsonMatch = raw.match(/\{[\s\S]*\}/);
            const cleaned = jsonMatch ? jsonMatch[0] : raw.replace(/```json|```/g, '').trim();
            parsed = JSON.parse(cleaned);
        } catch {
            return { answer: 'לא הצלחתי להבין את הבקשה. נסה לנסח אחרת.', action: null };
        }

        // ── Save contact ───────────────────────────────────────────────────────
        if (parsed.action === 'save_contact') {
            if (!parsed.recipient_name) {
                return { answer: 'לא הצלחתי לזהות שם. נסה: "שמור רון — 0501234567"', action: null };
            }
            const existing = await findContact(parsed.recipient_name, contacts);
            if (existing) {
                await contacts.updateById(existing.id, {
                    phone: parsed.recipient_phone || existing.phone,
                    email: parsed.recipient_email || existing.email,
                });
                return { answer: `✅ איש הקשר "${parsed.recipient_name}" עודכן.`, action: null };
            }
            const { error } = await contacts.create({
                name:  parsed.recipient_name,
                phone: parsed.recipient_phone || null,
                email: parsed.recipient_email || null,
            });
            if (error) throw error;
            return { answer: `✅ "${parsed.recipient_name}" נשמר באנשי הקשר.`, action: null };
        }

        // ── Send to self (user requests a link/message to themselves) ─────────
        if (parsed.recipient_name === 'self' || parsed.recipient_name === null) {
            const selfEmail = settings.userEmail
                || settings.userProfile?.email
                || parsed.recipient_email
                || null;

            if (!selfEmail) {
                return {
                    answer: 'כדי לשלוח לעצמך קישור במייל, הגדר את כתובת המייל שלך בהגדרות (שדה "המייל שלך").',
                    action: null
                };
            }

            const urls = Array.isArray(parsed.urls) ? parsed.urls : [];
            const baseText = parsed.message_intent || userMessage;
            const messageBody = urls.length > 0
                ? `${baseText}\n\n${urls.join('\n')}`
                : baseText;

            return {
                answer: `שולח לך את הקישור למייל (${selfEmail}) ✉️`,
                action: { type: 'email', email: selfEmail, message: messageBody }
            };
        }

        // ── Send message ───────────────────────────────────────────────────────
        const contact = await findContact(parsed.recipient_name, contacts);
        if (!contact) {
            return {
                answer: `לא מצאתי איש קשר בשם "${parsed.recipient_name}".\nתוכל לשמור אותו: "שמור ${parsed.recipient_name} — [מספר/מייל]"`,
                action: null
            };
        }

        // Draft the message with Gemma
        const urls = Array.isArray(parsed.urls) ? parsed.urls : [];
        const urlNote = urls.length > 0
            ? `\nחובה לכלול את הקישורים הבאים בהודעה כמות שהם: ${urls.join(', ')}`
            : '';
        const draftPrompt = `כתוב הודעה קצרה ומתאימה בעברית (עד 3 משפטים) לפי הבקשה הבאה.
כתוב רק את תוכן ההודעה, ללא כותרות, ללא "הנה ההודעה:" ובלי הסברים נוספים.${urlNote}

בקשה: "${parsed.message_intent || userMessage}"
נמען: ${contact.name}`;

        let draftedMessage = await callGemma4(draftPrompt, useLocal);
        // Ensure any extracted URLs appear verbatim in the final message
        if (urls.length > 0) {
            const missing = urls.filter(u => !draftedMessage.includes(u));
            if (missing.length > 0) draftedMessage = draftedMessage.trimEnd() + '\n' + missing.join('\n');
        }
        if (!draftedMessage || !draftedMessage.trim()) {
            return { answer: 'לא הצלחתי לנסח הודעה. נסה לתאר בצורה ברורה יותר מה לכתוב.', action: null };
        }
        const channel = parsed.channel || (contact.phone ? 'whatsapp' : 'email');

        let action = null;
        if (channel === 'whatsapp' && contact.phone) {
            const digits = contact.phone.replace(/[\s\-\(\)\+]/g, '');
            if (digits.length < 9) {
                return { answer: `מספר הטלפון של ${contact.name} לא תקין (${contact.phone}). עדכן: "שמור ${contact.name} — [מספר]"`, action: null };
            }
            const intlPhone = digits.startsWith('0') ? '972' + digits.slice(1) : digits;
            action = { type: 'whatsapp', phone: intlPhone, message: draftedMessage };
        } else if (channel === 'email' && contact.email) {
            action = { type: 'email', email: contact.email, message: draftedMessage };
        } else {
            const missing = channel === 'whatsapp' ? 'מספר טלפון' : 'כתובת מייל';
            return {
                answer: `אין ${missing} שמור עבור ${contact.name}. תוכל לעדכן: "שמור ${contact.name} — [${missing}]"`,
                action: null
            };
        }

        const channelLabel = channel === 'whatsapp' ? 'WhatsApp' : 'מייל';
        return {
            answer: `ניסחתי הודעה ל${contact.name} (${channelLabel}):\n\n"${draftedMessage}"`,
            action
        };

    } catch (err) {
        console.error('MessagingAgent Error:', err.message);
        return { answer: 'סליחה, נתקלתי בבעיה. נסה שוב.', action: null };
    }
}

module.exports = { runMessagingAgent };
