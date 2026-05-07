// Static code scan — extends the securityAgent prompt with performance + ux_backend categories.
// Always uses cloud (useLocal=false) because local models miss subtle issues.

const fs = require('fs');
const path = require('path');
const { callGemma4 } = require('../models');

const BASE_DIR = path.join(__dirname, '..', '..');

const FULL_BUDGET = 4000;
const STABLE_BUDGET = 1500;

function listSources() {
    const files = ['server.js'];
    const dirs = ['agents', 'agents/e2e', 'services'];
    for (const d of dirs) {
        const abs = path.join(BASE_DIR, d);
        try {
            for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
                if (entry.isFile() && entry.name.endsWith('.js')) {
                    files.push(path.join(d, entry.name).replace(/\\/g, '/'));
                }
            }
        } catch { /* dir may not exist */ }
    }
    return Array.from(new Set(files));
}

function readFiles(files, stableTargets) {
    const stable = new Set(stableTargets || []);
    const out = {};
    for (const rel of files) {
        try {
            const src = fs.readFileSync(path.join(BASE_DIR, rel), 'utf8');
            const budget = stable.has(rel) ? STABLE_BUDGET : FULL_BUDGET;
            out[rel] = src.length > budget ? src.slice(0, budget) + '\n// ... (truncated)' : src;
        } catch (err) {
            console.warn(`staticScan: cannot read ${rel}: ${err.message}`);
        }
    }
    return out;
}

function buildPrompt(codeBlock) {
    return `אתה מומחה Node.js, אבטחת מידע, ביצועים וחווית פיתוח. סרוק את הקוד הבא ומצא ממצאים בקטגוריות:

1. 🔴 critical — חשיפת מפתחות, הזרקת קוד, חוסר אימות
2. 🟠 high — קריסת שרת, אובדן נתונים, טיפול שגוי בשגיאות
3. 🟡 medium — race conditions, logic bugs, חוסר validation
4. 🟢 low — שיפורים מומלצים, code quality

קטגוריות נושא: security | bug | performance | reliability | ux_backend
- performance: I/O סינכרוני בלולאות, חוסר caching, latency hotspots
- ux_backend: הודעות שגיאה לא ברורות, חוסר Hebrew בתשובות, תגובות לא עקביות

החזר JSON תקין בלבד (ללא markdown):
{
  "findings": [
    {"severity":"critical|high|medium|low","category":"security|bug|performance|reliability|ux_backend","file":"<path>","issue":"<short>","fix":"<recommendation>"}
  ],
  "summary": "<1-2 sentences>",
  "score": 0
}

קוד הפרויקט:
${codeBlock}`;
}

async function runStaticScan({ learnedContext = {} } = {}) {
    const all = listSources();
    const hot = new Set(learnedContext.hotTargets || []);
    const ordered = [...all].sort((a, b) => (hot.has(b) ? 1 : 0) - (hot.has(a) ? 1 : 0));

    const files = readFiles(ordered, learnedContext.stableTargets);
    const codeBlock = Object.entries(files)
        .map(([name, src]) => `// ── ${name} ──\n${src}`)
        .join('\n\n');

    let raw = '';
    try { raw = await callGemma4(buildPrompt(codeBlock), false, 1500); }
    catch (e) { console.warn('staticScan LLM failed:', e.message); }

    const m = raw.match(/\{[\s\S]*"findings"[\s\S]*\}/);
    let report = null;
    if (m) { try { report = JSON.parse(m[0]); } catch { /* fallback */ } }

    if (!report || !Array.isArray(report.findings)) {
        return { findings: [], summary: '', score: null };
    }

    const findings = report.findings.map(f => ({
        severity: f.severity || 'low',
        category: f.category || 'bug',
        target: f.file || 'unknown',
        finding: f.issue || '',
        recommendation: f.fix || '',
    }));

    return { findings, summary: report.summary || '', score: report.score ?? null };
}

module.exports = { runStaticScan };
