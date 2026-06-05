// E2E testing agent — autonomous, learns from past runs.
// Triggered via chat ("בצע בדיקות קצה") or CLI (npm run e2e).

const crypto = require('crypto');
const { runManusTask, isManusConfigured } = require('./manusAgent');
const { runApiProbe }          = require('./e2e/apiProbe');
const { runStaticScan }        = require('./e2e/staticScan');
const { runFlutterScan }       = require('./e2e/flutterScan');
const { runUxScan }            = require('./e2e/uxScan');
const { runCodeErrorScanner }  = require('./e2e/codeErrorScanner');
const { loadContext, computeDeltas, distill, fingerprint } = require('./e2e/learning');

const SEV_EMOJI = { critical: '🔴', high: '🟠', medium: '🟡', low: '🟢' };
const STATUS_TAG = { regression: '🔁 רגרסיה', flaky: '📉 פלייקי', new: '🆕 חדש', known: '' };

const ALL_PROBES = ['api', 'static', 'flutter', 'ux', 'errors'];

function selectedProbes(settings) {
    const skip = new Set(settings.skipProbes || []);
    if (Array.isArray(settings.onlyProbes) && settings.onlyProbes.length) {
        return settings.onlyProbes.filter(p => ALL_PROBES.includes(p));
    }
    return ALL_PROBES.filter(p => !skip.has(p));
}

// Tag each finding with how it was produced so the report can separate
// hard measurements (HTTP/latency/regex) from LLM evaluations (which can err).
// `defaultSource` of null means: keep the finding's own `source` (e.g. the code
// error scanner already tags 'pattern' | 'llm'); we normalize those below.
function tagSource(findings, defaultSource) {
    return (findings || []).map(f => ({ ...f, source: normalizeSource(f.source || defaultSource) }));
}

// 'measured' = deterministic/verifiable; 'evaluated' = LLM judgment, needs validation.
function normalizeSource(source) {
    if (source === 'pattern' || source === 'measured') return 'measured';
    if (source === 'llm' || source === 'evaluated') return 'evaluated';
    return 'measured';
}

function isMeasured(f) { return normalizeSource(f.source) === 'measured'; }

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

function groupBy(findings, keyFn) {
    const m = new Map();
    for (const f of findings) {
        const k = keyFn(f);
        if (!m.has(k)) m.set(k, []);
        m.get(k).push(f);
    }
    return m;
}

