// API probe — hits the running server with sample Hebrew queries and a few GETs.
// Returns findings + samples for the UX probe to grade.

const axios = require('axios');

const DEFAULT_QUERIES = [
    'מה מזג האוויר בתל אביב?',
    'הוסף משימה: קנה חלב',
    'תזכיר לי בעוד שעה לבדוק',
    'שלום, מה שלומך?',
    'נסח לי הודעת מייל לבוס',
];

const GET_ENDPOINTS = [
    { path: '/health',        expect: 'object' },
    { path: '/tasks',         expect: 'array'  },
    { path: '/reminders',     expect: 'array'  },
    { path: '/notes',         expect: 'array'  },
    { path: '/chat-history',  expect: 'array'  },
];

const HEBREW_RE = /[֐-׿]/;

function classifyLatency(ms) {
    if (ms > 5000) return 'high';
    if (ms > 2000) return 'medium';
    return null;
}

async function runApiProbe({ baseUrl = 'http://localhost:3000', learnedContext = {} } = {}) {
    const findings = [];
    const samples = [];

    const queries = [
        ...(learnedContext.sampleBank || []),
        ...DEFAULT_QUERIES,
    ];
    const seen = new Set();
    const dedup = queries.filter(q => {
        const k = q.trim();
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
    }).slice(0, 15);

    // GET endpoints — quick correctness + latency
    for (const ep of GET_ENDPOINTS) {
        const t0 = Date.now();
        try {
            const res = await axios.get(`${baseUrl}${ep.path}`, { timeout: 8000 });
            const elapsed = Date.now() - t0;
            const isArray = Array.isArray(res.data);
            const okShape = ep.expect === 'array' ? isArray : (res.data && typeof res.data === 'object');

            if (!okShape) {
                findings.push({
                    severity: 'high', category: 'reliability',
                    target: `GET ${ep.path}`,
                    finding: `Unexpected response shape (expected ${ep.expect}).`,
                    recommendation: 'Verify route handler returns the documented type.',
                    latency_ms: elapsed,
                });
            }
            const sev = classifyLatency(elapsed);
            if (sev) {
                findings.push({
                    severity: sev, category: 'performance',
                    target: `GET ${ep.path}`,
                    finding: `Slow response: ${elapsed}ms.`,
                    recommendation: 'Profile the handler; consider caching or pagination.',
                    latency_ms: elapsed,
                });
            }
        } catch (err) {
            const status = err.response?.status;
            findings.push({
                severity: 'critical', category: 'reliability',
                target: `GET ${ep.path}`,
                finding: status ? `HTTP ${status}: ${err.message}` : `Network error: ${err.message}`,
                recommendation: 'Ensure the server is running and the route is registered.',
                latency_ms: Date.now() - t0,
            });
        }
    }

    // POST /ask-jarvis — Hebrew sample queries
    for (const query of dedup) {
        const t0 = Date.now();
        try {
            const res = await axios.post(`${baseUrl}/ask-jarvis`, { command: query }, { timeout: 30000 });
            const elapsed = Date.now() - t0;
            const answer = (res.data && res.data.answer) || '';
            samples.push({ query, answer, latency_ms: elapsed });

            if (!answer) {
                findings.push({
                    severity: 'high', category: 'quality',
                    target: 'POST /ask-jarvis',
                    finding: `Empty answer for: "${query}"`,
                    recommendation: 'Check agent dispatch and fallback messaging.',
                    latency_ms: elapsed,
                });
            } else if (!HEBREW_RE.test(answer)) {
                findings.push({
                    severity: 'high', category: 'quality',
                    target: 'POST /ask-jarvis',
                    finding: `Non-Hebrew answer for: "${query}" → "${answer.slice(0, 60)}"`,
                    recommendation: 'Force Hebrew system prompt for this intent.',
                    latency_ms: elapsed,
                });
            }
            const sev = classifyLatency(elapsed);
            if (sev) {
                findings.push({
                    severity: sev, category: 'performance',
                    target: 'POST /ask-jarvis',
                    finding: `Slow response (${elapsed}ms) for "${query}"`,
                    recommendation: 'Profile router + agent path; cache memories or shorten prompt.',
                    latency_ms: elapsed,
                });
            }
        } catch (err) {
            const status = err.response?.status;
            findings.push({
                severity: 'critical', category: 'reliability',
                target: 'POST /ask-jarvis',
                finding: status ? `HTTP ${status} on "${query}": ${err.message}` : `Network error on "${query}": ${err.message}`,
                recommendation: 'Inspect server logs around this query.',
                latency_ms: Date.now() - t0,
            });
        }
    }

    return { findings, samples };
}

module.exports = { runApiProbe, DEFAULT_QUERIES };
