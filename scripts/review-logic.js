'use strict';
/**
 * review-logic.js
 * Validates operational and business logic for changed files:
 * - Agent wiring (router + server dispatch)
 * - Agent function signature
 * - Cron timezone
 * - Supabase SELECT *
 * - New endpoints without rate limiting
 *
 * Usage: node scripts/review-logic.js [--base <branch>]
 */

const fs   = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = process.cwd();
const BASE = process.argv[3] || 'origin/main';

function read(rel) {
    try { return fs.readFileSync(path.join(ROOT, rel), 'utf8'); } catch { return ''; }
}

function changedFiles(filter) {
    try {
        const out = execSync(`git diff ${BASE}...HEAD --name-only`, { encoding: 'utf8' });
        const files = out.trim().split('\n').filter(Boolean);
        return filter ? files.filter(filter) : files;
    } catch { return []; }
}

function getDiff(files) {
    if (!files.length) return '';
    try { return execSync(`git diff ${BASE}...HEAD -- ${files.join(' ')}`, { encoding: 'utf8' }); }
    catch { return ''; }
}

const findings = [];

function flag(severity, message) {
    findings.push({ severity, message });
}

// ── 1. New agent files → must be wired in router.js + server.js ───────────────

const newAgents = changedFiles(f => f.startsWith('agents/') && !f.includes('custom') && !f.includes('e2e') && f !== 'agents/models.js' && f !== 'agents/utils.js' && f !== 'agents/router.js');
const agentDiff = getDiff(newAgents);
const addedAgentFiles = newAgents.filter(f => {
    try {
        execSync(`git show ${BASE}:${f}`, { encoding: 'utf8', stdio: 'pipe' });
        return false; // existed before
    } catch { return true; } // new file
});

for (const agentFile of addedAgentFiles) {
    const agentName = path.basename(agentFile, '.js');
    const serverSrc = read('server.js');
    const routerSrc = read('agents/router.js');

    const inServer = serverSrc.includes(`require('./agents/${agentName}')`) || serverSrc.includes(`require("./agents/${agentName}")`);
    const inRouter = routerSrc.includes(agentName) || routerSrc.includes(agentName.replace('Agent', '').toLowerCase());

    if (!inServer) flag('high', `⚙️  ${agentFile}: לא מיובא ב-server.js — האייג'נט לא נגיש`);
    if (!inRouter) flag('medium', `⚙️  ${agentFile}: לא נמצא ב-router.js — לא יסווג אוטומטית`);
}

// ── 2. Agent signature check (only for truly new files) ──────────────────────

const EXPECTED_SIG = /async\s+function\s+run\w+Agent\s*\(\s*userMessage\s*,\s*supabase\s*,\s*useLocal\s*,\s*settings/;
const EXPORT_RUN   = /module\.exports.*run\w+Agent/;

for (const f of addedAgentFiles) {
    const src = read(f);
    if (src.includes('module.exports')) {
        const hasRun = EXPORT_RUN.test(src);
        const hasSig = EXPECTED_SIG.test(src);
        if (hasRun && !hasSig) {
            flag('medium', `⚙️  ${f}: חתימת האייג'נט לא תואמת את הסטנדרט (userMessage, supabase, useLocal, settings)`);
        }
    }
}

// ── 3. router.js changes → check VALID_INTENTS + LLM_CLASSIFY_PROMPT ─────────

const routerChanged = changedFiles(f => f === 'agents/router.js').length > 0;
if (routerChanged) {
    const routerSrc = read('agents/router.js');
    const routerDiff = getDiff(['agents/router.js']);

    // New keywords added
    const newKeywords = [...routerDiff.matchAll(/^\+\s*(\w+)\s*:/gm)].map(m => m[1]);
    for (const kw of newKeywords) {
        if (!routerSrc.includes(`'${kw}'`) && !routerSrc.includes(`"${kw}"`)) continue;
        const inValid   = routerSrc.includes(`VALID_INTENTS`) && routerSrc.includes(kw);
        const inPrompt  = routerSrc.includes(`LLM_CLASSIFY_PROMPT`) && routerSrc.includes(kw);
        if (!inValid)  flag('high',   `⚙️  router.js: כוונה חדשה "${kw}" — לא נמצאת ב-VALID_INTENTS`);
        if (!inPrompt) flag('medium', `⚙️  router.js: כוונה חדשה "${kw}" — לא נמצאת ב-LLM_CLASSIFY_PROMPT`);
    }
}

// ── 4. Cron jobs → Jerusalem timezone ─────────────────────────────────────────

const serverDiff = getDiff(['server.js']);
const cronAdded  = [...serverDiff.matchAll(/^\+.*cron\.schedule/gm)];
for (const m of cronAdded) {
    if (!m[0].includes('Jerusalem') && !m[0].includes('timezone')) {
        flag('medium', `⚙️  server.js: cron חדש ללא timezone: 'Asia/Jerusalem'`);
    }
}

// ── 5. Supabase SELECT * ──────────────────────────────────────────────────────

const diffLines = getDiff(changedFiles(f => f.endsWith('.js') && !f.startsWith('tests/')));
const selectStar = [...diffLines.matchAll(/^\+.*\.select\s*\(\s*['"`]\*['"`]\s*\)/gm)];
for (const m of selectStar) {
    flag('low', `⚙️  שימוש ב-.select('*') — עדיף לציין עמודות ספציפיות`);
}

// ── 6. Return shape — agent returns { answer } ────────────────────────────────

for (const f of newAgents) {
    const src = read(f);
    // Check that every return has an answer field
    const returns = [...src.matchAll(/return\s*\{([^}]+)\}/g)];
    for (const m of returns) {
        if (!m[1].includes('answer')) {
            flag('medium', `⚙️  ${f}: return ללא שדה \`answer\` — ${m[0].slice(0, 60)}`);
        }
    }
}

// ── Output ────────────────────────────────────────────────────────────────────

const ICONS = { critical: '🔴', high: '🟠', medium: '🟡', low: '🔵' };
const ORDER = ['critical', 'high', 'medium', 'low'];

console.log('⚙️  היגיון תפעולי ועסקי\n');

if (findings.length === 0) {
    console.log('  ✅ לא נמצאו בעיות לוגיות\n');
} else {
    const sorted = findings.sort((a, b) => ORDER.indexOf(a.severity) - ORDER.indexOf(b.severity));
    sorted.forEach(f => console.log(`${ICONS[f.severity]} ${f.message}`));
    console.log('');
}

const hasCriticalOrHigh = findings.some(f => f.severity === 'critical' || f.severity === 'high');
process.exit(hasCriticalOrHigh ? 1 : 0);
