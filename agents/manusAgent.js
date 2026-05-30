require('dotenv').config();
const axios = require('axios');

// ─── Manus Agent — heavy/complex autonomous tasks ─────────────────────────────
//
// Manus is a long-running agent API (not a simple chat-completion provider).
// It accepts a natural-language task, runs it autonomously (browsing, coding,
// file ops), and returns a detailed result. Use for tasks that require multi-step
// reasoning and tool use that would be too slow or complex for standard LLMs.
//
// API: https://api.manus.ai/v2  (OpenAI-compatible subset)
// Auth: x-manus-api-key header
// Models: manus-1.6-lite | manus-1.6 | manus-1.6-max

const MANUS_API_KEY = process.env.MANUS_API_KEY;
const MANUS_BASE = 'https://api.manus.ai/v2';
const MANUS_MODEL = process.env.MANUS_MODEL || 'manus-1.6';

// Poll a Manus task by ID until it completes or the timeout is reached.
// Returns the result text or throws on timeout/error.
async function _pollTask(taskId, timeoutMs = 120000) {
    const deadline = Date.now() + timeoutMs;
    let delay = 3000;
    while (Date.now() < deadline) {
        await new Promise(r => setTimeout(r, delay));
        delay = Math.min(delay * 1.5, 15000); // back-off: 3s → 4.5s → 6.75s … max 15s

        const resp = await axios.get(`${MANUS_BASE}/tasks/${taskId}`, {
            headers: { 'x-manus-api-key': MANUS_API_KEY },
            timeout: 10000,
        });
        const { status, result } = resp.data;
        if (status === 'completed' && result) return result;
        if (status === 'failed') throw new Error(resp.data.error || 'Manus task failed');
    }
    throw new Error('Manus task timed out after 2 minutes');
}

async function runManusAgent(userMessage, settings = {}) {
    if (!MANUS_API_KEY) {
        return { answer: '⚠️ MANUS_API_KEY לא מוגדר. הוסף אותו בהגדרות הסביבה של השרת.' };
    }

    console.log(`🦾 Manus: starting task — "${userMessage.slice(0, 80)}"`);

    try {
        // Step 1: Create the task
        const createResp = await axios.post(`${MANUS_BASE}/tasks`, {
            prompt: userMessage,
            model: MANUS_MODEL,
        }, {
            headers: {
                'Content-Type': 'application/json',
                'x-manus-api-key': MANUS_API_KEY,
            },
            timeout: 15000,
        });

        const taskId = createResp.data?.task_id || createResp.data?.id;
        if (!taskId) throw new Error('Manus did not return a task ID');
        console.log(`🦾 Manus: task created — id=${taskId}`);

        // Step 2: Poll until done
        const result = await _pollTask(taskId);

        const answer = typeof result === 'string'
            ? result
            : result.content || result.text || JSON.stringify(result, null, 2);

        console.log(`🦾 Manus: task completed — ${answer.slice(0, 80)}`);
        return { answer };

    } catch (err) {
        const detail = err.response?.data?.error || err.response?.data?.message || err.message;
        console.error('🦾 Manus error:', detail);
        return {
            answer: `⚠️ Manus לא הצליח להשלים את המשימה: ${detail}`,
        };
    }
}

module.exports = { runManusAgent };
