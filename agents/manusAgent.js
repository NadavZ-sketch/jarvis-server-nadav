require('dotenv').config();
const axios = require('axios');

// ─── Manus Agent — heavy/complex autonomous tasks ─────────────────────────────
//
// Manus runs tasks in its own cloud sandbox (browsing, coding, research) so
// these requests cost us zero LLM tokens. Use for multi-step work too slow or
// too large for our normal Groq/DeepSeek/Gemini chain.
//
// Real API contract (https://open.manus.im/docs/api-reference):
//   POST /v1/tasks  →  { task_id, task_url, task_title }
//   GET  /v1/tasks/{taskId}  →  { status, output, ... }
//   Auth: header name is API_KEY (override via MANUS_AUTH_HEADER)
//   Profiles: manus-1.5 | manus-1.5-lite | manus-1.6

const MANUS_API_KEY     = process.env.MANUS_API_KEY;
const MANUS_BASE        = process.env.MANUS_BASE        || 'https://api.manus.ai/v1';
const MANUS_PROFILE     = process.env.MANUS_MODEL       || 'manus-1.5';
const MANUS_AUTH_HEADER = process.env.MANUS_AUTH_HEADER || 'API_KEY';
const MANUS_TIMEOUT_MS  = parseInt(process.env.MANUS_TIMEOUT_MS || '600000', 10); // 10 min default
const MANUS_POLL_MAX_MS = parseInt(process.env.MANUS_POLL_MAX_MS || '15000', 10);

function isManusConfigured() {
    return !!MANUS_API_KEY;
}

function _authHeaders() {
    return {
        [MANUS_AUTH_HEADER]: MANUS_API_KEY,
        'Content-Type': 'application/json',
    };
}

// Extract readable text from a Manus task GET response.
function _extractAnswer(data) {
    // output may be a string, an array of messages, or a structured object
    if (!data) return null;

    if (typeof data.output === 'string' && data.output.trim()) return data.output.trim();

    if (Array.isArray(data.output) && data.output.length) {
        const last = data.output[data.output.length - 1];
        const text = last?.content || last?.text || last?.message || '';
        if (text) return String(text).trim();
    }

    if (Array.isArray(data.messages) && data.messages.length) {
        const assistantMsgs = data.messages.filter(m => m.role === 'assistant' || m.role === 'jarvis');
        const last = assistantMsgs[assistantMsgs.length - 1] || data.messages[data.messages.length - 1];
        const text = last?.content || last?.text || '';
        if (text) return String(text).trim();
    }

    // Forward-compat fallbacks
    if (data.result && typeof data.result === 'string') return data.result.trim();
    if (data.content && typeof data.content === 'string') return data.content.trim();

    return null;
}

// Poll a task until it completes or the configurable timeout is reached.
async function _pollTask(taskId) {
    const deadline  = Date.now() + MANUS_TIMEOUT_MS;
    let   delayMs   = 3000;

    while (Date.now() < deadline) {
        await new Promise(r => setTimeout(r, delayMs));
        delayMs = Math.min(delayMs * 1.5, MANUS_POLL_MAX_MS);

        const resp = await axios.get(`${MANUS_BASE}/tasks/${taskId}`, {
            headers: _authHeaders(),
            timeout: 12000,
        });

        const { status } = resp.data;

        // Treat any "done" variant as complete
        if (['completed', 'success', 'finished', 'stopped'].includes(status)) {
            const answer = _extractAnswer(resp.data);
            if (answer) return { answer, taskData: resp.data };
            // status says done but output is empty — fall through to next poll
        }

        if (['failed', 'error', 'cancelled'].includes(status)) {
            const detail = resp.data.error || resp.data.message || status;
            throw new Error(String(detail));
        }
    }

    throw new Error(`Manus task timed out after ${Math.round(MANUS_TIMEOUT_MS / 60000)} minutes`);
}

// ─── Core reusable primitive — exported for offload use ───────────────────────

async function runManusTask(prompt, opts = {}) {
    if (!MANUS_API_KEY) {
        throw new Error('MANUS_API_KEY לא מוגדר');
    }

    const profile = opts.profile || MANUS_PROFILE;

    console.debug(`[Manus] creating task (profile=${profile})`);

    const createResp = await axios.post(`${MANUS_BASE}/tasks`, {
        prompt,
        agentProfile: profile,
        hideInTaskList: false,
    }, {
        headers: _authHeaders(),
        timeout: 15000,
    });

    const taskId  = createResp.data?.task_id || createResp.data?.id;
    const taskUrl = createResp.data?.task_url || createResp.data?.share_url || '';
    if (!taskId) throw new Error('Manus did not return a task ID');

    const { answer } = await _pollTask(taskId);
    console.debug(`[Manus] task ${taskId} completed`);

    return { answer, taskUrl, taskId };
}

// ─── User-facing agent wrapper ────────────────────────────────────────────────

async function runManusAgent(userMessage, settings = {}) {
    if (!MANUS_API_KEY) {
        return { answer: '⚠️ MANUS_API_KEY לא מוגדר. הוסף אותו בהגדרות הסביבה של השרת.' };
    }

    // Enrich the prompt with user context when available
    const userName = settings.userName || '';
    const memories = settings.userMemories ? `\n\nהקשר על המשתמש:\n${settings.userMemories}` : '';
    const prompt = userMessage + memories;

    try {
        const { answer, taskUrl } = await runManusTask(prompt);
        const link = taskUrl ? `\n\n🔗 [צפה במשימה ב-Manus](${taskUrl})` : '';
        return { answer: answer + link };
    } catch (err) {
        const detail = err.response?.data?.error || err.response?.data?.message || err.message;
        console.error('🦾 Manus error:', detail);
        return {
            answer: `⚠️ Manus לא הצליח להשלים את המשימה: ${detail}`,
        };
    }
}

module.exports = { runManusAgent, runManusTask, isManusConfigured };
