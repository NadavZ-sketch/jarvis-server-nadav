require('dotenv').config();
const axios    = require('axios');
const readline = require('readline');

// ─── Gemini (Google) — for live search agents (chat, sports) ───────────────
const GEMINI_MODEL = 'gemini-2.5-flash-lite';
const GOOGLE_KEY = process.env.GOOGLE_API_KEY;
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';
const GEMINI_URL = `${GEMINI_BASE}/${GEMINI_MODEL}:generateContent?key=${GOOGLE_KEY}`;

// ─── Groq — primary cloud (free, fast, OpenAI-compatible) ─────────────────
const GROQ_URL   = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_MODEL = 'llama-3.3-70b-versatile';

// ─── DeepSeek — fallback (OpenAI-compatible) ───────────────────────────────
const DEEPSEEK_URL   = 'https://api.deepseek.com/chat/completions';
const DEEPSEEK_MODEL = 'deepseek-chat';

// Local Ollama override (optional — set OLLAMA_URL in .env to use local model)
const OLLAMA_URL   = process.env.OLLAMA_URL;
const OLLAMA_MODEL = 'gemma4:e4b';

async function callGemma4(messages, useLocal = true, maxTokens = 800) {
    const msgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    // ── 1. Local Ollama (only if useLocal is enabled AND OLLAMA_URL is set) ──
    if (useLocal && OLLAMA_URL) {
        const response = await axios.post(`${OLLAMA_URL}/v1/chat/completions`, {
            model: OLLAMA_MODEL, messages: msgs, stream: false
        }, { timeout: 15000 });
        return response.data.choices[0].message.content.trim();
    }

    // ── 2. Groq (free, fast) ──
    try {
        const response = await axios.post(GROQ_URL, {
            model: GROQ_MODEL, messages: msgs, max_tokens: maxTokens
        }, {
            headers: {
                'Authorization': `Bearer ${process.env.GROQ_API_KEY}`,
                'Content-Type': 'application/json'
            },
            timeout: 7000,
        });
        const content = response.data.choices[0].message.content.trim();
        // Groq occasionally returns infrastructure errors as completion text instead of HTTP errors.
        // Detect and fall through to the next provider rather than showing raw error to the user.
        if (/^(API Error:|Stream idle timeout|internal server error)/i.test(content)) {
            console.warn('⚠️ Groq returned error as content, falling back to DeepSeek:', content.slice(0, 80));
            throw new Error(content);
        }
        return content;
    } catch (groqErr) {
        const detail = groqErr.response?.data ? JSON.stringify(groqErr.response.data) : groqErr.message;
        console.warn('⚠️ Groq failed, falling back to DeepSeek:', detail);
    }

    // ── 3. DeepSeek fallback ──
    try {
        const response = await axios.post(DEEPSEEK_URL, {
            model: DEEPSEEK_MODEL, messages: msgs, max_tokens: maxTokens
        }, {
            headers: {
                'Authorization': `Bearer ${process.env.DEEPSEEK_API_KEY}`,
                'Content-Type': 'application/json'
            },
            timeout: 9000,
        });
        return response.data.choices[0].message.content.trim();
    } catch (deepseekErr) {
        console.warn('⚠️ DeepSeek failed, falling back to Gemini:', deepseekErr.message);
    }

    // ── 4. Gemini final fallback ──
    const prompt = msgs.map(m => m.content).join('\n');
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }]
    }, { timeout: 15000 });
    return response.data.candidates[0].content.parts[0].text.trim();
}

// ─── SSE stream parser (Groq / DeepSeek / Ollama) ─────────────────────────────
// Returns { complete: true } when [DONE] is received, rejects on error/timeout.

