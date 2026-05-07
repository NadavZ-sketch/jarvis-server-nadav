// E2E testing agent — autonomous, learns from past runs.
// Triggered via chat ("בצע בדיקות קצה") or CLI (npm run e2e).

const crypto = require('crypto');
const { runApiProbe }      = require('./e2e/apiProbe');
const { runStaticScan }    = require('./e2e/staticScan');
const { runFlutterScan }   = require('./e2e/flutterScan');
const { runUxScan }        = require('./e2e/uxScan');
const { loadContext, computeDeltas, distill, fingerprint } = require('./e2e/learning');

const SEV_EMOJI = { critical: '🔴', high: '🟠', medium: '🟡', low: '🟢' };
const STATUS_TAG = { regression: '🔁 רגרסיה', flaky: '📉 פלייקי', new: '🆕 חדש', known: '' };

const ALL_PROBES = ['api', 'static', 'flutter', 'ux'];

function selectedProbes(settings) {
    const skip = new Set(settings.skipProbes || []);
    if (Array.isArray(settings.onlyProbes) && settings.onlyProbes.length) {
        return settings.onlyProbes.filter(p => ALL_PROBES.includes(p));
    }
    return ALL_PROBES.filter(p => !skip.has(p));
}

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

function formatAnswer({ runId, findings, score, deltas, learnedContext, distillSummary, summary }) {
    const counts = countsBySeverity(findings);
    const trend = (learnedContext.movingAvgScore != null)
        ? `(Δ ${score - learnedContext.movingAvgScore >= 0 ? '+' : ''}${score - learnedContext.movingAvgScore} מהממוצע)`
        : '';

    const groups = groupBy(findings, f => categoryOfTarget(f.target));
    const sectionOrder = ['API', 'Static', 'Flutter UI', 'Hebrew Quality', 'Other'];

    const sections = sectionOrder
        .filter(s => groups.has(s))
        .map(name => {
            const lines = groups.get(name).slice(0, 8).map(f => {
                const tag = STATUS_TAG[f.status] || '';
                const lat = f.latency_ms != null ? ` (${f.latency_ms} ms)` : '';
                return `${SEV_EMOJI[f.severity] || '⚪'} [${(f.severity || '').toUpperCase()}] ${f.target}${lat} ${tag}\n   ${f.finding}\n   ✅ ${f.recommendation || ''}`;
            }).join('\n\n');
            return `— ${name} —\n${lines}`;
        }).join('\n\n');

    const learning = [
        '🧠 לימוד עצמי:',
        `   • נוספו ${distillSummary.added} בדיקות חדשות ל-e2e_learned_probes.`,
        distillSummary.pruned ? `   • נגרעו ${distillSummary.pruned} בדיקות (5 פספוסים).` : null,
        ...(distillSummary.promoted || []).slice(0, 3).map(p =>
            `   💡 הצעה לקיבוע: "${p.query || p.target}" חשפה באג ${p.hits + 1} פעמים — שווה להוסיף לקבועים.`
        ),
    ].filter(Boolean).join('\n');

    return [
        `🧪 דוח בדיקות E2E (run_id: ${runId}) — ציון כללי: ${score}/100  ${trend}`.trim(),
        `${SEV_EMOJI.critical} קריטי: ${counts.critical}   ${SEV_EMOJI.high} גבוה: ${counts.high}   ${SEV_EMOJI.medium} בינוני: ${counts.medium}   ${SEV_EMOJI.low} נמוך: ${counts.low}`,
        `🆕 חדש: ${deltas.newCount}   🔁 רגרסיה: ${deltas.regressionCount}   ✅ נפתר: ${deltas.resolvedCount}   📉 פלייקי: ${deltas.flakyCount}`,
        '',
        sections || 'לא נמצאו ממצאים.',
        '',
        learning,
        '',
        summary ? `📋 סיכום: ${summary}` : '',
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

    const tasks = [];
    if (probes.includes('static'))  tasks.push(runStaticScan({ learnedContext }).catch(e => ({ findings: [], _err: e.message })));
    if (probes.includes('flutter')) tasks.push(runFlutterScan({ learnedContext }).catch(e => ({ findings: [], _err: e.message })));
    if (probes.includes('ux'))      tasks.push(runUxScan({ samples: apiResult.samples, learnedContext }).catch(e => ({ findings: [], _err: e.message })));

    const [staticRes, flutterRes, uxRes] = await Promise.all([
        probes.includes('static')  ? tasks.shift() : Promise.resolve({ findings: [] }),
        probes.includes('flutter') ? tasks.shift() : Promise.resolve({ findings: [] }),
        probes.includes('ux')      ? tasks.shift() : Promise.resolve({ findings: [] }),
    ]);

    const allFindings = [
        ...(apiResult.findings || []),
        ...(staticRes.findings || []),
        ...(flutterRes.findings || []),
        ...(uxRes.findings || []),
    ];

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

    const answer = formatAnswer({
        runId,
        findings: allFindings,
        score,
        deltas,
        learnedContext,
        distillSummary,
        summary: staticRes.summary || '',
    });

    return {
        answer,
        action: { type: 'e2e_report', runId, score, counts: countsBySeverity(allFindings), deltas },
    };
}

module.exports = { runE2EAgent };

