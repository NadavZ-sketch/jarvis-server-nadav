'use strict';

const { callGemma4 } = require('../agents/models');
const { extractJSON } = require('../agents/utils');

const CATEGORIES = ['עבודה', 'משפחה', 'בריאות', 'תחביב', 'כללי'];

const PROMPT_PREFIX = `סווג את התוכן הבא לאחת מהקטגוריות: עבודה, משפחה, בריאות, תחביב, כללי.
כללי היא ברירת המחדל כשאין התאמה ברורה לאף קטגוריה אחרת.
החזר JSON בלבד: {"category": "אחת מהקטגוריות בעברית"}

תוכן: `;

async function classifyCategory(content, useLocal = false) {
    if (!content || !content.trim()) return 'כללי';
    try {
        const aiText = await callGemma4([{ role: 'user', content: PROMPT_PREFIX + content }], useLocal, 60);
        const parsed = extractJSON(aiText);
        const category = parsed?.category;
        return CATEGORIES.includes(category) ? category : 'כללי';
    } catch (err) {
        console.error('[memoryCategory] classify error (defaulting to כללי):', err.message);
        return 'כללי';
    }
}

module.exports = { classifyCategory, CATEGORIES };