function categoryOfTarget(target) {
    if (!target) return 'Other';
    if (/POST \/|GET \//.test(target)) return 'API';
    if (/\.dart/.test(target)) return 'Flutter UI';
    if (/quality/i.test(target)) return 'Hebrew Quality';
    if (/\.js$/.test(target) || /^server\.js/.test(target)) return 'Static';
    return 'Other';
}

function buildClaudePrompt({ runId, findings, score, counts }) {
    const order = { critical: 0, high: 1, medium: 2, low: 3 };
    const sorted = [...findings].sort((a, b) => (order[a.severity] ?? 9) - (order[b.severity] ?? 9));
    const sevHeader = { critical: '## 🔴 Critical (fix first)', high: '## 🟠 High Priority', medium: '## 🟡 Medium', low: '## 🟢 Low' };

    const grouped = { critical: [], high: [], medium: [], low: [] };
    for (const f of sorted) {
        const sev = grouped[f.severity] ? f.severity : 'low';
        grouped[sev].push(f);
    }

    let body = '';
    for (const sev of ['critical', 'high', 'medium', 'low']) {
        if (!grouped[sev].length) continue;
        body += `\n${sevHeader[sev]}\n\n`;
        grouped[sev].forEach((f, i) => {
            const tag = f.status && f.status !== 'new' ? ` _(${f.status})_` : '';
            const srcTag = isMeasured(f) ? ' `[MEASURED]`' : ' `[AI-EVALUATED — verify first]`';
            const lat = f.latency_ms != null ? ` — ${f.latency_ms}ms` : '';
            const readHint = /^(GET|POST|PUT|DELETE|PATCH)\s/.test(f.target)
                ? '_(validate in `server.js`)_'
                : `_(Read \`${f.target}\` to validate)_`;
            body += `### ${i + 1}. \`${f.target}\`${lat}${srcTag}${tag}\n`;
            body += `- **Validate:** ${readHint}\n`;
            body += `- **Category:** ${f.category}\n`;
            body += `- **Issue:** ${f.finding}\n`;
            body += `- **Fix:** ${f.recommendation || '(no recommendation)'}\n\n`;
        });
    }

    const checklist = sorted.slice(0, 25).map(f =>
        `- [ ] **[${(f.severity || '').toUpperCase()}]** ${f.target} — ${f.recommendation || f.finding}`
    ).join('\n');

    return [
        '```markdown',
        `# E2E Test Report — \`${runId}\``,
        `**Score:** ${score}/100 | 🔴 ${counts.critical} · 🟠 ${counts.high} · 🟡 ${counts.medium} · 🟢 ${counts.low}`,
        '',
        '## Instructions for Claude',
        '**Step 1 — Validate each finding against the actual code:**',
        'For EVERY finding below, use your Read tool to open the referenced file before touching anything.',
        'For code files (.js, .dart): search for the exact pattern described in the issue — if it no longer exists, mark the finding as "already fixed" and skip it.',
        'For API endpoints (GET /…, POST /…): open server.js and confirm the route and its handler actually have the described problem.',
        'Write one line per finding: ✅ confirmed / ⏭️ skipped (reason).',
        '',
        '**Step 2 — Fix in priority order (Critical → High → Medium → Low):**',
        'For each confirmed finding: make the minimal change needed, run the test suite (`npm test`), and verify the fix works.',
        '',
        '**Step 3 — Write a plain-language summary (REQUIRED):**',
        'After completing all fixes, write a detailed explanation in simple Hebrew — suitable for someone with no coding knowledge — that covers:',
        '- What problems were found and what they were causing in the app',
        '- What changes you made to fix each problem',
        '- What works now that was broken before',
        '- Any issues that remain unfixed and why',
        'Use plain language, no technical jargon. This summary will be shared with the product team.',
        body.trim(),
        '## Action Checklist',
        checklist,
        '```',
    ].join('\n');
}

function buildSimpleUserReport({ score, findings, inconclusive = false }) {
    // No real data → never invent a score. Be honest about it.
    if (inconclusive) {
        const staticFindings = findings.filter(f => !isMeasured(f));
        const staticNote = staticFindings.length > 0
            ? `\n\nנמצאו ${staticFindings.length} ממצאים בסריקת קוד סטטית — אך הם אינם מחושבים לציון כל עוד השרת לא נבדק.`
            : '';
        return [
            '🔴 בדיקת מערכת — השרת לא מגיב.',
            '',
            '⚠️ כל בקשות ה-API נכשלו בשגיאת רשת (תוך 1–4ms) — השרת כנראה לא רץ.',
            'ודא שהשרת רץ ושכתובת הבדיקה נכונה (`http://localhost:3000`), ואז הרץ שוב.' + staticNote,
        ].join('\n');
    }

    // Measured findings are verifiable facts; evaluated findings are AI judgment
    // that needs validation. We base the headline conclusion only on measured data.
    const measured = findings.filter(isMeasured);
    const evaluated = findings.filter(f => !isMeasured(f));

    const criticals = measured.filter(f => f.severity === 'critical');
    const highs = measured.filter(f => f.severity === 'high');
    const mediums = measured.filter(f => f.severity === 'medium');

    let status = '✅ מעולה! כל מה שנבדק במדידה עובד כמו שצריך.';
    let action = '';

    if (criticals.length > 0) {
        status = `🚨 נמדדו ${criticals.length} בעיות קריטיות שצריך לתקן מייד!`;
        action = criticals.slice(0, 3).map(f =>
            `• ${f.finding} → ${f.recommendation || 'צריך לתקן'}`
        ).join('\n');
    } else if (highs.length > 0) {
        status = `⚠️ נמדדו ${highs.length} בעיות חשובות שצריך לתקן.`;
        action = highs.slice(0, 3).map(f =>
            `• ${f.finding} → ${f.recommendation || 'צריך לשפר'}`
        ).join('\n');
    } else if (mediums.length > 0) {
        status = `🔧 נמדדו ${mediums.length} שיפורים שאפשר לעשות.`;
        action = mediums.slice(0, 2).map(f =>
            `• ${f.finding}`
        ).join('\n');
    }

    const scoreColor = score >= 85 ? '💚' : score >= 70 ? '💛' : '❤️';
    const evalNote = evaluated.length
        ? `🤖 בנוסף, ה-AI סימן ${evaluated.length} הערכות שדורשות אימות לפני פעולה (לא נמדדו ודאית).`
        : '';

    return [
        `🧪 בדיקת מערכת — ציון: ${score}/100 ${scoreColor}`,
        '',
        status,
        '',
        ...(action ? [action, ''] : []),
        ...(evalNote ? [evalNote, ''] : []),
        `תגובה מפורטת לדחיסה בקלוד זמינה — בקש אם צריך עזרה בתיקון.`,
    ].filter(Boolean).join('\n');
}

function renderSections(findings) {
    const groups = groupBy(findings, f => categoryOfTarget(f.target));
    const sectionOrder = ['API', 'Static', 'Flutter UI', 'Hebrew Quality', 'Other'];
    return sectionOrder
        .filter(s => groups.has(s))
        .map(name => {
            const lines = groups.get(name).slice(0, 8).map(f => {
                const tag = STATUS_TAG[f.status] || '';
                const lat = f.latency_ms != null ? ` (${f.latency_ms} ms)` : '';
                return `${SEV_EMOJI[f.severity] || '⚪'} [${(f.severity || '').toUpperCase()}] ${f.target}${lat} ${tag}\n   ${f.finding}\n   ✅ ${f.recommendation || ''}`;
            }).join('\n\n');
            return `— ${name} —\n${lines}`;
        }).join('\n\n');
}

function formatAnswer({ runId, findings, score, deltas, learnedContext, distillSummary, summary, inconclusive = false }) {
    const counts = countsBySeverity(findings);

    const measured = findings.filter(isMeasured);
    const evaluated = findings.filter(f => !isMeasured(f));
    const measuredSections = renderSections(measured);
    const evaluatedSections = renderSections(evaluated);

    const findingsBlock = inconclusive
        ? 'לא נאספו נתונים מדודים בריצה זו (השרת לא היה נגיש).'
        : [
            '✅ נמדד ודאית (מדידות אמיתיות — HTTP/latency/דפוסי קוד):',
            measuredSections || '   אין ממצאים מדודים — מה שנבדק במדידה תקין.',
            '',
            '🤖 הערכת AI — מומלץ לאמת לפני פעולה (ניתוח מודל, עלול לכלול false-positive):',
            evaluatedSections || '   אין הערכות AI בריצה זו.',
        ].join('\n');

    const learning = [
        '🧠 לימוד עצמי:',
        `   • נוספו ${distillSummary.added} בדיקות חדשות ל-e2e_learned_probes.`,
        distillSummary.pruned ? `   • נגרעו ${distillSummary.pruned} בדיקות (5 פספוסים).` : null,
        ...(distillSummary.promoted || []).slice(0, 3).map(p =>
            `   💡 הצעה לקיבוע: "${p.query || p.target}" חשפה באג ${p.hits + 1} פעמים — שווה להוסיף לקבועים.`
        ),
    ].filter(Boolean).join('\n');

    const claudePrompt = findings.length
        ? [
            '',
            '═══════════════════════════════════════════',
            '📋 לתיקון בקלוד — העתק את הבלוק הבא ושלח לקלוד קוד:',
            '═══════════════════════════════════════════',
            '',
            buildClaudePrompt({ runId, findings, score, counts }),
        ].join('\n')
        : '';

    // For users, show simple report. For developers, show detailed.
    const simpleUserReport = buildSimpleUserReport({ score, findings, inconclusive });

    const scoreLine = inconclusive
        ? `דוח בדיקות E2E (run_id: ${runId}) — ⚠️ ללא נתונים מספיקים, אין ציון.`
        : `דוח בדיקות E2E (run_id: ${runId}) — ציון כללי: ${score}/100 (מבוסס מדידות; ${measured.length} מדודים, ${evaluated.length} הערכות AI)`;

    return [
        simpleUserReport,
        '',
        '═══════════════════════════════════════════',
        '🔬 דוח מפורט (טכני):',
        '═══════════════════════════════════════════',
        scoreLine,
        `${SEV_EMOJI.critical} קריטי: ${counts.critical}   ${SEV_EMOJI.high} גבוה: ${counts.high}   ${SEV_EMOJI.medium} בינוני: ${counts.medium}   ${SEV_EMOJI.low} נמוך: ${counts.low}`,
        `🆕 חדש: ${deltas.newCount}   🔁 רגרסיה: ${deltas.regressionCount}   ✅ נפתר: ${deltas.resolvedCount}   📉 פלייקי: ${deltas.flakyCount}`,
        '',
        findingsBlock,
        '',
        learning,
        '',
        summary ? `📋 סיכום: ${summary}` : '',
        claudePrompt,
    ].filter(Boolean).join('\n');
}

async function persistFindings(supabase, runId, findings) {
    if (!supabase || !findings.length) return;
    const rows = findings.map(f => ({
        run_id: runId,
        category: f.category || 'bug',
        severity: f.severity || 'low',
        target: (f.target || 'unknown').slice(0, 500),
        finding: (f.finding || '').slice(0, 2000),
        recommendation: (f.recommendation || '').slice(0, 1000),
        latency_ms: f.latency_ms ?? null,
        score: f.score ?? null,
        fingerprint: f.fingerprint || fingerprint(f.target, f.finding),
        status: f.status || 'new',
        source: normalizeSource(f.source),
    }));
    try {
        // Insert in chunks of 50 to stay under request limits
        for (let i = 0; i < rows.length; i += 50) {
            await supabase.from('e2e_reports').insert(rows.slice(i, i + 50));
        }
    } catch (err) {
        console.warn('e2eAgent: persistFindings failed:', err.message);
    }
}

async function runE2EAgent(userMessage = '', supabase = null, useLocal = false, settings = {}) {
    try {
        return await _runE2EAgent(userMessage, supabase, useLocal, settings);
    } catch (err) {
        console.error('E2EAgent error:', err.message);
        return { answer: 'לא הצלחתי לבצע את בדיקות הקצה. ייתכן שהמיגרציות ב-Supabase לא הורצו עדיין. נסה שוב או הרץ: `npm run e2e`.' };
    }
}

async function _runE2EAgent(userMessage = '', supabase = null, useLocal = false, settings = {}) {
    const t0 = Date.now();
    const probes = selectedProbes(settings);
    const baseUrl = settings.baseUrl || process.env.E2E_BASE_URL || 'http://localhost:3000';

    const learnedContext = settings.disableLearning ? {
        regressions: [], flakiness: [], stableTargets: [], hotTargets: [],
        sampleBank: [], lastRunFindings: [], movingAvgScore: null, learnedProbes: [],
    } : await loadContext(supabase);

    console.log(`🧪 E2E: probes=${probes.join(',')} | learned=${learnedContext.learnedProbes?.length || 0} | hot=${(learnedContext.hotTargets || []).length}`);

    let apiResult = { findings: [], samples: [] };
    if (probes.includes('api')) {
        apiResult = await runApiProbe({ baseUrl, learnedContext });
    }

    const [staticRes, flutterRes, uxRes, errorsRes] = await Promise.all([
        probes.includes('static')  ? runStaticScan({ learnedContext }).catch(e => ({ findings: [], _err: e.message })) : Promise.resolve({ findings: [] }),
        probes.includes('flutter') ? runFlutterScan({ learnedContext }).catch(e => ({ findings: [], _err: e.message })) : Promise.resolve({ findings: [] }),
        probes.includes('ux')      ? runUxScan({ samples: apiResult.samples, learnedContext }).catch(e => ({ findings: [], _err: e.message })) : Promise.resolve({ findings: [] }),
        probes.includes('errors')  ? runCodeErrorScanner({ learnedContext }).catch(e => ({ findings: [], _err: e.message })) : Promise.resolve({ findings: [] }),
    ]);

    const allFindings = [
        ...tagSource(apiResult.findings, 'measured'),
        ...tagSource(staticRes.findings, 'evaluated'),
        ...tagSource(flutterRes.findings, 'evaluated'),
        ...tagSource(uxRes.findings, 'evaluated'),
        // codeErrorScanner keeps its own per-finding `source` ('pattern' | 'llm')
        ...tagSource(errorsRes.findings, null),
    ];

    // A run is "inconclusive" when the server wasn't reachable.
    // Static code findings (medium/low) don't change this — a score of 0/100
    // caused by network errors is misleading, not meaningful.
    const ranApi = probes.includes('api');
    const apiReachable = !ranApi || apiResult.reachable !== false;
    const inconclusive = ranApi && !apiReachable;

    const deltas = computeDeltas(allFindings, learnedContext);
    const score = computeScore(allFindings);
    const runId = crypto.randomUUID();

    if (!settings.dryRun) {
        await persistFindings(supabase, runId, allFindings);
    }

    const distillSummary = settings.disableLearning
        ? { added: 0, pruned: 0, promoted: [] }
        : await distill(supabase, allFindings, learnedContext, false);

    const elapsed = Date.now() - t0;
    console.log(`🧪 E2E done in ${elapsed}ms — ${allFindings.length} findings, score ${score}`);

    // Optionally offload the narrative analysis to Manus (local probes still run here)
    const useManusOffload = process.env.MANUS_OFFLOAD_E2E === 'true' && isManusConfigured() && allFindings.length > 0;
    let answer;
    if (useManusOffload) {
        console.log('🧪 E2EAgent: offloading narrative analysis to Manus');
        const claudePrompt = buildClaudePrompt({ runId, findings: allFindings, score, counts: countsBySeverity(allFindings) });
        const { answer: manusAnswer } = await runManusTask(claudePrompt).catch(() => ({ answer: null }));
        answer = manusAnswer || formatAnswer({ runId, findings: allFindings, score, deltas, learnedContext, distillSummary, summary: staticRes.summary || '', inconclusive });
    } else {
        answer = formatAnswer({
            runId,
            findings: allFindings,
            score,
            deltas,
            learnedContext,
            distillSummary,
            summary: staticRes.summary || '',
            inconclusive,
        });
    }

    return {
        answer,
        action: { type: 'e2e_report', runId, score: inconclusive ? null : score, inconclusive, counts: countsBySeverity(allFindings), deltas },
    };
}

module.exports = { runE2EAgent, buildClaudePrompt, countsBySeverity, computeScore };

