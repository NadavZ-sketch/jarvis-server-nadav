// Keyword-based fast routing — no API call needed
// ORDER MATTERS: reminder must be before memory to avoid תזכיר לי conflict
const KEYWORDS = {
    task:      /משימ|הוסף משימ|מחק משימ|רשימת משימ|הראה משימ|כל המשימ|סיימתי|סמן כבוצע|השלמתי/i,
    reminder:  /תזכיר לי|הזכר לי|תזכורת|להזכיר לי|הצג תזכורות|מחק תזכורת|בטל תזכורת|כל התזכורות|רשימת תזכורות/i,
    memory:    /זכור ש|תזכור ש|שמור ש|מה אתה יודע|מה זכרת|ספר לי עליי|מה שמרת|מחק זיכרון|הסר זיכרון|שכח ש/i,
    sports:    /כדורגל|פרמייר|ליג|מאמן|קבוצ|שחקן|גול|ניצחון|הפסד|תוצא|טבלה|דירוג|העברות|ארסנל|צ'לסי|מנצ'סטר|ליברפול|טוטנהאם|אסטון|ניוקאסל|ברייטון|everton|arsenal|chelsea|liverpool|premier league|epl/i,
    music:     /מוזיקה|מוסיקה|פלייליסט|להשמיע|תנגן|תשמיע|ספוטיפיי|spotify/i,
    messaging: /שלח.*ווצאפ|שלח.*וואטסאפ|שלח.*מייל|ווצאפ ל|וואטסאפ ל|מייל ל|שלח הודעה ל|שמור.*קשר|הוסף.*קשר|שמור.*טלפון|שמור.*מספר/i,
    draft:     /נסח לי|תנסח|עזור לי לנסח|כתוב לי|תכתוב לי|תכין לי|הכן לי.*הודעה|תעזור לי לכתוב|נוסח ל/i,
};

function classifyIntent(userMessage) {
    // Fast path: keyword match (saves a Gemini API call)
    for (const [intent, pattern] of Object.entries(KEYWORDS)) {
        if (pattern.test(userMessage)) {
            console.log(`🧭 Router (keyword): "${intent}" ← "${userMessage.slice(0, 50)}"`);
            return intent;
        }
    }

    // No keyword match → default to chat (saves a Gemini API call)
    console.log(`🧭 Router (default): "chat" ← "${userMessage.slice(0, 50)}"`);
    return 'chat';
}

module.exports = { classifyIntent };
