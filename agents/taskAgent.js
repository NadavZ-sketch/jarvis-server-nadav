const axios = require('axios');

async function executeTaskAgent(userMessage, supabase) {
    // הפרומפט החדש: מלמד אותו לזהות גם בקשות למזג אוויר
    const systemPrompt = `You are a Task Manager AI. 
    Analyze the user message in Hebrew and extract the intent. 
    Intents allowed: 
    'add' (user wants to add a new task), 
    'list' (user wants to see their tasks), 
    'delete' (user wants to remove/finish a task),
    'weather' (user is asking about the weather, temperature, or if it's raining),
    'none' (not a task related command).
    
    Return ONLY a JSON object: {"intent": "add|list|delete|weather|none", "taskDetails": "the task text, OR the city name in Hebrew if weather (or empty string if no city mentioned)"}`;

    try {
        const response = await axios.post(`https://generativelanguage.googleapis.com/v1beta/models/gemma-4-26b-a4b-it:generateContent?key=${process.env.GOOGLE_API_KEY}`, {
            contents: [{ parts: [{ text: systemPrompt + "\nUser Message: " + userMessage }] }]
        }, { headers: { 'Content-Type': 'application/json' } });

        let aiText = response.data.candidates[0].content.parts[0].text;
        
        // חילוץ בטוח של ה-JSON
        const lastOpen = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');
        
        if (lastOpen !== -1 && lastClose !== -1 && lastOpen < lastClose) {
            const parsed = JSON.parse(aiText.substring(lastOpen, lastClose + 1));
            console.log("🧠 Task Agent parsed:", parsed);

            // 1. מזג אוויר (הפיצ'ר החדש!)
            if (parsed.intent === 'weather') {
                let city = parsed.taskDetails;
                
                // אם לא ביקשת עיר ספציפית, הוא יבדוק באשדוד כברירת מחדל
                if (!city || city.trim() === '' || city.toLowerCase() === 'empty') {
                    city = 'אשדוד'; 
                }
                
                try {
                    console.log(`☁️ Fetching weather for: ${city}`);
                    // פנייה לשירות מזג אוויר חינמי שמחזיר טמפרטורה ותיאור בעברית
                    const weatherRes = await axios.get(`https://wttr.in/${encodeURIComponent(city)}?format=%t+%C&lang=he`);
                    const weatherData = weatherRes.data.trim(); 
                    
                    return `הטמפרטורה ב${city} היא כרגע ${weatherData}.`;
                } catch (e) {
                    return "סליחה אדוני, יש לי כרגע תקלה בחיבור ללווייני מזג האוויר.";
                }
            }

            // 2. הוספת משימה
            if (parsed.intent === 'add') {
                await supabase.from('tasks').insert([{ content: parsed.taskDetails }]); 
                return `מעולה, הוספתי את המשימה: ${parsed.taskDetails}`;
            }
            
            // 3. שליפת משימות
            if (parsed.intent === 'list') {
                const { data } = await supabase.from('tasks').select('*');
                if (!data || data.length === 0) return "אין לך משימות כרגע, אתה יכול לנוח.";
                const taskList = data.map((t, i) => `${i + 1}. ${t.content}`).join('. ');
                return `הנה המשימות שלך: ${taskList}`;
            }
            
            // 4. מחיקת משימה
            if (parsed.intent === 'delete') {
                const { data, error } = await supabase
                    .from('tasks')
                    .delete()
                    .ilike('content', `%${parsed.taskDetails}%`)
                    .select();

                if (data && data.length > 0) {
                    return `מצוין, מחקתי את המשימה: ${data[0].content}.`;
                } else {
                    return "לא הצלחתי למצוא משימה כזו כדי למחוק אותה.";
                }
            }
        }
    } catch (err) {
        console.error("Task Agent Error:", err.message);
    }
    
    // אם זו לא משימה ולא מזג אוויר, מחזירים null כדי שהמוח הראשי יענה על השאלה
    return null; 
}

module.exports = { executeTaskAgent };