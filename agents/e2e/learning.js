// Self-improvement loop for the E2E agent.
//
// loadContext()   — reads last N runs + active learned-probes from Supabase
// computeDeltas() — classifies each new finding as new / regression / flaky / known
// distill()       — updates reinforcement counters and asks an LLM for new probe ideas

const crypto = require('crypto');
const { callGemma4 } = require('../models');

const HISTORY_RUNS = 5;
const MAX_ACTIVE_PROBES = 50;
const PROMOTE_HITS = 3;
const PRUNE_MISSES = 5;

function fingerprint(target, finding) {
    const key = `${target}|${(finding || '').slice(0, 80)}`;
    return crypto.createHash('sha1').update(key).digest('hex');
}

async function loadContext(supabase) {
    const empty = {
        regressions: [], flakiness: [], stableTargets: [], hotTargets: [],
        sampleBank: [], lastRunFindings: [], movingAvgScore: null, learnedProbes: [],
        runHistory: [],
    };
    if (!supabase) return empty;

    try {
        const { data: runRows } = await supabase
            .from('e2e_reports')
            .select('run_id, created_at')
            .order('created_at', { ascending: false })
            .limit(500);

        const seen = new Set();
        const runIds = [];
        for (const r of runRows || []) {
            if (!seen.has(r.run_id)) { seen.add(r.run_id); runIds.push(r.run_id); }
            if (runIds.length >= HISTORY_RUNS) break;
        }
        if (runIds.length === 0) {
            const { data: probes } = await supabase
                .from('e2e_learned_probes')
                .select('*').eq('active', true).limit(30);
            return { ...empty, learnedProbes: probes || [] };
        }

        const { data: findings } = await supabase
            .from('e2e_reports')
            .select('*')
            .in('run_id', runIds);

        const byRun = new Map();
        for (const f of findings || []) {
            if (!byRun.has(f.run_id)) byRun.set(f.run_id, []);
            byRun.get(f.run_id).push(f);
        }

        const orderedRuns = runIds.map(id => byRun.get(id) || []);
        const lastRunFindings = orderedRuns[0] || [];

        // Build presence matrix per fingerprint across runs (newest -> oldest)
        const presence = new Map(); // fp -> array<bool> length runIds.length
        for (let i = 0; i < orderedRuns.length; i++) {
            const fps = new Set(orderedRuns[i].map(f => f.fingerprint || fingerprint(f.target, f.finding)));
            for (const fp of fps) {
                if (!presence.has(fp)) presence.set(fp, new Array(orderedRuns.length).fill(false));
                presence.get(fp)[i] = true;
            }
        }

        const regressions = [];
        const flakiness = [];
        for (const [fp, arr] of presence.entries()) {
            const count = arr.filter(Boolean).length;
            if (count >= 2) regressions.push(fp);
            // flaky = appears, disappears, then reappears
            let transitions = 0;
            for (let i = 1; i < arr.length; i++) if (arr[i] !== arr[i - 1]) transitions++;
            if (transitions >= 2 && count >= 2) flakiness.push(fp);
        }

        // Hot targets: anything with a finding in the last run
        const hotTargets = Array.from(new Set(lastRunFindings.map(f => f.target))).slice(0, 20);

        // Stable targets: appeared as target in older runs but not in last 3 runs
        const recentTargets = new Set(orderedRuns.slice(0, 3).flatMap(r => r.map(f => f.target)));
        const olderTargets = new Set(orderedRuns.slice(3).flatMap(r => r.map(f => f.target)));
        const stableTargets = [...olderTargets].filter(t => !recentTargets.has(t));

        // Sample bank: queries from API/UX findings whose finding text reveals a probe
        const sampleBank = [];
        for (const f of findings || []) {
            if (f.target && /POST \/ask-jarvis|chat/i.test(f.target) && f.finding) {
                const m = f.finding.match(/"([^"]{4,80})"/);
                if (m) sampleBank.push(m[1]);
            }
        }

        // Moving average score: count of low/med/high/critical → 100 - weighted
        const scores = orderedRuns.map(rs => {
            const w = { critical: 25, high: 10, medium: 4, low: 1 };
            const penalty = rs.reduce((s, f) => s + (w[f.severity] || 0), 0);
            return Math.max(0, 100 - penalty);
        });
        const movingAvgScore = scores.length
            ? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length)
            : null;

        const { data: probes } = await supabase
            .from('e2e_learned_probes')
            .select('*')
            .eq('active', true)
            .order('hits', { ascending: false })
            .limit(30);

        return {
            regressions,
            flakiness,
            stableTargets,
            hotTargets,
            sampleBank: Array.from(new Set(sampleBank)).slice(0, 10),
            lastRunFindings,
            movingAvgScore,
            learnedProbes: probes || [],
            runHistory: orderedRuns,
        };
    } catch (err) {
        console.warn('learning.loadContext failed:', err.message);
        return empty;
    }
}

