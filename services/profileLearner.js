/**
 * User-profile learning loop.
 *
 * Turns observed behaviour into the user_profiles row so personalization
 * improves automatically — the profile is already injected into the chat and
 * insight prompts, so no further wiring is needed once it's populated.
 *
 * Deterministic and LLM-free (cheap, runs in a daily cron). Derived values are
 * written into the visible columns ONLY for fields the user hasn't set
 * manually; explicit edits (tracked in auto_learned.user_overridden by the
 * POST /user-profile handler) are never overwritten.
 */

const { analyzePatterns } = require('../agents/insightAgent');

const BUCKET_HOURS = {
    morning: '08:00-12:00',
    afternoon: '12:00-17:00',
    evening: '17:00-22:00',
    night: '22:00-06:00',
};

const LEARNABLE_FIELDS = ['preferred_hours', 'interests', 'recurring_tasks'];

function deriveProfile(analysis, tasks = []) {
    const learned = {};

    // preferred_hours — from the busiest time-of-day bucket(s).
    const bucketsSorted = Object.entries(analysis.buckets || {}).sort((a, b) => b[1] - a[1]);
    const hours = [];
    if (bucketsSorted[0] && bucketsSorted[0][1] > 0) {
        hours.push(BUCKET_HOURS[bucketsSorted[0][0]]);
        if (bucketsSorted[1] && bucketsSorted[1][1] >= bucketsSorted[0][1] * 0.6) {
            hours.push(BUCKET_HOURS[bucketsSorted[1][0]]);
        }
    }
    if (hours.length) learned.preferred_hours = hours.filter(Boolean);

    // interests — from top features, stripping the "(N פעמים)" suffix.
    const interests = (analysis.topFeatures || [])
        .map(f => String(f).replace(/\s*\(\d+.*?\)\s*$/, '').trim())
        .filter(Boolean)
        .slice(0, 10);
    if (interests.length) learned.interests = interests;

    // recurring_tasks — task contents that appear at least twice.
    const counts = new Map();
    for (const t of (tasks || [])) {
        const c = String(t.content || '').trim();
        if (c) counts.set(c.toLowerCase(), { display: c, n: (counts.get(c.toLowerCase())?.n || 0) + 1 });
    }
    const recurring = [];
    for (const { display, n } of counts.values()) if (n >= 2) recurring.push(display);
    if (recurring.length) learned.recurring_tasks = recurring.slice(0, 10);

    return learned;
}

async function learnUserProfile(repos, opts = {}) {
    try {
        const [chats, tasks, memContents] = await Promise.all([
            repos.chat.recentForSearch(200),
            repos.tasks.allBasic(),
            repos.memories.allContents(),
        ]);

        if (chats.length < 5) return { updated: false, reason: 'insufficient_data' };

        const data = {
            chats,
            tasks: tasks || [],
            memories: (memContents || []).map(c => ({ content: c })),
            contacts: [],
            reminders: [],
        };

        const analysis = analyzePatterns(data);
        const learned = deriveProfile(analysis, data.tasks);
        if (Object.keys(learned).length === 0) return { updated: false, reason: 'nothing_learned' };

        const existing = typeof opts.getProfile === 'function' ? await opts.getProfile() : null;
        const existingAuto = (existing && typeof existing.auto_learned === 'object' && existing.auto_learned) || {};
        const userOverridden = Array.isArray(existingAuto.user_overridden) ? existingAuto.user_overridden : [];

        // Visible fields: write the learned value only when the user hasn't set it.
        const visible = {};
        for (const key of LEARNABLE_FIELDS) {
            if (!userOverridden.includes(key) && learned[key]) visible[key] = learned[key];
        }

        const auto_learned = {
            ...existingAuto,
            ...learned,
            user_overridden: userOverridden,
            learned_at: new Date().toISOString(),
        };

        const payload = { ...visible, auto_learned, updated_at: new Date().toISOString() };

        if (existing?.id && existing.id !== 'local-fallback') {
            const { error } = await repos.profile.update(existing.id, payload);
            if (error) return { updated: false, reason: error.message };
        } else {
            const { error } = await repos.profile.create(payload);
            if (error) return { updated: false, reason: error.message };
        }
        return { updated: true, learned };
    } catch (err) {
        return { updated: false, reason: err.message };
    }
}

module.exports = { learnUserProfile, deriveProfile };
