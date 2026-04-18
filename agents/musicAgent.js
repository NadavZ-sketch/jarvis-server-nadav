require('dotenv').config();
const { callGemma4 } = require('./models');

async function runMusicAgent(userMessage, supabase, useLocal = false, settings = {}) {
    const userName = settings.userName || 'נדב';

    try {
        const isListPlaylist   = /הצג.*פלייליסט|פלייליסט שלי|מה\s.*פלייליסט|כל.*שיר.*שמור/i.test(userMessage);
        const isSavePlaylist   = /הוסף.*פלייליסט|שמור.*פלייליסט|הוסף.*מועדפים|שמור.*מועדפים/i.test(userMessage);
        const isDeletePlaylist = /מחק.*שיר|הסר.*שיר|מחק.*מהפלייליסט|הסר.*מהפלייליסט/i.test(userMessage);

        if (isListPlaylist) {
            const { data, error } = await supabase
                .from('playlist')
                .select('title, artist')
                .order('created_at', { ascending: false })
                .limit(20);
            if (error) throw error;
            if (!data || data.length === 0) {
                return { answer: `אין לך עדיין שירים שמורים בפלייליסט, ${userName}.` };
            }
            const list = data.map((s, i) => `${i + 1}. ${s.title}${s.artist ? ` — ${s.artist}` : ''}`).join('\n');
            return { answer: `🎵 הפלייליסט שלך:\n${list}` };
        }

        if (isDeletePlaylist) {
            const term = userMessage
                .replace(/מחק|הסר|שיר|מהפלייליסט|מהמועדפים|פלייליסט|מועדפים/g, '')
                .trim();
            if (!term) return { answer: 'מה למחוק? נסה: "מחק שיר [שם]"' };
            const { data, error } = await supabase.from('playlist').delete().ilike('title', `%${term}%`).select();
            if (error) throw error;
            if (!data?.length) return { answer: `לא מצאתי "${term}" בפלייליסט.` };
            return { answer: `✅ הסרתי "${data[0].title}" מהפלייליסט.` };
        }

        if (isSavePlaylist) {
            const term = userMessage
                .replace(/הוסף|שמור|לפלייליסט|למועדפים|פלייליסט|מועדפים/g, '')
                .trim();
            if (!term) return { answer: 'מה להוסיף? נסה: "הוסף לפלייליסט [שם השיר]"' };
            await supabase.from('playlist').insert([{ title: term, artist: '' }]);
            return { answer: `✅ הוספתי "${term}" לפלייליסט שלך.` };
        }

        // Music recommendation
        const prompt = `אתה עוזר מוזיקה של ${userName}. המשתמש ביקש: "${userMessage}".
המלץ בעברית בשתי שורות קצרות על שיר או אמן מתאים למצב רוח.
בסוף הוסף שורה בפורמט: SEARCH: <english search query for YouTube Music>`;

        const aiText = await callGemma4(prompt, useLocal);

        const searchMatch = aiText.match(/SEARCH:\s*(.+)/i);
        const searchQuery = searchMatch ? searchMatch[1].trim() : userMessage;
        const cleanAnswer = aiText.replace(/SEARCH:\s*.+/i, '').trim();
        const ytUrl = `https://music.youtube.com/search?q=${encodeURIComponent(searchQuery)}`;

        return {
            answer: cleanAnswer,
            action: { type: 'music', url: ytUrl },
        };

    } catch (err) {
        console.error('MusicAgent Error:', err.message);
        return { answer: 'סליחה, לא הצלחתי לעבד את הבקשה המוזיקלית. נסה שוב.' };
    }
}

module.exports = { runMusicAgent };
