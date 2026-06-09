'use strict';

/**
 * dashboardLearner — derives a personalized control-center layout from how the
 * user actually uses the dashboard.
 *
 * Modeled on services/styleLearner.js and services/profileLearner.js: a thin,
 * deterministic (LLM-free) layer on top of the existing telemetry pipeline.
 * The frontend records `dashboard_tab_view` events via POST /dashboard/smart-
 * telemetry (metadata.tab = tab id); this module aggregates those counts
 * through feedbackStore.aggregateEvents and produces a "most-used first" tab
 * order plus the single most-used tab to spotlight.
 *
 * It never throws into the request path and always returns a sensible default
 * when there isn't enough signal yet.
 */

const feedbackStore = require('./feedbackStore');

// Canonical tab ids in their default (authoring) order.
const DEFAULT_ORDER = ['overview', 'agents', 'analytics', 'dev', 'qa', 'settings'];
// Below this many recorded views we don't reorder — avoids thrashing the layout
// off one or two clicks.
const MIN_SIGNAL = 5;

/**
 * @param {object} supabase
 * @param {{userId?:string, sinceDays?:number}} opts
 * @returns {Promise<{order:string[], spotlight:string|null, counts:object, learned:boolean}>}
 */
async function getDashboardLayout(supabase, { userId = 'default', sinceDays = 30 } = {}) {
    const fallback = { order: [...DEFAULT_ORDER], spotlight: null, counts: {}, learned: false };
    if (!supabase) return fallback;

    let agg;
    try {
        agg = await feedbackStore.aggregateEvents(supabase, { userId, sinceDays, limit: 2000 });
    } catch (err) {
        console.error('⚠️ dashboardLearner aggregate failed (suppressed):', err.message);
        return fallback;
    }
    if (!agg || !agg.ok) return fallback;

    // Count tab views from event metadata (event_name === 'dashboard_tab_view').
    const tabCounts = {};
    for (const ev of agg.events || []) {
        if (ev.event_name !== 'dashboard_tab_view') continue;
        const tab = ev.metadata && ev.metadata.tab;
        if (typeof tab === 'string' && DEFAULT_ORDER.includes(tab)) {
            tabCounts[tab] = (tabCounts[tab] || 0) + 1;
        }
    }

    const totalViews = Object.values(tabCounts).reduce((s, n) => s + n, 0);
    if (totalViews < MIN_SIGNAL) {
        return { ...fallback, counts: tabCounts };
    }

    // Stable sort: most-viewed first, ties keep the default authoring order.
    const order = [...DEFAULT_ORDER].sort((a, b) => {
        const diff = (tabCounts[b] || 0) - (tabCounts[a] || 0);
        if (diff !== 0) return diff;
        return DEFAULT_ORDER.indexOf(a) - DEFAULT_ORDER.indexOf(b);
    });
    const spotlight = order[0] && (tabCounts[order[0]] || 0) > 0 ? order[0] : null;

    return { order, spotlight, counts: tabCounts, learned: true };
}

module.exports = { getDashboardLayout, DEFAULT_ORDER, MIN_SIGNAL };
