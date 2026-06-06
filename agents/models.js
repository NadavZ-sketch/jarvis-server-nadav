require('dotenv').config();
const axios    = require('axios');
const readline = require('readline');
const { AsyncLocalStorage } = require('async_hooks');
const { PROVIDERS, resolveChain, clampTemp, LocalModelError } = require('./providerConfig');

// ─── Provider tracking + per-request options ──────────────────────────────
// Wrap a request with providerContext.run({ opts }, fn). Any provider call
// inside records which provider answered (read via getCurrentProvider()), and
// callGemma4/callGemma4Stream pick up per-request `opts` (cloudProvider,
// temperature, local url/model) from the store when not passed explicitly.
// This lets all ~44 callGemma4 call sites honor user settings without edits.
const providerContext = new AsyncLocalStorage();
function _setProvider(name) {
    const store = providerContext.getStore();
    if (store) store.provider = name;
}
function getCurrentProvider() {
    return providerContext.getStore()?.provider || null;
}
// Merge explicit opts arg with request-scoped opts from the store (arg wins).
function _resolveOpts(opts) {
    const fromStore = providerContext.getStore()?.opts || {};
    return { ...fromStore, ...(opts || {}) };
}

// ─── Gemini (Google) — for live search agents (chat, sports) ───────────────
const GEMINI_MODEL = 'gemini-2.5-flash-lite';
const GOOGLE_KEY = process.env.GOOGLE_API_KEY;
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';
const GEMINI_URL = `${GEMINI_BASE}/${GEMINI_MODEL}:generateContent?key=${GOOGLE_KEY}`;

// Cloud/local provider descriptors (urls, models, timeouts, keys) and the
// failover chain live in agents/providerConfig.js — the single source of truth.

// ─── Shared sampling parameter ────────────────────────────────────────────
// Pin top_p across all providers so the same prompt yields a consistent style
// regardless of which provider answered. Temperature is per-request (honors
// settings.temperature via clampTemp), defaulting to 0.5 when unset.
const LLM_TOP_P = 0.9;

// Convert OpenAI-style messages → Gemini contents + systemInstruction.
// Preserves role boundaries (instead of flattening to a single string), so
// the Gemini fallback keeps the same identity/context as the primary path.
function _msgsToGeminiPayload(msgs, generationConfig = {}) {
    const systemMsg = msgs.find(m => m.role === 'system');
    const contents = msgs
        .filter(m => m.role !== 'system')
        .map(m => ({
            role: m.role === 'assistant' ? 'model' : 'user',
            parts: [{ text: m.content }],
        }));
    // Gemini requires at least one user message; if the only content was system
    // (rare), fold it into a user turn so the API does not 400.
    if (contents.length === 0) {
        contents.push({ role: 'user', parts: [{ text: systemMsg?.content || '' }] });
    }
    const payload = { contents, generationConfig };
    if (systemMsg?.content) {
        payload.systemInstruction = { parts: [{ text: systemMsg.content }] };
    }
    return payload;
}

// Build axios headers for an OpenAI-compatible provider descriptor.
function _providerHeaders(provider) {
    const headers = { 'Content-Type': 'application/json' };
    if (provider.keyEnv && process.env[provider.keyEnv]) {
        headers['Authorization'] = `Bearer ${process.env[provider.keyEnv]}`;
    }
    if (provider.extraHeaders) Object.assign(headers, provider.extraHeaders());
    return headers;
}

// Single non-streaming call to one provider. Returns trimmed text or throws.
async function _callProvider(provider, msgs, maxTokens, temperature, settings) {
    if (provider.openaiCompatible) {
        const url = `${provider.url(settings).replace(/\/$/, '')}`;
        // Ollama exposes the OpenAI-compatible API under /v1/chat/completions.
        const endpoint = provider.id === 'ollama' ? `${url}/v1/chat/completions` : url;
        const response = await axios.post(endpoint, {
            model: provider.model(settings), messages: msgs, max_tokens: maxTokens,
            temperature, top_p: LLM_TOP_P,
        }, { headers: _providerHeaders(provider), timeout: provider.timeout });
        const content = response.data.choices[0].message.content.trim();
        // Groq occasionally returns infrastructure errors as completion text
        // instead of HTTP errors — treat those as a failure so we fall through.
        if (provider.id === 'groq' &&
            /^(API Error:|Stream idle timeout|internal server error)/i.test(content)) {
            throw new Error(content);
        }
        return content;
    }
    // Gemini — preserves system/user/assistant role boundaries so identity and
    // conversation context survive across the fallback.
    const payload = _msgsToGeminiPayload(msgs, {
        temperature, topP: LLM_TOP_P, maxOutputTokens: maxTokens,
    });
    const response = await axios.post(GEMINI_URL, payload, { timeout: provider.timeout });
    return response.data.candidates[0].content.parts[0].text.trim();
}

