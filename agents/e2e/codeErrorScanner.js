// Code error scanner — detects runtime bugs and anti-patterns via regex (Phase 1)
// then deepens analysis via LLM (Phase 2).
// Produces normalized findings + a Claude Code / Codex-ready prompt block.

const fs   = require('fs');
const path = require('path');
const { callGemma4 } = require('../models');

const BASE_DIR    = path.join(__dirname, '..', '..');
const FULL_BUDGET   = 4000;
const STABLE_BUDGET = 1500;

// ── Regex rules (Phase 1 — fast, deterministic) ───────────────────────────────
// Each rule: { id, pattern, severity, category, finding, recommendation }
const REGEX_RULES = [
    {
        id: 'eval_usage',
        pattern: /\beval\s*\(/g,
        severity: 'critical',
        category: 'security',
        finding: 'שימוש ב-eval() — חשיפה להזרקת קוד מצד משתמש',
        recommendation: 'הסר את eval() והחלף בפרסור בטוח (JSON.parse, switch/case, או מיפוי פונקציות)',
    },
    {
        id: 'hardcoded_secret',
        pattern: /(?:password|secret|apikey|api_key|token)\s*[:=]\s*['"][^'"]{4,}/gi,
        severity: 'critical',
        category: 'security',
        finding: 'מחרוזת סוד / מפתח hard-coded בקוד',
        recommendation: 'העבר לקובץ .env והשתמש ב-process.env.VARIABLE_NAME',
    },
    {
        id: 'process_exit',
        pattern: /\bprocess\.exit\s*\(/g,
        severity: 'high',
        category: 'reliability',
        finding: 'קריאה ל-process.exit() — עלולה להרוג את השרת בזמן ריצה',
        recommendation: 'השתמש במנגנון graceful shutdown בלבד (signal handlers בהפעלה)',
    },
    {
        id: 'unhandled_promise',
        pattern: /\.then\s*\([^)]*\)\s*(?![\s\S]{0,30}\.catch)/g,
        severity: 'high',
        category: 'reliability',
        finding: 'Promise chain ללא .catch() — Unhandled rejection יקריס את השרת',
        recommendation: 'הוסף .catch(err => console.error(err)) לכל .then() chain',
    },
    {
        id: 'sync_io',
        pattern: /\bfs\.(readFileSync|writeFileSync|appendFileSync|existsSync|mkdirSync)\s*\(/g,
        severity: 'medium',
        category: 'performance',
        finding: 'קריאת/כתיבת קובץ סינכרונית — חוסמת את ה-Event Loop',
        recommendation: 'החלף ב-fs.promises.readFile / writeFile עם await',
    },
    {
        id: 'var_declaration',
        pattern: /\bvar\s+[a-zA-Z_$]/g,
        severity: 'low',
        category: 'bug',
        finding: 'שימוש ב-var — עלול לגרום לבעיות scoping בלתי צפויות',
        recommendation: 'החלף ב-const (ברירת מחדל) או let (אם נדרש שינוי)',
    },
    {
        id: 'loose_null_check',
        pattern: /[^!=<>]==[^=]null|[^!=<>]!=null(?!=)/g,
        severity: 'low',
        category: 'bug',
        finding: 'בדיקת null באמצעות == / != (loose equality) — עלולה לכלול undefined בטעות',
        recommendation: 'השתמש ב-=== null או !== null לבדיקה מדויקת',
    },
    {
        id: 'console_log_prod',
        pattern: /\bconsole\.log\s*\(/g,
        severity: 'low',
        category: 'ux_backend',
        finding: 'console.log() בקוד — מאט את הפרודקשן ומדליף מידע פנימי',
        recommendation: 'החלף ב-console.warn / console.error לשגיאות, או הסר לוגים שאינם דרושים',
    },
    {
        id: 'new_function',
        pattern: /\bnew\s+Function\s*\(/g,
        severity: 'critical',
        category: 'security',
        finding: 'שימוש ב-new Function() — שווה ערך ל-eval(), חשיפה להזרקת קוד',
        recommendation: 'הסר ועבור לפתרון סטטי (switch, map, require)',
    },
    {
        id: 'missing_await_supabase',
        // Multiline: match lines that have supabase.from().<op>() but no `await` on the same line
        pattern: /^(?![^\n]*\bawait\b)[^\n]*\bsupabase\s*\.\s*from\s*\([^)]+\)\s*\.\s*(?:select|insert|update|delete|upsert)\s*\(/gm,
        severity: 'high',
        category: 'bug',
        finding: 'קריאת Supabase ללא await — לא ממתינים לתוצאה, הנתונים לא ייקלטו',
        recommendation: 'הוסף await לפני supabase.from(...).select/insert/...()',
    },
];

// ── File discovery (same pattern as staticScan) ───────────────────────────────
// Exclude this scanner itself to avoid false positives from its own regex pattern strings.
const SELF_REL = 'agents/e2e/codeErrorScanner.js';

function listSources() {
    const files = ['server.js'];
    const dirs = ['agents', 'agents/e2e', 'services'];
    for (const d of dirs) {
        const abs = path.join(BASE_DIR, d);
        try {
            for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
                if (entry.isFile() && entry.name.endsWith('.js')) {
                    const rel = path.join(d, entry.name).replace(/\\/g, '/');
                    if (rel !== SELF_REL) files.push(rel);
                }
            }
        } catch { /* dir may not exist */ }
    }
    return Array.from(new Set(files));
}

async function readFiles(files, stableTargets) {
    const stable = new Set(stableTargets || []);
    const out = {};
    await Promise.all(files.map(async (rel) => {
        try {
            const src = await fs.promises.readFile(path.join(BASE_DIR, rel), 'utf8');
            const budget = stable.has(rel) ? STABLE_BUDGET : FULL_BUDGET;
            out[rel] = src.length > budget ? src.slice(0, budget) + '\n// ... (truncated)' : src;
        } catch (err) {
            console.warn(`codeErrorScanner: cannot read ${rel}: ${err.message}`);
        }
    }));
    return out;
}

// ── Phase 1: Regex-based pattern scan ────────────────────────────────────────
function patternScan(fileContents) {
    const findings = [];
    for (const [relPath, src] of Object.entries(fileContents)) {
        const lines = src.split('\n');
        for (const rule of REGEX_RULES) {
            // Reset lastIndex for global patterns
            rule.pattern.lastIndex = 0;
            let match;
            while ((match = rule.pattern.exec(src)) !== null) {
                // Calculate line number from match index
                const lineNum = src.slice(0, match.index).split('\n').length;
                // Skip matches inside comments
                const lineText = lines[lineNum - 1] || '';
                if (/^\s*\/\//.test(lineText)) continue;

                findings.push({
                    severity: rule.severity,
                    category: rule.category,
                    target: `${relPath}:${lineNum}`,
                    finding: rule.finding,
                    recommendation: rule.recommendation,
                    source: 'pattern',
                });
                // For non-global patterns, break after first match per file per rule
                if (!rule.pattern.global) break;
                // Avoid infinite loops for zero-width matches
                if (match.index === rule.pattern.lastIndex) rule.pattern.lastIndex++;
            }
            rule.pattern.lastIndex = 0;
        }
    }
    return findings;
}

// ── Phase 2: LLM deep analysis ────────────────────────────────────────────────
function buildLLMPrompt(codeBlock, existingFindings) {
    const knownTargets = existingFindings.slice(0, 10).map(f => `${f.target}: ${f.finding}`).join('\n');
    return `אתה בודק שגיאות קוד Node.js/Express מומחה. מצא שגיאות לוגיקה, race conditions, ו-edge cases שלא ניתן לזהות ב-regex.

אל תחזור על הממצאים האלה שכבר נמצאו:
${knownTargets || '(אין)'}

חפש בעיות כגון:
- לוגיקה שגויה בתנאים (if/else, switch)
- פרמטרים שנשכחו או הוחלפו
- race condition ב-async/await
- missing validation על קלט שהשתנה בדרך
- תשובות שגויות בעברית (תשובה בשפה הלא נכונה)
- חוסר עקביות בפורמט תשובות בין endpoints שונים

החזר JSON תקין בלבד (ללא markdown):
{
  "findings": [
    {
      "severity": "critical|high|medium|low",
      "category": "bug|reliability|performance|ux_backend|security",
      "target": "<file:line or endpoint>",
      "finding": "<תיאור קצר בעברית>",
      "recommendation": "<המלצה ספציפית לתיקון בעברית>"
    }
  ],
  "summary": "<1-2 משפטים בעברית על מצב הקוד>"
}

קוד הפרויקט:
${codeBlock}`;
}

async function llmDeepScan(fileContents, existingFindings) {
    const codeBlock = Object.entries(fileContents)
        .map(([name, src]) => `// ── ${name} ──\n${src}`)
        .join('\n\n');

    let raw = '';
    try {
        raw = await callGemma4(buildLLMPrompt(codeBlock, existingFindings), false, 1500);
    } catch (e) {
        console.warn('codeErrorScanner: LLM scan failed:', e.message);
        return [];
    }

    const m = raw.match(/\{[\s\S]*"findings"[\s\S]*\}/);
    if (!m) return [];

    let report;
    try { report = JSON.parse(m[0]); } catch { return []; }

    if (!Array.isArray(report.findings)) return [];

    return report.findings.map(f => ({
        severity: f.severity || 'low',
        category: f.category || 'bug',
        target: f.target || 'unknown',
        finding: f.finding || '',
        recommendation: f.recommendation || '',
        source: 'llm',
        _summary: report.summary || '',
    }));
}

// ── Score calculation ─────────────────────────────────────────────────────────
function computeScore(findings) {
    const w = { critical: 25, high: 10, medium: 4, low: 1 };
    const penalty = findings.reduce((s, f) => s + (w[f.severity] || 0), 0);
    return Math.max(0, 100 - penalty);
}

function countsBySeverity(findings) {
    const c = { critical: 0, high: 0, medium: 0, low: 0 };
    for (const f of findings) if (f.severity in c) c[f.severity]++;
    return c;
}

// ── Claude Code / Codex ready prompt ─────────────────────────────────────────
function buildClaudeReadyPrompt(findings, score) {
    const counts = countsBySeverity(findings);
    const order  = { critical: 0, high: 1, medium: 2, low: 3 };
    const sorted = [...findings].sort((a, b) => (order[a.severity] ?? 9) - (order[b.severity] ?? 9));

    const sevHeader = {
        critical: '## 🔴 קריטי',
        high:     '## 🟠 גבוה',
        medium:   '## 🟡 בינוני',
        low:      '## 🟢 נמוך',
    };

    const grouped = { critical: [], high: [], medium: [], low: [] };
    for (const f of sorted) {
        if (f.severity in grouped) grouped[f.severity].push(f);
    }

    let body = '';
    for (const sev of ['critical', 'high', 'medium', 'low']) {
        if (!grouped[sev].length) continue;
        body += `\n${sevHeader[sev]}\n\n`;
        grouped[sev].forEach((f, i) => {
            body += `### ${i + 1}. \`${f.target}\`\n`;
            body += `- **קטגוריה:** ${f.category}\n`;
            body += `- **בעיה:** ${f.finding}\n`;
            body += `- **תיקון:** ${f.recommendation}\n\n`;
        });
    }

    const checklist = sorted.slice(0, 30).map(f =>
        `- [ ] **[${(f.severity || '').toUpperCase()}]** \`${f.target}\` — ${f.recommendation || f.finding}`
    ).join('\n');

    const now = new Date().toISOString().slice(0, 10);

    return [
        '```markdown',
        `# בקשת תיקון שגיאות קוד — Jarvis Server`,
        `**נוצר:** ${now} | **ציון:** ${score}/100 | 🔴 ${counts.critical} · 🟠 ${counts.high} · 🟡 ${counts.medium} · 🟢 ${counts.low}`,
        '',
        '## הוראות לקלוד קוד / Codex:',
        'קרא כל ממצא, מצא את הקובץ הרלוונטי, בצע תיקון מינימלי, הרץ `npm test`, ותדווח מה שינית.',
        'תתקן לפי סדר עדיפות: קריטי ← גבוה ← בינוני ← נמוך.',
        '',
        body.trim(),
        '',
        '## רשימת תיקונים (Checklist):',
        checklist,
        '```',
    ].join('\n');
}

// ── Main entry point ──────────────────────────────────────────────────────────
async function runCodeErrorScanner({ learnedContext = {} } = {}) {
    const all     = listSources();
    const hot     = new Set(learnedContext.hotTargets || []);
    const ordered = [...all].sort((a, b) => (hot.has(b) ? 1 : 0) - (hot.has(a) ? 1 : 0));

    const fileContents = await readFiles(ordered, learnedContext.stableTargets);

    console.log(`🔍 codeErrorScanner: scanning ${Object.keys(fileContents).length} files (Phase 1 regex)...`);
    const patternFindings = patternScan(fileContents);
    console.log(`🔍 codeErrorScanner: ${patternFindings.length} pattern findings. Running LLM deep scan (Phase 2)...`);

    const llmFindings = await llmDeepScan(fileContents, patternFindings);

    // Deduplicate by target+finding (simple string match)
    const seen = new Set(patternFindings.map(f => `${f.target}|${f.finding}`));
    const newLlm = llmFindings.filter(f => !seen.has(`${f.target}|${f.finding}`));

    const allFindings = [...patternFindings, ...newLlm];
    const score = computeScore(allFindings);
    const summary = newLlm[0]?._summary || (allFindings.length
        ? `נמצאו ${allFindings.length} ממצאים (ציון: ${score}/100).`
        : 'לא נמצאו שגיאות קוד.');

    // Clean internal fields
    const findings = allFindings.map(({ source: _s, _summary: _sum, ...rest }) => rest);

    const claudePrompt = findings.length
        ? buildClaudeReadyPrompt(findings, score)
        : '✅ לא נמצאו שגיאות קוד.';

    console.log(`✅ codeErrorScanner: done. Score=${score}, total=${findings.length}`);
    return { findings, claudePrompt, summary, score };
}

module.exports = { runCodeErrorScanner };
