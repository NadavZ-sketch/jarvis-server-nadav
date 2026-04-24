const { sanitizeLike } = require('./utils');
require('dotenv').config();
const { callGemma4 } = require('./models');

async function findContact(name, supabase) {
    const nameLower = name.trim().toLowerCase();
    // Use .ilike() directly — safer than .or() string interpolation
    const { data } = await supabase
        .from('contacts')
        .select('*')
        .ilike('name', `%${nameLower}%`);
    if (!data || data.length === 0) return null;
    return data.find(c =>
        c.name.toLowerCase().includes(nameLower) ||
        (c.aliases && c.aliases.some(a => a.toLowerCase().includes(nameLower)))
    ) || null;
}

async function runMessagingAgent(userMessage, supabase, useLocal = true) {
    try {
        const parsePrompt = `Parse this Hebrew message and return valid JSON only (no markdown, no explanation):
{
  "action": "send" or "save_contact",
  "channel": "whatsapp" or "email" or null,
  "recipient_name": "name or null",
  "recipient_phone": "phone number digits only or null",
  "recipient_email": "email or null",
  "message_intent": "what the user wants to communicate in Hebrew or null"
}

Message: "${userMessage}"`;

        const raw = await callGemma4(parsePrompt, useLocal);
        let parsed;
        try {
            parsed = JSON.parse(raw.replace(/```json|```/g, '').trim());
        } catch {
            return { answer: 'לא הצלחתי להבין את הבקשה. נסה לנסח אחרת.', action: null };
        }

        // ── Save contact ───────────────────────────────────────────────────────
        if (parsed.action === 'save_contact') {
            if (!parsed.recipient_name) {
                return { answer: 'לא הצלחתי לזהות שם. נסה: "שמור רון — 0501234567"', action: null };
            }
            const existing = await findContact(parsed.recipient_name, supabase);
            if (existing) {
                // Update existing contact
                await supabase.from('contacts').update({
                    phone: parsed.recipient_phone || existing.phone,
                    email: parsed.recipient_email || existing.email,
                }).eq('id', existing.id);
                return { answer: `✅ איש הקשר "${parsed.recipient_name}" עודכן.`, action: null };
            }
            const { error } = await supabase.from('contacts').insert([{
                name:  parsed.recipient_name,
                phone: parsed.recipient_phone || null,
                email: parsed.recipient_email || null,
            }]);
            if (error) throw error;
            return { answer: `✅ "${parsed.recipient_name}" נשמר באנשי הקשר.`, action: null };
        }

        // ── Send message ───────────────────────────────────────────────────────
        if (!parsed.recipient_name) {
            return { answer: 'לא הצלחתי לזהות את הנמען. נסה לציין שם ברור.', action: null };
        }

        const contact = await findContact(parsed.recipient_name, supabase);
        if (!contact) {
            return {
                answer: `לא מצאתי איש קשר בשם "${parsed.recipient_name}".\nתוכל לשמור אותו: "שמור ${parsed.recipient_name} — [מספר/מייל]"`,
                action: null
            };
        }

        // Draft the message with Gemma
        const draftPrompt = `כתוב הודעה קצרה ומתאימה בעברית (עד 3 משפטים) לפי הבקשה הבאה.
כתוב רק את תוכן ההודעה, ללא כותרות, ללא "הנה ההודעה:" ובלי הסברים נוספים.

בקשה: "${parsed.message_intent || userMessage}"
נמען: ${contact.name}`;

        const draftedMessage = await callGemma4(draftPrompt, useLocal);
        const channel = parsed.channel || (contact.phone ? 'whatsapp' : 'email');

        let action = null;
        if (channel === 'whatsapp' && contact.phone) {
            const digits = contact.phone.replace(/[\s\-\(\)\+]/g, '');
            if (digits.length < 8) {
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
