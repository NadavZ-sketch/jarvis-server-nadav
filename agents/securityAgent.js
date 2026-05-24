require('dotenv').config();
const fs   = require('fs');
const path = require('path');
const { callGemma4 } = require('./models');

const BASE_DIR = path.join(__dirname, '..');

const MAX_CHARS_PER_FILE = 3000; // per-file cap to avoid token overflow
const MAX_TOTAL_CHARS    = 60000; // total context budget across all files

// Directories to scan, in priority order (high-value code first).
const SCAN_DIRS = [
    { dir: '',           pattern: /^server\.js$/ },
    { dir: 'agents',     pattern: /^(?!.*\.test\.js$)[^/]+\.js$/ },
    { dir: 'services',   pattern: /^(?!.*\.test\.js$)[^/]+\.js$/ },
    { dir: 'routes',     pattern: /^(?!.*\.test\.js$)[^/]+\.js$/ },
    { dir: 'controllers',pattern: /^(?!.*\.test\.js$)[^/]+\.js$/ },
];

// Files that must never be read (secrets, generated output, huge bundles).
const EXCLUDE_NAMES = new Set(['.env', '.env.local', '.env.production', 'package-lock.json']);
const EXCLUDE_DIRS  = new Set(['node_modules', 'tests', '.git', 'coverage']);

async function _listJs(relDir, pattern) {
    const abs = path.join(BASE_DIR, relDir);
    try {
        const entries = await fs.promises.readdir(abs, { withFileTypes: true });
        return entries
            .filter(e => e.isFile() && pattern.test(e.name) && !EXCLUDE_NAMES.has(e.name))
            .map(e => relDir ? path.join(relDir, e.name) : e.name);
    } catch { return []; }
}

async function readProjectFiles() {
    // Collect candidates in priority order
    const candidates = [];
    for (const { dir, pattern } of SCAN_DIRS) {
        // Skip excluded directories
        if (dir && EXCLUDE_DIRS.has(dir)) continue;
        const files = await _listJs(dir, pattern);
        candidates.push(...files);
    }

    // Read files, honour per-file and total-budget caps
    const result = {};
    let totalChars = 0;
    await Promise.all(candidates.map(async (relPath) => {
        try {
            const raw = await fs.promises.readFile(path.join(BASE_DIR, relPath), 'utf8');
            const content = raw.length > MAX_CHARS_PER_FILE
                ? raw.slice(0, MAX_CHARS_PER_FILE) + '\n// ... (truncated)'
                : raw;
            result[relPath] = { content, size: content.length };
        } catch (err) {
            console.warn(`⚠️ SecurityAgent: could not read ${relPath}: ${err.message}`);
        }
    }));

    // Apply total budget in priority order (candidates already ordered)
    const final = {};
    for (const relPath of candidates) {
        if (!result[relPath]) continue;
        if (totalChars + result[relPath].size > MAX_TOTAL_CHARS) break;
        final[relPath] = result[relPath].content;
        totalChars += result[relPath].size;
    }
    return final;
}

function buildScanPrompt(codeBlock) {
    return `אתה מומחה אבטחת מידע ופיתוח Node.js. סרוק את הקוד הבא ומצא ממצאים בארבע קטגוריות:

1. 🔴 critical — חשיפת מפתחות, הזרקת קוד, חוסר אימות
2. 🟠 high — קריסת שרת, אובדן נתונים, טיפול שגוי בשגיאות
3. 🟡 medium — race conditions, logic bugs, חוסר validation
4. 🟢 low — שיפורים מומלצים, code quality

החזר JSON תקין בלבד (ללא markdown):
{
  "findings": [
    {
      "severity": "critical|high|medium|low",
      "category": "security|bug|performance|reliability",
      "file": "שם הקובץ",
      "issue": "תיאור קצר של הבעיה",
      "fix": "המלצה לתיקון"
    }
  ],
  "summary": "סיכום 1-2 משפטים",
  "score": 0
}

הערה: score הוא ציון איכות הקוד מ-0 עד 100.

קוד הפרויקט:
${codeBlock}`;
}

async function runSecurityAgent(userMessage, useLocal, sendEmailFn) {
    try {
        const sendReport = /שלח|מייל|email|דוח ב|report/i.test(userMessage);

        const files = await readProjectFiles();
        const codeBlock = Object.entries(files)
            .map(([name, src]) => `// ── ${name} ──\n${src}`)
            .join('\n\n');

        console.log(`🔐 SecurityAgent: scanning ${Object.keys(files).length} files...`);

        // Always use cloud for security analysis (local models may miss issues)
        const raw = await callGemma4(buildScanPrompt(codeBlock), false);

        // Extract JSON from response
        let report = null;
        const match = raw.match(/\{[\s\S]*"findings"[\s\S]*\}/);
        if (match) {
            try { report = JSON.parse(match[0]); } catch { /* fallback to raw */ }
        }

        if (!report || !Array.isArray(report.findings)) {
            return { answer: `🔍 תוצאות הסריקה:\n\n${raw}` };
        }

        const SEV = { critical: '🔴', high: '🟠', medium: '🟡', low: '🟢' };
        const findings = report.findings;

        const counts = { critical: 0, high: 0, medium: 0, low: 0 };
        findings.forEach(f => { if (f.severity in counts) counts[f.severity]++; });

        const lines = findings.length > 0
            ? findings.map(f =>
                `${SEV[f.severity] || '⚪'} [${(f.severity || '').toUpperCase()}] ${f.file}\n   ${f.issue}\n   ✅ ${f.fix}`
              ).join('\n\n')
            : 'לא נמצאו ממצאים.';

        const answer = [
            `🔐 דוח אבטחה וסריקת באגים (ציון: ${report.score ?? '?'}/100)`,
            `🔴 קריטי: ${counts.critical}  🟠 גבוה: ${counts.high}  🟡 בינוני: ${counts.medium}  🟢 נמוך: ${counts.low}`,
            '',
            lines,
            '',
            `📋 סיכום: ${report.summary || ''}`,
        ].join('\n');

        if (sendReport && sendEmailFn) {
            const emailBody = [
                `דוח אבטחה — Jarvis (ציון: ${report.score ?? '?'}/100)`,
                `סיכום: ${report.summary}`,
                '',
                findings.map(f =>
                    `[${(f.severity || '').toUpperCase()}] ${f.file}\nבעיה: ${f.issue}\nתיקון: ${f.fix}`
                ).join('\n\n---\n\n'),
            ].join('\n');

            await sendEmailFn(process.env.GMAIL_USER, emailBody);
            return { answer: answer + '\n\n📧 הדוח נשלח למייל.' };
        }

        return { answer };

    } catch (err) {
        console.error('SecurityAgent Error:', err.message);
        return { answer: 'לא הצלחתי לבצע את הסריקה. נסה שוב.' };
    }
}

module.exports = { runSecurityAgent };
