require('dotenv').config();
const fs   = require('fs');
const path = require('path');
const { callGemma4 } = require('./models');

const BASE_DIR = path.join(__dirname, '..');

// Files to scan — only JS source, never .env or secrets
const SCAN_FILES = [
    'server.js',
    'agents/router.js',
    'agents/models.js',
    'agents/chatAgent.js',
    'agents/taskAgent.js',
    'agents/reminderAgent.js',
    'agents/memoryAgent.js',
    'agents/sportsAgent.js',
    'agents/messagingAgent.js',
    'agents/draftAgent.js',
    'agents/securityAgent.js',
    'agents/agentFactoryAgent.js',
];

const MAX_CHARS_PER_FILE = 4000; // avoid token overflow on smaller models

function readProjectFiles() {
    const result = {};
    for (const file of SCAN_FILES) {
        try {
            const content = fs.readFileSync(path.join(BASE_DIR, file), 'utf8');
            result[file] = content.length > MAX_CHARS_PER_FILE
                ? content.slice(0, MAX_CHARS_PER_FILE) + '\n// ... (truncated)'
                : content;
        } catch { /* skip missing files */ }
    }
    return result;
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

        const files = readProjectFiles();
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
