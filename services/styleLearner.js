'use strict';

/**
 * Deterministic style/preference learner — Phase 2 of the self-improvement loop.
 *
 * Consumes the explicit feedback recorded in Phase 0 (👍/👎 and free-text
 * corrections stored in `smart_telemetry_events`) and derives a small set of
 * response-style preferences that get injected back into the chat prompt.
 *
 * LLM-free and conservative by design (same philosophy as profileLearner): a
 * preference is only learned when a consistent, repeated signal crosses a
 * threshold, so a single bad answer never reshapes Jarvis's behaviour. The
 * result is written into user_profiles.auto_learned.style_prefs, preserving any
 * other auto-learned keys and never touching fields the user set manually.
 */

// A preference must be seen at least this many times before it's applied.
const MIN_SIGNAL = 3;
// Minimum total 👍/👎 votes before we report a satisfaction trend.
const MIN_VOTES_FOR_TREND = 5;

// Directional cue phrases. Only unambiguous, directional wording counts — bare
// "קצר"/"ארוך" is skipped because it could be a complaint in either direction.
const CUES = {
    lengthShorter: /ארוך מדי|יותר מדי ארוך|קצר יותר|בקיצור|תכל'?ס|בקצרה|תמציתי|מקוצר|אל תאריך|תקצר|נסה לקצר|פחות מילים/,
    lengthLonger:  /קצר מדי|יותר פרטים|תפרט|פרט יותר|הרחב|בהרחבה|מפורט יותר|תסביר יותר|לא מספיק מפורט|חסר הסבר|תרחיב/,
    toneFormal:    /רשמי יותר|פורמלי|מקצועי יותר|בכבוד|פחות סלנג|אל תשתמש בסלנג/,
    toneCasual:    /בסלנג|יותר חופשי|תהיה רגוע|פחות רשמי|אל תהיה רשמי|יותר ידידותי|דבר נורמלי|תהיה חברמן/,
    langHebrew:    /בעברית|תכתוב בעברית|דבר עברית|תענה בעברית/,
    langEnglish:   /באנגלית|in english|answer in english|reply in english/i,
};

/**
 * Pure: derives style preferences from a list of feedback events.
 * @param {Array<{event_name:string, event_value:number, metadata:object}>} events
 * @returns {{prefs:object, signals:object}}
 */
function deriveStylePrefs(events = []) {
    const s = {
        lengthShorter: 0, lengthLonger: 0,
        toneFormal: 0, toneCasual: 0,
        langHebrew: 0, langEnglish: 0,
        ups: 0, downs: 0,
    };

    for (const e of events) {
        if (e.event_name === 'feedback_up') s.ups++;
        else if (e.event_name === 'feedback_down') s.downs++;

        const text = e?.metadata?.correction;
        if (!text || typeof text !== 'string') continue;
        for (const key of ['lengthShorter', 'lengthLonger', 'toneFormal', 'toneCasual', 'langHebrew', 'langEnglish']) {
            if (CUES[key].test(text)) s[key]++;
        }
    }

    const prefs = {};

    // Each dimension: pick the side that crosses the threshold AND dominates.
    const pick = (a, b, aVal, bVal) => {
        if (s[a] >= MIN_SIGNAL && s[a] > s[b]) return aVal;
        if (s[b] >= MIN_SIGNAL && s[b] > s[a]) return bVal;
        return undefined;
    };

    const length = pick('lengthShorter', 'lengthLonger', 'shorter', 'longer');
    if (length) prefs.response_length = length;

    const tone = pick('toneFormal', 'toneCasual', 'formal', 'casual');
    if (tone) prefs.tone = tone;

    const language = pick('langHebrew', 'langEnglish', 'hebrew', 'english');
    if (language) prefs.language = language;

    const totalVotes = s.ups + s.downs;
    if (totalVotes >= MIN_VOTES_FOR_TREND) {
        const downRate = s.downs / totalVotes;
        if (downRate >= 0.4) prefs.satisfaction = 'low';
        else if (downRate <= 0.15) prefs.satisfaction = 'high';
        else prefs.satisfaction = 'neutral';
    }

    return { prefs, signals: s };
}

/**
 * Renders the learned style prefs as a short Hebrew prompt block, or '' if
 * nothing has been learned. Shared by both prompt builders.
 */
function renderStyleHint(prefs) {
    if (!prefs || typeof prefs !== 'object') return '';
    const lines = [];
    if (prefs.response_length === 'shorter') lines.push('המשתמש מעדיף תשובות קצרות וממוקדות — קצר כברירת מחדל.');
    if (prefs.response_length === 'longer')  lines.push('המשתמש מעדיף תשובות מפורטות ומלאות יותר.');
    if (prefs.tone === 'formal') lines.push('העדפת טון: רשמי ומקצועי יותר.');
    if (prefs.tone === 'casual') lines.push('העדפת טון: חופשי וידידותי, סלנג טבעי בסדר.');
    if (prefs.language === 'hebrew')  lines.push('העדפת שפה: עברית.');
    if (prefs.language === 'english') lines.push('העדפת שפה: אנגלית.');
    if (prefs.satisfaction === 'low') lines.push('שים לב: לאחרונה חלק מהתשובות לא קלעו — דייק ברלוונטיות.');
    return lines.join('\n');
}

/**
 * Reads recent feedback, derives prefs, and persists them into
 * user_profiles.auto_learned.style_prefs. Fire-and-forget friendly.
 * @param {object} supabase
 * @param {{getProfile?:Function, aggregate?:Function, onUpdate?:Function, sinceDays?:number}} [opts]
 */
async function learnStyle(supabase, opts = {}) {
    try {
        const aggregate = opts.aggregate || require('./feedbackStore').aggregateEvents;
        const agg = await aggregate(supabase, { sinceDays: opts.sinceDays ?? 30, limit: 1000 });
        const events = (agg && agg.events) || [];
        if (events.length === 0) return { updated: false, reason: 'no_events' };

        const { prefs } = deriveStylePrefs(events);
        if (Object.keys(prefs).length === 0) return { updated: false, reason: 'nothing_learned' };

        const existing = typeof opts.getProfile === 'function' ? await opts.getProfile() : null;
        const existingAuto = (existing && typeof existing.auto_learned === 'object' && existing.auto_learned) || {};
        const userOverridden = Array.isArray(existingAuto.user_overridden) ? existingAuto.user_overridden : [];

        // Respect a manually-set tone: don't let a learned tone fight an explicit choice.
        if (userOverridden.includes('speaking_tone')) delete prefs.tone;
        if (Object.keys(prefs).length === 0) return { updated: false, reason: 'all_overridden' };

        const auto_learned = {
            ...existingAuto,
            user_overridden: userOverridden,
            style_prefs: { ...prefs, learned_at: new Date().toISOString() },
        };
        const payload = { auto_learned, updated_at: new Date().toISOString() };

        if (existing?.id && existing.id !== 'local-fallback') {
            const { error } = await supabase.from('user_profiles').update(payload).eq('id', existing.id);
            if (error) return { updated: false, reason: error.message };
        } else {
            const { error } = await supabase.from('user_profiles').insert([payload]);
            if (error) return { updated: false, reason: error.message };
        }

        if (typeof opts.onUpdate === 'function') { try { opts.onUpdate(); } catch { /* ignore */ } }
        return { updated: true, learned: prefs };
    } catch (err) {
        return { updated: false, reason: err.message };
    }
}

module.exports = { deriveStylePrefs, renderStyleHint, learnStyle, MIN_SIGNAL, MIN_VOTES_FOR_TREND };
