'use strict';
jest.mock('axios');
const axios = require('axios');
const { classifyIntent, classifyIntentWithLLM, detectComplexTask } = require('../../agents/router');

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
        // weather keywords (definite-article form must also match)
        ['מזג אוויר', 'weather'],
        ['מה מזג האוויר היום', 'weather'],
        ['תחזית למחר', 'weather'],
        // e2e keywords
        ['בצע בדיקות קצה', 'e2e'],
        ['בדיקות קצה לקצה', 'e2e'],
        ['הרץ בדיקות', 'e2e'],
        ['end-to-end', 'e2e'],
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

describe('classifyIntentWithLLM', () => {
    const groqResponse = (intent) => ({
        data: { choices: [{ message: { content: `{"intent":"${intent}"}` } }] }
    });

    beforeEach(() => jest.clearAllMocks());

    test('returns valid intent from LLM JSON', async () => {
        axios.post.mockResolvedValueOnce(groqResponse('task'));
        expect(await classifyIntentWithLLM('אני צריך לגמור את הפרויקט')).toBe('task');
    });

    test('JSON with braces in surrounding text is parsed correctly', async () => {
        // Bug fix: indexOf('{') vs lastIndexOf('{') — preamble before JSON must be ignored
        axios.post.mockResolvedValueOnce({
            data: { choices: [{ message: { content: 'Sure! {"intent":"reminder"}' } }] }
        });
        expect(await classifyIntentWithLLM('תזכיר לי לקנות חלב')).toBe('reminder');
    });

    test('unknown intent from LLM falls back to chat', async () => {
        axios.post.mockResolvedValueOnce({
            data: { choices: [{ message: { content: '{"intent":"flying"}' } }] }
        });
        expect(await classifyIntentWithLLM('משהו מוזר')).toBe('chat');
    });

    test('LLM returns no JSON → falls back to chat', async () => {
        axios.post.mockResolvedValueOnce({
            data: { choices: [{ message: { content: 'I do not know' } }] }
        });
        expect(await classifyIntentWithLLM('שאלה כלשהי')).toBe('chat');
    });

    test('network error → falls back to chat', async () => {
        axios.post.mockRejectedValueOnce(new Error('timeout'));
        expect(await classifyIntentWithLLM('שאלה כלשהי')).toBe('chat');
    });
});

describe('manus keyword routing', () => {
    test.each([
        ['manus', 'manus'],
        ['מאנוס', 'manus'],
        ['מטלה מורכבת לבניית מערכת', 'manus'],
        ['מחקר מעמיק על השוק הישראלי', 'manus'],
        ['deep research on AI trends', 'manus'],
        ['בנה לי אפליקציה לניהול זמן', 'manus'],
        ['תחקור לעומק את הנושא', 'manus'],
    ])('"%s" → "manus"', (input) => {
        expect(classifyIntent(input)).toBe('manus');
    });

    test('ordinary news question does NOT route to manus', () => {
        expect(classifyIntent('מה קורה בחדשות היום')).toBe('news');
    });

    test('ordinary task does NOT route to manus', () => {
        expect(classifyIntent('הוסף משימה לקנות חלב')).toBe('task');
    });

    test('short chat message does NOT route to manus', () => {
        expect(classifyIntent('שלום')).toBe('chat');
    });
});

describe('detectComplexTask', () => {
    test('short message → false', () => {
        expect(detectComplexTask('שלום')).toBe(false);
    });

    test('long message with research signal → true', () => {
        const msg = 'אני רוצה שתעשה מחקר מעמיק על שוק התוכנה הישראלי ותשווה בין המתחרים העיקריים, תכין דוח מפורט עם המלצות אסטרטגיות ותציג את הממצאים בצורה ברורה ומקיפה. חשוב שהמחקר יהיה מקיף ויכסה את כל ההיבטים הרלוונטיים.';
        expect(msg.length).toBeGreaterThan(180);
        expect(detectComplexTask(msg)).toBe(true);
    });

    test('long message without complexity signals → false', () => {
        const msg = 'שלום ג\'רוויס, יש לי שאלה פשוטה בנוגע לפעולות היום שלי ואני רוצה לדעת מה מצב העסקים ואיפה כדאי לי ללכת לאכול צהריים כי אני רעב מאוד ולא יודע להחליט בין שתי האפשרויות שעומדות בפניי כרגע ממש.';
        expect(msg.length).toBeGreaterThan(180);
        expect(detectComplexTask(msg)).toBe(false);
    });

    test('numbered list with build signal → true', () => {
        const msg = 'בנה לי סקריפט Python שעושה את הדברים הבאים: 1. סורק תיקייה 2. מסדר קבצים לפי סוג 3. יוצר דוח סיכום 4. שולח מייל עם הדוח 5. עושה גיבוי אוטומטי לענן ואז מאתחל מחדש. זה חשוב מאוד לפרויקט שלי.';
        expect(detectComplexTask(msg)).toBe(true);
    });
});