function parseSSEStream(stream, onChunk) {
    return new Promise((resolve, reject) => {
        const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
        let settled = false;
        let doneSeen = false;
        let chunksSent = 0;

        const IDLE_MS = 12000;

        let idleTimer = setTimeout(() => {
            console.warn('⚠️ Stream idle timeout (12s) — closing');
            rl.close();
        }, IDLE_MS);

        const done = (err) => {
            if (settled) return;
            settled = true;
            clearTimeout(idleTimer);
            if (err) return reject(err);
            // Idle timeout fired without [DONE] and without any chunks → treat as error
            if (!doneSeen && chunksSent === 0) {
                return reject(new Error('Stream idle timeout — no data received'));
            }
            resolve({ complete: doneSeen });
        };

        rl.on('line', (line) => {
            clearTimeout(idleTimer);
            idleTimer = setTimeout(() => {
                console.warn('⚠️ Stream idle timeout (12s) — closing');
                rl.close();
            }, IDLE_MS);

            if (!line.startsWith('data: ')) return;
            const json = line.slice(6).trim();
            if (json === '[DONE]') { doneSeen = true; rl.close(); return; }
            try {
                const parsed = JSON.parse(json);
                if (parsed.error) {
                    const msg = parsed.error.message || JSON.stringify(parsed.error);
                    console.warn('⚠️ Stream error event:', msg);
                    // Reject so the caller can fall back to the next provider
                    // (unless we already sent chunks — in that case just close gracefully)
                    if (chunksSent === 0) {
                        rl.close();
                        return done(new Error(msg));
                    }
                    rl.close();
                    return;
                }
                const content = parsed.choices?.[0]?.delta?.content;
                if (content) { chunksSent++; onChunk(content); }
            } catch {}
        });
        rl.on('close', () => done());
        rl.on('error', (e) => done(e));
        stream.on('error', (e) => done(e));
    });
}

// ─── Streaming variant: Groq → DeepSeek → Gemini (non-stream fallback) ────────

async function callGemma4Stream(messages, useLocal = true, onChunk, signal = null) {
    const msgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    const streamOpts = (headers) => ({
        headers,
        responseType: 'stream',
        timeout: 15000,
        ...(signal ? { signal } : {})
    });

    // ── 1. Local Ollama ──
    if (useLocal && OLLAMA_URL) {
        const response = await axios.post(`${OLLAMA_URL}/v1/chat/completions`, {
            model: OLLAMA_MODEL, messages: msgs, stream: true
        }, streamOpts({ 'Content-Type': 'application/json' }));
        await parseSSEStream(response.data, onChunk);
        return;
    }

    // ── 2. Groq streaming ──
    try {
        const response = await axios.post(GROQ_URL, {
            model: GROQ_MODEL, messages: msgs, max_tokens: 800, stream: true
        }, streamOpts({
            'Authorization': `Bearer ${process.env.GROQ_API_KEY}`,
            'Content-Type': 'application/json'
        }));
        // parseSSEStream resolves (complete or partial chunks) or rejects (no data + error/timeout).
        // On resolve we're done — even a partial response is better than a fallback that appends.
        await parseSSEStream(response.data, onChunk);
        return;
    } catch (err) {
        if (err.name === 'CanceledError' || err.name === 'AbortError') throw err;
        console.warn('⚠️ Groq stream failed, falling back to DeepSeek:', err.message);
    }

    // ── 3. DeepSeek streaming fallback ──
    try {
        const response = await axios.post(DEEPSEEK_URL, {
            model: DEEPSEEK_MODEL, messages: msgs, max_tokens: 800, stream: true
        }, streamOpts({
            'Authorization': `Bearer ${process.env.DEEPSEEK_API_KEY}`,
            'Content-Type': 'application/json'
        }));
        await parseSSEStream(response.data, onChunk);
        return;
    } catch (err) {
        if (err.name === 'CanceledError' || err.name === 'AbortError') throw err;
        console.warn('⚠️ DeepSeek stream failed, falling back to Gemini (non-streaming):', err.message);
    }

    // ── 4. Gemini final fallback (non-streaming) ──
    const prompt = msgs.map(m => m.content).join('\n');
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }]
    }, { timeout: 15000, ...(signal ? { signal } : {}) });
    const text = response.data.candidates[0].content.parts[0].text.trim();
    onChunk(text);
}

// ─── Gemini with Google Search grounding (real-time data) ─────────────────────

async function callGeminiWithSearch(prompt) {
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }],
        tools: [{ google_search: {} }]
    });
    return response.data.candidates[0].content.parts[0].text.trim();
}

// ─── Gemini Vision (image + text) ─────────────────────────────────────────────

function detectMimeType(base64) {
    if (base64.startsWith('/9j/'))  return 'image/jpeg';
    if (base64.startsWith('iVBOR')) return 'image/png';
    if (base64.startsWith('UklGR')) return 'image/webp';
    return 'image/jpeg';
}

async function callGeminiVision(prompt, imageBase64) {
    const response = await axios.post(GEMINI_URL, {
        contents: [{
            parts: [
                { text: prompt },
                { inline_data: { mime_type: detectMimeType(imageBase64), data: imageBase64 } }
            ]
        }]
    });
    return response.data.candidates[0].content.parts[0].text.trim();
}

module.exports = { GEMINI_URL, callGemma4, callGemma4Stream, callGeminiWithSearch, callGeminiVision, detectMimeType };