function computeDeltas(currentFindings, learnedContext) {
    const lastRun = learnedContext.lastRunFindings || [];
    const lastFps = new Set(lastRun.map(f => f.fingerprint || fingerprint(f.target, f.finding)));
    const regressions = new Set(learnedContext.regressions || []);
    const flakiness = new Set(learnedContext.flakiness || []);

    let newCount = 0, regressionCount = 0, flakyCount = 0;
    for (const f of currentFindings) {
        const fp = f.fingerprint || fingerprint(f.target, f.finding);
        f.fingerprint = fp;
        if (flakiness.has(fp)) { f.status = 'flaky'; flakyCount++; }
        else if (regressions.has(fp) || lastFps.has(fp)) { f.status = 'regression'; regressionCount++; }
        else { f.status = 'new'; newCount++; }
    }

    const currentFps = new Set(currentFindings.map(f => f.fingerprint));
    const resolvedCount = lastRun.filter(f =>
        !currentFps.has(f.fingerprint || fingerprint(f.target, f.finding))
    ).length;

    return { newCount, regressionCount, resolvedCount, flakyCount };
}

async function distill(supabase, currentFindings, learnedContext, useLocal = false) {
    if (!supabase) return { added: 0, pruned: 0, promoted: [] };
    const summary = { added: 0, pruned: 0, promoted: [] };

    try {
        const probes = learnedContext.learnedProbes || [];
        const usedFps = new Set(currentFindings.map(f => f.fingerprint));
        const now = new Date().toISOString();

        // 1. Reinforcement: hits if a probe's target/query shows up in current findings, else miss
        for (const p of probes) {
            const hit = currentFindings.some(f =>
                (p.target && f.target && f.target.includes(p.target)) ||
                (p.query && f.finding && f.finding.includes(p.query))
            );
            const update = hit
                ? { hits: (p.hits || 0) + 1, last_used_at: now }
                : { misses: (p.misses || 0) + 1, last_used_at: now };
            await supabase.from('e2e_learned_probes').update(update).eq('id', p.id);

            if (hit && (p.hits || 0) + 1 >= PROMOTE_HITS) summary.promoted.push(p);
        }

        // 2. Auto-prune
        const { data: stale } = await supabase
            .from('e2e_learned_probes')
            .update({ active: false })
            .eq('active', true)
            .gte('misses', PRUNE_MISSES)
            .eq('hits', 0)
            .select('id');
        summary.pruned = stale?.length || 0;

        // 3. LLM proposes new probes
        const findingsDigest = currentFindings.slice(0, 20).map(f =>
            `- [${f.severity}/${f.category}] ${f.target}: ${f.finding.slice(0, 120)}`
        ).join('\n');
        const existingDigest = probes.slice(0, 10).map(p =>
            `- ${p.kind}: ${p.target || p.file_pattern || ''} | ${p.query || ''}`
        ).join('\n');

        const prompt = `You are improving an autonomous E2E test agent for a Hebrew personal-assistant server.
Given recent findings and existing probes, propose UP TO 5 NEW probes that would catch bugs missed today.

Existing probes (don't duplicate):
${existingDigest || '(none)'}

Recent findings:
${findingsDigest || '(none)'}

Return ONLY a JSON array. Each item: {"kind":"api|static|flutter|ux","target":"<endpoint or file>","query":"<Hebrew query, only for api/ux>","file_pattern":"<glob, only for static/flutter>","reason":"<why>"}.
No markdown. No prose.`;

        let raw = '';
        try { raw = await callGemma4(prompt, useLocal, 600); } catch (e) {
            console.warn('distill LLM failed:', e.message);
        }
        const open = raw.indexOf('['), close = raw.lastIndexOf(']');
        let proposals = [];
        if (open !== -1 && close !== -1) {
            try { proposals = JSON.parse(raw.substring(open, close + 1)); } catch { /* ignore */ }
        }

        const valid = (Array.isArray(proposals) ? proposals : [])
            .filter(p => p && ['api', 'static', 'flutter', 'ux'].includes(p.kind))
            .slice(0, 5);

        if (valid.length) {
            const rows = valid.map(p => ({
                kind: p.kind,
                target: p.target || null,
                query: p.query || null,
                file_pattern: p.file_pattern || null,
                reason: (p.reason || '').slice(0, 500),
                auto_generated: true,
                active: true,
            }));
            const { data: inserted } = await supabase.from('e2e_learned_probes').insert(rows).select('id');
            summary.added = inserted?.length || 0;
        }

        // 4. Cap active rows at MAX_ACTIVE_PROBES (deactivate oldest by last_used_at NULLS FIRST)
        const { data: active } = await supabase
            .from('e2e_learned_probes')
            .select('id')
            .eq('active', true)
            .order('last_used_at', { ascending: true, nullsFirst: true });
        const overflow = (active?.length || 0) - MAX_ACTIVE_PROBES;
        if (overflow > 0) {
            const ids = active.slice(0, overflow).map(r => r.id);
            await supabase.from('e2e_learned_probes').update({ active: false }).in('id', ids);
        }
    } catch (err) {
        console.warn('learning.distill failed:', err.message);
    }

    return summary;
}

module.exports = {
    loadContext,
    computeDeltas,
    distill,
    fingerprint,
    HISTORY_RUNS,
    MAX_ACTIVE_PROBES,
    PROMOTE_HITS,
    PRUNE_MISSES,
};
