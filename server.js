require('dotenv').config();
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');
const googleTTS = require('google-tts-api');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' })); 

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);

let chatMemory = []; 

async function generateSpeech(text) {
    try {
        const results = await googleTTS.getAllAudioBase64(text, {
            lang: 'iw',
            slow: false,
            host: 'https://translate.google.com',
            splitPunct: ',.?!:' 
        });
        const buffers = results.map(res => Buffer.from(res.base64, 'base64'));
        return Buffer.concat(buffers).toString('base64');
    } catch (err) {
        console.error("❌ Google TTS Error:", err.message);
        return null;
    }
}

async function unifiedJarvisBrain(userMessage, imageBase64) {
    const { data: memoriesData } = await supabase.from('memories').select('content');
    let longTermMemories = "אין עדיין זיכרונות שמורים.";
    if (memoriesData && memoriesData.length > 0) {
        longTermMemories = memoriesData.map(m => `- ${m.content}`).join('\n');
    }

    const memoryString = chatMemory.map(msg => `${msg.role === 'user' ? 'Nadav' : 'Jarvis'}: ${msg.text}`).join('\n');
    
    const now = new Date();
    const currentDate = now.toLocaleDateString('he-IL', { timeZone: 'Asia/Jerusalem' });
    const currentDay = now.toLocaleDateString('he-IL', { weekday: 'long', timeZone: 'Asia/Jerusalem' });
    const currentTime = now.toLocaleTimeString('he-IL', { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute:'2-digit' });

    const systemPrompt = `You are Jarvis, an AI assistant. Analyze the user message AND the image if provided.
    Decide the intent: 'add', 'list', 'delete', 'weather', 'remember', or 'chat'.
    
    * IMPORTANT: For 'remember' intent, create a concise memory statement including a context tag in brackets at the beginning.
    * If an image is provided, analyze it deeply to answer the user's question accurately.
    
    Return ONLY a JSON object:
    {
      "intent": "add|list|delete|weather|remember|chat",
      "parameter": "the contextualized fact to remember or task details",
      "response": "conversational response in Hebrew"
    }
    
    --- Permanent Memories About Nadav ---
    ${longTermMemories}
    --------------------------------------
    
    Current DateTime: Today is ${currentDay}, ${currentDate}, and the local time is ${currentTime}.
    User is Nadav, Mechanical Engineer.
    
    --- Recent Conversation History ---
    ${memoryString}
    -----------------------------------
    
    Current Message from Nadav: `;

    try {
        // נשארים עם גרסת 2.5-flash-lite!
        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${process.env.GOOGLE_API_KEY}`;
        
        let promptParts = [{ text: systemPrompt + userMessage }];
        if (imageBase64) {
            promptParts.push({
                inlineData: {
                    data: imageBase64,
                    mimeType: "image/jpeg" 
                }
            });
        }

        const requestBody = {
            contents: [{ parts: promptParts }]
        };

        // התיקון הקריטי: מדליקים את החיפוש רק אם אין תמונה בבקשה
        if (!imageBase64) {
            requestBody.tools = [{ googleSearch: {} }];
        }

        const response = await axios.post(url, requestBody);

        let aiText = response.data.candidates[0].content.parts[0].text;
        const lastOpen = aiText.lastIndexOf('{');
        const lastClose = aiText.lastIndexOf('}');

        if (lastOpen !== -1 && lastClose !== -1) {
            return JSON.parse(aiText.substring(lastOpen, lastClose + 1));
        }
    } catch (err) {
        // עכשיו נראה בדיוק מה גוגל מתלונן אם משהו קורס
        console.error("AI Brain Error from Google:", err.response ? JSON.stringify(err.response.data, null, 2) : err.message);
    }
    return { intent: "chat", response: "סליחה נדב, נתקלתי בקושי בעיבוד המידע והתמונה." };
}

app.post('/ask-jarvis', async (req, res) => {
    try {
        const userMessage = req.body.command || "";
        const imageBase64 = req.body.image; 
        
        console.log(`\n--- Incoming Task: ${userMessage} | Has Image: ${!!imageBase64} ---`);
        const startTime = Date.now(); 

        const brainData = await unifiedJarvisBrain(userMessage, imageBase64);
        let answer = "";

        if (brainData.intent === 'add') {
            await supabase.from('tasks').insert([{ content: brainData.parameter }]); 
            answer = `הוספתי את המשימה: ${brainData.parameter}`;
        } else if (brainData.intent === 'list') {
            const { data } = await supabase.from('tasks').select('*');
            if (!data || data.length === 0) answer = "אין לך משימות כרגע.";
            else answer = `המשימות שלך: ` + data.map((t, i) => `${i + 1}. ${t.content}`).join('. ');
        } else if (brainData.intent === 'delete') {
            await supabase.from('tasks').delete().ilike('content', `%${brainData.parameter}%`);
            answer = `מחקתי את המשימה שביקשת.`;
        } else if (brainData.intent === 'weather') {
            let city = brainData.parameter || 'אשדוד';
            try {
                const weatherRes = await axios.get(`https://wttr.in/${encodeURIComponent(city)}?format=%t+%C&lang=he`);
                answer = `הטמפרטורה ב${city} היא ${weatherRes.data.trim()}.`;
            } catch(e) {
                answer = "תקלה בחיבור למזג האוויר.";
            }
        } else if (brainData.intent === 'remember') {
            await supabase.from('memories').insert([{ content: brainData.parameter }]);
            answer = `רשמתי לפניי: ${brainData.parameter}`;
        } else {
            answer = brainData.response || "לא הצלחתי לגבש תשובה.";
        }

        console.log(`⏱️ Speed Check: Processed in ${(Date.now() - startTime) / 1000} seconds!`);

        chatMemory.push({ role: 'user', text: userMessage });
        chatMemory.push({ role: 'jarvis', text: answer });
        if (chatMemory.length > 10) chatMemory = chatMemory.slice(chatMemory.length - 10);

        const audioBase64 = await generateSpeech(answer);
        res.json({ answer: answer, audio: audioBase64 });

    } catch (err) {
        console.error("Route Error:", err.message);
        res.status(500).json({ answer: "שגיאת מערכת פנימית." });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 JARVIS ONLINE | VISION (MODEL 2.5) ACTIVATED | PORT: ${PORT}`);
});