async function callGemma4(messages, useLocal = true, maxTokens = 800, opts = {}) {
    const msgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    const o = _resolveOpts(opts);
    const temperature = clampTemp(o.temperature);
    const chain = resolveChain({ useLocal, cloudProvider: o.cloudProvider });
    const strictLocal = useLocal;

    let lastErr = null;
    for (const id of chain) {
        const provider = PROVIDERS[id];
        if (!provider) continue;
        // Skip providers that can't run this request (e.g. OpenRouter without a
        // key, Ollama without a configured url) — they fall through to the next.
        if (provider.enabled && !provider.enabled(o)) continue;
        try {
            const content = await _callProvider(provider, msgs, maxTokens, temperature, o);
            _setProvider(id);
            return content;
        } catch (err) {
            lastErr = err;
            const detail = err.response?.data ? JSON.stringify(err.response.data) : err.message;
            console.warn(`⚠️ Provider "${id}" failed${chain.length > 1 ? ', trying next' : ''}:`, detail);
        }
    }

    // Strict local: surface a clean, typed error so the handler can show a clear
    // Hebrew message instead of a raw stack/timeout.
    if (strictLocal) {
        const p = PROVIDERS.ollama;
        throw new LocalModelError('Local model unavailable', {
            url: p.url(o), model: p.model(o),
        });
    }
    throw lastErr || new Error('All providers failed');
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

// ─── Streaming variant: config-driven chain, Gemini non-stream terminal ───────

// Stream one OpenAI-compatible provider's SSE response into onChunk.
async function _streamProvider(provider, msgs, maxTokens, temperature, settings, onChunk, signal) {
    const url = provider.url(settings).replace(/\/$/, '');
    const endpoint = provider.id === 'ollama' ? `${url}/v1/chat/completions` : url;
    const response = await axios.post(endpoint, {
        model: provider.model(settings), messages: msgs, max_tokens: maxTokens, stream: true,
        temperature, top_p: LLM_TOP_P,
    }, {
        headers: _providerHeaders(provider),
        responseType: 'stream',
        timeout: provider.timeout,
        ...(signal ? { signal } : {}),
    });
    // parseSSEStream resolves (complete or partial chunks) or rejects (no data +
    // error/timeout). On resolve we're done — even a partial response beats a
    // fallback that appends.
    await parseSSEStream(response.data, onChunk);
}

async function callGemma4Stream(messages, useLocal = true, onChunk, signal = null, maxTokens = 800, opts = {}) {
    const msgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    const o = _resolveOpts(opts);
    const temperature = clampTemp(o.temperature);
    const chain = resolveChain({ useLocal, cloudProvider: o.cloudProvider });
    const strictLocal = useLocal;

    let lastErr = null;
    for (const id of chain) {
        const provider = PROVIDERS[id];
        if (!provider) continue;
        if (provider.enabled && !provider.enabled(o)) continue;
        try {
            if (provider.openaiCompatible) {
                await _streamProvider(provider, msgs, maxTokens, temperature, o, onChunk, signal);
            } else {
                // Gemini — non-streaming terminal fallback; emit the full text as one chunk.
                const payload = _msgsToGeminiPayload(msgs, {
                    temperature, topP: LLM_TOP_P, maxOutputTokens: maxTokens,
                });
                const response = await axios.post(GEMINI_URL, payload,
                    { timeout: provider.timeout, ...(signal ? { signal } : {}) });
                onChunk(response.data.candidates[0].content.parts[0].text.trim());
            }
            _setProvider(id);
            return;
        } catch (err) {
            if (err.name === 'CanceledError' || err.name === 'AbortError') throw err;
            lastErr = err;
            console.warn(`⚠️ Provider "${id}" stream failed${chain.length > 1 ? ', trying next' : ''}:`, err.message);
        }
    }

    if (strictLocal) {
        const p = PROVIDERS.ollama;
        throw new LocalModelError('Local model unavailable', { url: p.url(o), model: p.model(o) });
    }
    throw lastErr || new Error('All streaming providers failed');
}

// ─── Tool-calling loop (OpenAI-compatible providers only) ────────────────────
//
// callWithTools drives a full tool-use loop: if the model returns tool_calls,
// they are executed via `callToolFn` and appended as tool results before the
// next completion round. When the model returns plain text the loop exits.
//
// callGemma4 / callGemma4Stream are NOT touched — this is purely additive.

async function callWithTools(messages, {
    tools = [],
    callTool: callToolFn,
    useLocal = false,
    maxTokens = 800,
    maxIterations = 5,
    opts = {},
} = {}) {
    const initialMsgs = typeof messages === 'string'
        ? [{ role: 'user', content: messages }]
        : messages;

    const o = _resolveOpts(opts);
    const temperature = clampTemp(o.temperature);

    // Gemini uses a different payload format and does not support tool_calls in
    // the OpenAI sense — filter it out of the chain for this function.
    const chain = resolveChain({ useLocal, cloudProvider: o.cloudProvider })
        .filter(id => PROVIDERS[id]?.openaiCompatible);

    if (chain.length === 0) {
        throw new Error('No OpenAI-compatible provider available for tool calling');
    }

    for (const id of chain) {
        const provider = PROVIDERS[id];
        if (!provider) continue;
        if (provider.enabled && !provider.enabled(o)) continue;

        try {
            const url = provider.url(o).replace(/\/$/, '');
            const endpoint = provider.id === 'ollama' ? `${url}/v1/chat/completions` : url;
            const currentMsgs = [...initialMsgs];

            for (let i = 0; i < maxIterations; i++) {
                const body = {
                    model: provider.model(o), messages: currentMsgs,
                    max_tokens: maxTokens, temperature, top_p: LLM_TOP_P,
                };
                if (tools.length > 0) {
                    body.tools = tools;
                    body.tool_choice = 'auto';
                }

                const response = await axios.post(endpoint, body, {
                    headers: _providerHeaders(provider), timeout: provider.timeout,
                });

                const message    = response.data.choices[0].message;
                const toolCalls  = message.tool_calls;

                if (toolCalls && toolCalls.length > 0) {
                    currentMsgs.push({
                        role: 'assistant', content: message.content || null, tool_calls: toolCalls,
                    });
                    for (const tc of toolCalls) {
                        let toolResult;
                        try {
                            const args = typeof tc.function.arguments === 'string'
                                ? JSON.parse(tc.function.arguments)
                                : (tc.function.arguments || {});
                            toolResult = callToolFn
                                ? await callToolFn(tc.function.name, args)
                                : `Tool ${tc.function.name} not available`;
                        } catch (err) {
                            toolResult = `Error in tool ${tc.function.name}: ${err.message}`;
                        }
                        currentMsgs.push({
                            role: 'tool', tool_call_id: tc.id,
                            content: typeof toolResult === 'string' ? toolResult : JSON.stringify(toolResult),
                        });
                    }
                    continue; // next iteration with tool results appended
                }

                // No tool_calls → final text answer
                const content = (message.content || '').trim();
                if (provider.id === 'groq' &&
                    /^(API Error:|Stream idle timeout|internal server error)/i.test(content)) {
                    throw new Error(content);
                }
                _setProvider(id);
                return content;
            }

            // maxIterations exhausted — return the last assistant message if any
            const lastAssistant = [...currentMsgs].reverse().find(m => m.role === 'assistant');
            _setProvider(id);
            return (lastAssistant?.content || '').trim();

        } catch (err) {
            const detail = err.response?.data ? JSON.stringify(err.response.data) : err.message;
            console.warn(`⚠️ callWithTools "${id}" failed${chain.length > 1 ? ', trying next' : ''}:`, detail);
        }
    }

    throw new Error('All OpenAI-compatible providers failed for tool calling');
}

// ─── Gemini with Google Search grounding (real-time data) ─────────────────────

async function callGeminiWithSearch(prompt) {
    const response = await axios.post(GEMINI_URL, {
        contents: [{ parts: [{ text: prompt }] }],
        tools: [{ google_search: {} }]
    });
    _setProvider('gemini');
    return response.data.candidates[0].content.parts[0].text.trim();
}

// ─── Gemini Vision (image + text) ─────────────────────────────────────────────

function detectMimeType(base64) {
    if (base64.startsWith('/9j/'))  return 'image/jpeg';
    if (base64.startsWith('iVBOR')) return 'image/png';
    if (base64.startsWith('UklGR')) return 'image/webp';
    return 'image/jpeg';
}

const MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10 MB decoded
async function callGeminiVision(prompt, imageBase64) {
    if (imageBase64.length > Math.ceil(MAX_IMAGE_BYTES * 4 / 3)) {
        throw new Error('Image too large (max 10 MB)');
    }
    const response = await axios.post(GEMINI_URL, {
        contents: [{
            parts: [
                { text: prompt },
                { inline_data: { mime_type: detectMimeType(imageBase64), data: imageBase64 } }
            ]
        }]
    });
    _setProvider('gemini');
    return response.data.candidates[0].content.parts[0].text.trim();
}

module.exports = { GEMINI_URL, callGemma4, callGemma4Stream, callGeminiWithSearch, callGeminiVision, callWithTools, detectMimeType, providerContext, getCurrentProvider, LocalModelError };
