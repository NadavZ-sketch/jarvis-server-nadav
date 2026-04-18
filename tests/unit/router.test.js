'use strict';
const { classifyIntent } = require('../../agents/router');

describe('classifyIntent — keyword routing', () => {
    test.each([
        // task keywords
        ['הוסף משימה לקנות חלב', 'task'],
        ['מחק משימה', 'task'],
        ['רשימת משימות', 'task'],
        ['סיימתי את האימון', 'task'],
        ['השלמתי את הפרויקט', 'task'],
        ['סמן כבוצע', 'task'],
        // reminder keywords
        ['תזכיר לי בעוד שעה', 'reminder'],
        ['הצג תזכורות', 'reminder'],
        ['מחק תזכורת על אימון', 'reminder'],
        ['כל התזכורות', 'reminder'],
        // memory keywords
        ['זכור ש אני אוהב פיצה', 'memory'],
        ['מה אתה יודע עליי', 'memory'],
        ['מחק זיכרון', 'memory'],
        ['שכח ש אני גר בתל אביב', 'memory'],
        // sports keywords
        ['מה קורה בפרמייר ליג', 'sports'],
        ['ארסנל נגד צ\'לסי', 'sports'],
        ['premier league', 'sports'],
        ['liverpool', 'sports'],
        ['טבלת הליגה', 'sports'],
        // music keywords
        ['מוזיקה לאימון', 'music'],
        ['הצג פלייליסט', 'music'],
        ['תנגן שיר', 'music'],
        ['spotify', 'music'],
        // messaging keywords
        ['שלח ווצאפ לרון', 'messaging'],
        ['שלח מייל לאמא', 'messaging'],
        ['שמור מספר של רון', 'messaging'],
        ['הוסף איש קשר', 'messaging'],
        // draft keywords
        ['נסח לי הודעה לבוס', 'draft'],
        ['תכתוב לי מייל', 'draft'],
        ['עזור לי לנסח', 'draft'],
        // default to chat
        ['מה השעה עכשיו', 'chat'],
        ['שלום', 'chat'],
        ['', 'chat'],
        ['hello world', 'chat'],
    ])('"%s" → "%s"', (input, expected) => {
        expect(classifyIntent(input)).toBe(expected);
    });

    test('reminder beats memory when message contains תזכיר לי (ORDER MATTERS)', () => {
        // "תזכיר לי" matches reminder; "מה שמרת" matches memory — reminder must win
        expect(classifyIntent('תזכיר לי מה שמרת עליי')).toBe('reminder');
    });

    test('returns string (not a Promise)', () => {
        const result = classifyIntent('שלום');
        expect(typeof result).toBe('string');
    });
});
