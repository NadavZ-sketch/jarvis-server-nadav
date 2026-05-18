'use strict';
/**
 * review-coverage.js
 * Reads Jest coverage summary and git diff to report coverage gaps
 * on changed files. Exits with code 1 if critical gaps found.
 *
 * Usage: node scripts/review-coverage.js [--base <branch>]
 */

const fs   = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT     = process.cwd();
const BASE     = process.argv[3] || 'origin/main';
const SUMMARY  = path.join(ROOT, 'coverage', 'coverage-summary.json');

// ── 1. Get changed non-test files ────────────────────────────────────────────

function getChangedFiles() {
    try {
        const out = execSync(`git diff ${BASE}...HEAD --name-only`, { encoding: 'utf8' });
        return out.trim().split('\n').filter(f =>
            f.endsWith('.js') &&
            !f.startsWith('tests/') &&
            !f.startsWith('scripts/') &&
            !f.includes('node_modules')
        );
    } catch {
        return [];
    }
}

// ── 2. Run Jest coverage if summary not fresh ─────────────────────────────────

function ensureCoverage() {
    const exists = fs.existsSync(SUMMARY);
    if (exists) {
        const age = Date.now() - fs.statSync(SUMMARY).mtimeMs;
        if (age < 5 * 60 * 1000) return; // fresh enough (< 5 min)
    }
    console.error('⏳ Running Jest coverage...');
    execSync('npx jest --coverage --coverageReporters=json-summary --silent 2>/dev/null', {
        cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'ignore', 'ignore'],
    });
}

// ── 3. Analyse coverage per file ──────────────────────────────────────────────

const THRESHOLDS = { statements: 60, branches: 50, functions: 60 };

function isExistingFile(relPath) {
    try {
        execSync(`git show ${BASE}:${relPath}`, { stdio: 'pipe', encoding: 'utf8' });
        return true;
    } catch { return false; }
}

function analyse(changedFiles, summary) {
    const findings = [];

    for (const relPath of changedFiles) {
        const absPath  = path.join(ROOT, relPath);
        const summaryKey = Object.keys(summary).find(k => k === absPath || k.endsWith('/' + relPath));

        if (!summaryKey) {
            // No coverage data → file not in collectCoverageFrom or never imported by tests
            const testFile = relPath.replace(/^agents\//, 'tests/unit/').replace(/^services\//, 'tests/unit/').replace(/^controllers\//, 'tests/unit/').replace('.js', '.test.js');
            const hasTest  = fs.existsSync(path.join(ROOT, testFile));
            findings.push({
                file: relPath,
                severity: hasTest ? 'medium' : 'high',
                message: hasTest
                    ? `כיסוי לא נמדד (קובץ לא ב-collectCoverageFrom?)`
                    : `❌ אין קובץ בדיקה (נבדק: ${testFile})`,
            });
            continue;
        }

        const s = summary[summaryKey];
        const low = [];
        if (s.statements.pct < THRESHOLDS.statements) low.push(`שורות ${s.statements.pct}%`);
        if (s.branches.pct   < THRESHOLDS.branches)   low.push(`ענפים ${s.branches.pct}%`);
        if (s.functions.pct  < THRESHOLDS.functions)   low.push(`פונקציות ${s.functions.pct}%`);

        if (low.length) {
            // Only 'high' for brand-new files — existing files with pre-existing low coverage are 'medium'
            const isNewFile = !isExistingFile(relPath);
            findings.push({
                file: relPath,
                severity: isNewFile && s.statements.pct < 30 ? 'high' : 'medium',
                message: `כיסוי נמוך: ${low.join(', ')}`,
                uncoveredLines: s.statements.skipped > 0 ? `(${s.statements.total - s.statements.covered} שורות לא מכוסות)` : '',
            });
        } else {
            findings.push({ file: relPath, severity: 'ok', message: `✅ ${s.statements.pct}% שורות / ${s.branches.pct}% ענפים` });
        }
    }

    return findings;
}

// ── 4. Check for new exported functions without tests ─────────────────────────

function checkNewExports(changedFiles) {
    const findings = [];
    try {
        const diff = execSync(`git diff ${BASE}...HEAD -- ${changedFiles.join(' ')}`, { encoding: 'utf8' });
        const addedExports = [...diff.matchAll(/^\+.*module\.exports.*=.*\{([^}]+)\}/gm)];
        addedExports.forEach(m => {
            const names = m[1].split(',').map(s => s.trim()).filter(Boolean);
            names.forEach(name => {
                if (name) findings.push({ severity: 'medium', message: `פונקציה חדשה ב-exports: \`${name}\` — בדוק שיש בדיקה` });
            });
        });
    } catch { /* diff failed */ }
    return findings;
}

// ── 5. Main ───────────────────────────────────────────────────────────────────

try {
    ensureCoverage();
} catch {
    console.error('⚠️  לא ניתן להריץ Jest — מדלג על כיסוי');
    process.exit(0);
}

const summary      = JSON.parse(fs.readFileSync(SUMMARY, 'utf8'));
const changedFiles = getChangedFiles();

if (changedFiles.length === 0) {
    console.log('📊 כיסוי בדיקות: לא נמצאו קבצי JS שונו\n');
    process.exit(0);
}

const findings    = analyse(changedFiles, summary);
const exportFinds = checkNewExports(changedFiles);
const allFindings = [...findings, ...exportFinds];

console.log('📊 כיסוי בדיקות\n');
allFindings.forEach(f => {
    const icon = f.severity === 'ok' ? '  ' : f.severity === 'high' ? '🟠' : '🟡';
    if (f.severity === 'ok') {
        console.log(`  ${f.file}: ${f.message}`);
    } else {
        console.log(`${icon} ${f.file || ''}: ${f.message} ${f.uncoveredLines || ''}`);
    }
});

const hasHigh = allFindings.some(f => f.severity === 'high');
console.log('');
process.exit(hasHigh ? 1 : 0);
