// ─── Provider configuration — single source of truth for the LLM chain ───────
//
// Pure data + resolvers. No network calls live here. `agents/models.js` consumes
// these descriptors to build requests, so adding/reordering a provider or
// changing a timeout only touches this file.
//
// Per-request overrides (cloud provider preference, temperature, local Ollama
// url/model) arrive as a `settings`-shaped object and are honored by the
// `url`/`model`/`enabled` resolver functions and by `resolveChain`.

// Lazily read env at call time (not import time) so .env load order / test stubs
// don't matter.
const PROVIDERS = {
    ollama: {
        id: 'ollama',
        openaiCompatible: true,
        timeout: 15000,
        // Honor the mobile wizard's settings first, then the OLLAMA_URL env var.
        url:   (s = {}) => s.localServerUrl || process.env.OLLAMA_URL || null,
        model: (s = {}) => s.localModelName || process.env.OLLAMA_MODEL || 'gemma4:e4b',
        keyEnv: null,
        enabled: (s = {}) => !!(s.localServerUrl || process.env.OLLAMA_URL),
    },
    groq: {
        id: 'groq',
        openaiCompatible: true,
        timeout: 7000,
        url:   () => 'https://api.groq.com/openai/v1/chat/completions',
        model: () => 'llama-3.3-70b-versatile',
        keyEnv: 'GROQ_API_KEY',
        // Always attempted (primary cloud); a missing key fails fast and falls through.
        enabled: () => true,
    },
    deepseek: {
        id: 'deepseek',
        openaiCompatible: true,
        timeout: 9000,
        url:   () => 'https://api.deepseek.com/chat/completions',
        model: () => 'deepseek-chat',
        keyEnv: 'DEEPSEEK_API_KEY',
        enabled: () => true,
    },
    openrouter: {
        id: 'openrouter',
        openaiCompatible: true,
        timeout: 10000,
        url:   () => 'https://openrouter.ai/api/v1/chat/completions',
        model: (s = {}) => s.openrouterModel || process.env.OPENROUTER_MODEL || 'meta-llama/llama-3.3-70b-instruct:free',
        keyEnv: 'OPENROUTER_API_KEY',
        extraHeaders: () => ({
            'HTTP-Referer': process.env.OPENROUTER_REFERER || 'https://jarvis-server',
            'X-Title': 'Jarvis',
        }),
        enabled: () => !!process.env.OPENROUTER_API_KEY,
    },
    gemini: {
        id: 'gemini',
        openaiCompatible: false, // uses the Gemini generateContent payload
        timeout: 15000,
        keyEnv: 'GOOGLE_API_KEY',
        // Terminal fallback — always attempted.
        enabled: () => true,
    },
};

// Default cloud failover order when no specific provider is requested.
const CLOUD_DEFAULT_ORDER = ['groq', 'deepseek', 'openrouter', 'gemini'];

// Build the ordered provider chain for a request.
//   - useLocal === true → strict local: ['ollama'] only, no cloud fallback.
//     (A local failure surfaces as an error rather than silently using cloud.)
//   - otherwise → cloud order with the chosen `cloudProvider` moved to the front,
//     the rest kept as fallback.
function resolveChain({ useLocal = false, cloudProvider = null } = {}) {
    if (useLocal) return ['ollama'];
    let cloud = [...CLOUD_DEFAULT_ORDER];
    if (cloudProvider && cloud.includes(cloudProvider)) {
        cloud = [cloudProvider, ...cloud.filter(p => p !== cloudProvider)];
    }
    return cloud;
}

// Clamp a user-supplied temperature to a sane range; fall back to 0.5.
function clampTemp(t) {
    return (typeof t === 'number' && t >= 0 && t <= 2) ? t : 0.5;
}

// Raised when strict-local inference fails, so the request handler can show a
// clear Hebrew message instead of a raw stack/timeout.
class LocalModelError extends Error {
    constructor(message, { url, model } = {}) {
        super(message);
        this.name = 'LocalModelError';
        this.url = url;
        this.model = model;
    }
}

module.exports = { PROVIDERS, CLOUD_DEFAULT_ORDER, resolveChain, clampTemp, LocalModelError };
