'use strict';
/**
 * review-security.js
 * Scans changed files for known security anti-patterns.
 * Exits with code 1 if critical or high findings exist.
 *
 * Usage: node scripts/review-security.js [--base <branch>]
 */

const fs   = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = process.cwd();
const BASE = process.argv[3] || 'origin/main';

// ── Rule definitions ──────────────────────────────────────────────────────────
// Each rule: { id, severity, description, pattern, fileFilter?, skipIfPattern? }

const RULES = [
    // Injection / RCE
    {
        id: 'RCE-001',
        severity: 'critical',
        description: 'require() עם משתנה — סכנת הרצת קוד שרירותי',
        pattern: /require\s*\(\s*(?!['"`])(?!path\.)/,
        fileFilter: /\.(js)$/,
        skipIfPattern: /\/\/ safe-require/,
    },
    {
        id: 'RCE-002',
        severity: 'critical',
        description: 'שימוש ב-eval() או new Function()',
        pattern: /\beval\s*\(|\bnew\s+Function\s*\(/,
        fileFilter: /\.(js)$/,
    },
    {
        id: 'RCE-003',
        severity: 'critical',
        description: 'LLM output נכתב ישירות לקובץ ללא סניטציה (agentFactory pattern)',
        pattern: /writeFile.*cleanCode|cleanCode.*writeFile/,
        fileFilter: /agentFactory/,
    },

    // Path traversal
    {
        id: 'PATH-001',
        severity: 'critical',
        description: 'path.join/resolve עם קלט משתמש ללא בדיקת גבול (startsWith SAFE_DIR)',
        pattern: /path\.(join|resolve)\s*\([^)]*(?:entry\.|req\.|body\.|query\.|params\.|filePath|agentPath)/,
        fileFilter: /\.(js)$/,
        skipIfPattern: /startsWith\(.*DIR/,
    },

    // Auth / Authz
    {
        id: 'AUTH-001',
        severity: 'high',
        description: 'endpoint POST/PUT/DELETE חדש ללא requirePolicy()',
        pattern: /app\.(post|put|delete)\s*\(['"`][^'"`]+['"`]\s*,\s*async/,
        fileFilter: /server\.js$/,
        skipIfPattern: /requirePolicy/,
        multilineContext: 3,
    },
    {
        id: 'AUTH-002',
        severity: 'high',
        description: 'OAuth callback ללא אימות state',
        pattern: /auth.*callback|callback.*oauth/i,
        fileFilter: /server\.js$/,
        skipIfPattern: /_oauthNonces|state.*nonce|nonce.*state/,
    },

    // Information disclosure
    {
        id: 'INFO-001',
        severity: 'medium',
        description: 'err.message נחשף לקליינט ב-res.json',
        pattern: /res\.(?:status\(\d+\)\.)?json\s*\([^)]*err\.message/,
        fileFilter: /\.(js)$/,
    },
    {
        id: 'INFO-002',
        severity: 'medium',
        description: 'stack trace או פרטי מערכת בתגובה',
        pattern: /res\.(?:status\(\d+\)\.)?(?:json|send)\s*\([^)]*(?:err\.stack|__dirname|process\.env)/,
        fileFilter: /\.(js)$/,
    },

    // CORS / CSRF
    {
        id: 'CORS-001',
        severity: 'critical',
        description: 'CORS wildcard origin: \'*\'',
        pattern: /cors\s*\(\s*\{[^}]*origin\s*:\s*['"`]\*['"`]/,
        fileFilter: /server\.js$/,
    },
    {
        id: 'WS-001',
        severity: 'high',
        description: 'WebSocketServer ללא verifyClient',
        pattern: /new\s+WebSocketServer\s*\(\s*\{/,
        fileFilter: /server\.js$/,
        skipIfPattern: /verifyClient/,  // checked against surrounding lines in full source
    },

    // Rate limiting
    {
        id: 'RATE-001',
        severity: 'medium',
        description: 'endpoint ציבורי חדש ללא rate limiter (_rl)',
        pattern: /app\.(get|post|put|delete)\s*\(['"`]\/[a-z]/,
        fileFilter: /server\.js$/,
        skipIfPattern: /_rl\(|rateLimit\(/,
        multilineContext: 2,
    },

    // Secrets
    {
        id: 'SEC-001',
        severity: 'critical',
        description: 'API key / סיסמה hard-coded בקוד',
        pattern: /(?:api[_-]?key|password|secret|token)\s*[:=]\s*['"`][a-zA-Z0-9_\-+/]{16,}['"`]/i,
        fileFilter: /\.(js)$/,
        skipIfPattern: /process\.env|example|test|mock|placeholder/i,
    },

    // Known bug patterns
    {
        id: 'BUG-001',
        severity: 'medium',
        description: 'lastIndexOf(\'{\') — גורם לפרסור JSON שגוי כשהתוכן מכיל סוגריים (באג ידוע)',
        pattern: /lastIndexOf\s*\(\s*['"`]\{['"`]\)/,
        fileFilter: /\.(js)$/,
        skipTestFiles: true,
    },
    {
        id: 'BUG-002',
        severity: 'low',
        description: 'await בתוך forEach — הפרומיסים לא מחכים',
        pattern: /\.forEach\s*\([^)]*async|\.forEach\s*\(\s*async/,
        fileFilter: /\.(js)$/,
    },
];

// ── Get diff lines ────────────────────────────────────────────────────────────

function getDiffLines(base) {
    try {
        const diff = execSync(`git diff ${base}...HEAD`, { encoding: 'utf8' });
        const results = []; // { file, lineNum, content }

        let currentFile = null;
        let newLineNum  = 0;

        for (const line of diff.split('\n')) {
            if (line.startsWith('+++ b/')) {
                currentFile = line.slice(6);
                newLineNum  = 0;
                continue;
            }
            if (line.startsWith('@@ ')) {
                const m = line.match(/@@ -\d+(?:,\d+)? \+(\d+)/);
                newLineNum = m ? parseInt(m[1], 10) - 1 : newLineNum;
                continue;
            }
            if (line.startsWith('-')) continue;
            if (line.startsWith('+')) {
                newLineNum++;
                results.push({ file: currentFile, lineNum: newLineNum, content: line.slice(1) });
            } else {
                newLineNum++;
            }
        }
        return results;
    } catch { return []; }
}

// ── Build per-file full source index for context lookups ─────────────────────

function buildFileIndex(diffLines) {
    // fileIndex[path] = array of all lines (added + context) in order
    const index = {};
    for (const { file, lineNum, content } of diffLines) {
        if (!file) continue;
        if (!index[file]) index[file] = [];
        index[file][lineNum] = content;
    }
    return index;
}

function contextAround(fileIndex, file, lineNum, radius = 8) {
    const lines = fileIndex[file] || [];
    const start = Math.max(0, lineNum - radius);
    const end   = Math.min(lines.length, lineNum + radius);
    return lines.slice(start, end).filter(Boolean).join('\n');
}

// ── Scan ──────────────────────────────────────────────────────────────────────

function scan(diffLines) {
    const findings  = [];
    const fileIndex = buildFileIndex(diffLines);

    // Also load full source for context checks (not just diff lines)
    const fullSources = {};
    const uniqueFiles = [...new Set(diffLines.map(l => l.file).filter(Boolean))];
    for (const f of uniqueFiles) {
        try { fullSources[f] = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch { /* skip */ }
    }

    for (const rule of RULES) {
        const matchedLines = diffLines.filter(({ file, content }) => {
            if (!file) return false;
            if (rule.fileFilter  && !rule.fileFilter.test(file))  return false;
            if (rule.skipTestFiles && /^tests\//.test(file))       return false;
            // Skip comment-only lines
            if (/^\s*\/\//.test(content)) return false;
            if (rule.skipIfPattern && rule.skipIfPattern.test(content)) return false;
            return rule.pattern.test(content);
        });

        for (const { file, lineNum, content } of matchedLines) {
            // For rules that need surrounding context, check the wider window
            if (rule.skipIfPattern) {
                const ctx = contextAround(fileIndex, file, lineNum);
                if (rule.skipIfPattern.test(ctx)) continue;
                // Also check full source around the line for multi-line constructs
                const fullSrc = fullSources[file] || '';
                const srcLines = fullSrc.split('\n');
                const nearby = srcLines.slice(Math.max(0, lineNum - 5), lineNum + 10).join('\n');
                if (rule.skipIfPattern.test(nearby)) continue;
            }

            findings.push({
                id:       rule.id,
                severity: rule.severity,
                file,
                lineNum,
                snippet:  content.trim().slice(0, 100),
                message:  rule.description,
            });
        }
    }

    return findings;
}

// ── Format & output ───────────────────────────────────────────────────────────

const ICONS = { critical: '🔴', high: '🟠', medium: '🟡', low: '🔵' };
const ORDER = ['critical', 'high', 'medium', 'low'];

function print(findings) {
    console.log('🔒 אבטחה ודפוסים בעייתיים\n');

    if (findings.length === 0) {
        console.log('  ✅ לא נמצאו ממצאים בקוד שנשתנה\n');
        return;
    }

    const sorted = findings.sort((a, b) => ORDER.indexOf(a.severity) - ORDER.indexOf(b.severity));
    for (const f of sorted) {
        console.log(`${ICONS[f.severity]} [${f.id}] ${f.file}:${f.lineNum}`);
        console.log(`   ${f.message}`);
        console.log(`   ↳ ${f.snippet}\n`);
    }
}

// ── Main ──────────────────────────────────────────────────────────────────────

const diffLines = getDiffLines(BASE);
const findings  = scan(diffLines);
print(findings);

const hasCriticalOrHigh = findings.some(f => f.severity === 'critical' || f.severity === 'high');
process.exit(hasCriticalOrHigh ? 1 : 0);
