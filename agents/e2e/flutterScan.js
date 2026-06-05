// Flutter UI consistency scan — reads .dart files and asks the LLM to flag
// RTL violations, theme inconsistencies, accessibility gaps, navigation drift,
// and hard-coded English strings.

const fs = require('fs');
const path = require('path');
const { callGemma4 } = require('../models');

const FLUTTER_LIB = path.join(__dirname, '..', '..', 'jarvis_mobile', 'lib');
const PER_FILE_BUDGET = 3000;
const PER_CALL_BUDGET = 12000;

function walk(dir, out = []) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch { return out; }
    for (const e of entries) {
        const abs = path.join(dir, e.name);
        if (e.isDirectory()) walk(abs, out);
        else if (e.isFile() && e.name.endsWith('.dart')) out.push(abs);
    }
    return out;
}

function relPath(abs) {
    return path.relative(path.join(__dirname, '..', '..'), abs).replace(/\\/g, '/');
}

async function chunkFiles(files, budget) {
    const chunks = [];
    let cur = [], used = 0;
    for (const abs of files) {
        let src;
        try { src = await fs.promises.readFile(abs, 'utf8'); } catch { continue; }
        const trimmed = src.length > PER_FILE_BUDGET ? src.slice(0, PER_FILE_BUDGET) + '\n// ... (truncated)' : src;
        if (used + trimmed.length > budget && cur.length) {
            chunks.push(cur);
            cur = []; used = 0;
        }
        cur.push({ rel: relPath(abs), src: trimmed });
        used += trimmed.length;
    }
    if (cur.length) chunks.push(cur);
    return chunks;
}

const PROMPT_HEADER = `אתה מבקר UI של אפליקציית Flutter בעברית (RTL-first).
סרוק את קבצי ה-Dart ומצא בעיות בקטגוריות:
- ui: הפרות RTL בקוד שמציג עברית (Row/Text/ListView ללא TextDirection.rtl)
- ui: חוסר עקביות תמה — צבעים/TextStyle בקוד במקום Theme.of(context)
- accessibility: חוסר Semantics/tooltip על widgets אינטראקטיביים
- ui: שימוש ב-MaterialPageRoute במקום slide_fade_route
- ux_backend: מחרוזות אנגלית קשיחות בזרימות משתמש בעברית

החזר JSON בלבד (ללא markdown):
{"findings":[{"severity":"critical|high|medium|low","category":"ui|accessibility|ux_backend","file":"<path:line>","issue":"<short>","fix":"<recommendation>"}]}

קבצים:
`;

async function scanChunk(chunk) {
    const block = chunk.map(({ rel, src }) => `// ── ${rel} ──\n${src}`).join('\n\n');
    let raw = '';
    try { raw = await callGemma4(PROMPT_HEADER + block, false, 1200); }
    catch (e) { console.warn('flutterScan chunk failed:', e.message); return []; }

    const m = raw.match(/\{[\s\S]*"findings"[\s\S]*\}/);
    if (!m) return [];
    let report;
    try { report = JSON.parse(m[0]); } catch { return []; }
    if (!Array.isArray(report.findings)) return [];

    return report.findings.map(f => ({
        severity: f.severity || 'low',
        category: f.category || 'ui',
        target: f.file || 'unknown',
        finding: f.issue || '',
        recommendation: f.fix || '',
    }));
}

async function runFlutterScan({ learnedContext = {} } = {}) {
    try { await fs.promises.access(FLUTTER_LIB); } catch { return { findings: [] }; }

    const all = walk(FLUTTER_LIB);
    const hot = new Set(learnedContext.hotTargets || []);
    all.sort((a, b) => {
        const ah = hot.has(relPath(a)) ? 1 : 0;
        const bh = hot.has(relPath(b)) ? 1 : 0;
        return bh - ah;
    });

    const chunks = await chunkFiles(all, PER_CALL_BUDGET);
    const all_findings = [];
    for (const chunk of chunks) {
        const f = await scanChunk(chunk);
        all_findings.push(...f);
    }
    return { findings: all_findings };
}

module.exports = { runFlutterScan };
