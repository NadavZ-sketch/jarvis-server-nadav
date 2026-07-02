'use strict';

// Router Trainer — closes the intent-router feedback loop. Two read-only
// signals (training-events: zero-keyword-match messages; misroutes: repeated
// 👎 patterns, see services/feedbackStore.computeMisroutePatterns) surface
// candidates for a human to turn into a keyword→intent override, applied via
// the keywords CRUD below. Overrides live in config/router-overrides.json,
// not Supabase — file-based so agents/router.js can load them with a cheap
// in-process TTL cache (see loadRouterOverrides/invalidateOverridesCache).

const fs = require('fs');
const path = require('path');
const { invalidateOverridesCache, VALID_INTENTS } = require('../agents/router');
const feedbackStore = require('../services/feedbackStore');
const { writeJsonAtomic } = require('../services/jsonFileStore');

function createRouterTrainerController({ supabase }) {
    const ROUTER_OVERRIDES_PATH = path.join(__dirname, '..', 'config', 'router-overrides.json');

    function readRouterOverrides() {
        try {
            const parsed = JSON.parse(fs.readFileSync(ROUTER_OVERRIDES_PATH, 'utf8'));
            return Array.isArray(parsed.overrides) ? parsed.overrides : [];
        } catch {
            return [];
        }
    }

    function writeRouterOverrides(overrides) {
        writeJsonAtomic(ROUTER_OVERRIDES_PATH, { overrides });
        invalidateOverridesCache();
    }

    return {
        async trainingEvents(req, res) {
            try {
                const limit = Math.min(Number(req.query.limit) || 50, 100);
                const { data, error } = await supabase
                    .from('smart_telemetry_events')
                    .select('id, metadata, created_at')
                    .eq('event_name', 'router_chat_default')
                    .order('created_at', { ascending: false })
                    .limit(limit);
                if (error) throw error;
                const events = (data || []).map(row => ({
                    id: row.id,
                    message: (row.metadata && row.metadata.message) ? row.metadata.message : '',
                    created_at: row.created_at,
                }));
                res.json({ events });
            } catch (err) {
                console.error('GET /router/training-events error:', err.message);
                res.status(500).json({ error: 'failed to fetch training events' });
            }
        },

        // Closes the router feedback loop: 👎 events carry the intent that produced
        // the reply (routeTracker, see POST /feedback in server.js). This surfaces
        // messages that were mis-routed the same way more than once — a human
        // still picks the correct intent and applies it via POST /router/keywords;
        // this endpoint only detects and proposes, it never writes an override.
        async misroutes(req, res) {
            try {
                const limit = Math.min(Number(req.query.limit) || 500, 1000);
                const minOccurrences = Math.max(Number(req.query.minOccurrences) || 2, 2);
                const { data, error } = await supabase
                    .from('smart_telemetry_events')
                    .select('metadata, created_at')
                    .eq('event_name', 'feedback_down')
                    .order('created_at', { ascending: false })
                    .limit(limit);
                if (error) throw error;
                const misroutes = feedbackStore.computeMisroutePatterns(data || [], { minOccurrences });
                res.json({ misroutes });
            } catch (err) {
                console.error('GET /router/misroutes error:', err.message);
                res.status(500).json({ error: 'failed to compute misroute patterns' });
            }
        },

        getKeywords(req, res) {
            try {
                const overrides = readRouterOverrides();
                res.json({ overrides });
            } catch (err) {
                console.error('GET /router/keywords error:', err.message);
                res.status(500).json({ error: 'failed to read overrides' });
            }
        },

        postKeywords(req, res) {
            try {
                const { keyword, intent } = req.body || {};
                if (!keyword || typeof keyword !== 'string' || !intent || typeof intent !== 'string') {
                    return res.status(400).json({ error: 'keyword and intent are required strings' });
                }
                const kw = keyword.trim();
                if (!kw) return res.status(400).json({ error: 'keyword must not be empty' });
                if (!VALID_INTENTS.has(intent)) return res.status(400).json({ error: `unknown intent: ${intent}` });
                const overrides = readRouterOverrides();
                const deduped = overrides.filter(o => !(o.keyword === kw && o.intent === intent));
                deduped.push({ keyword: kw, intent });
                writeRouterOverrides(deduped);
                res.json({ ok: true, overrides: deduped });
            } catch (err) {
                console.error('POST /router/keywords error:', err.message);
                res.status(500).json({ error: 'failed to save override' });
            }
        },

        deleteKeywords(req, res) {
            try {
                const { keyword, intent } = req.body || {};
                if (!keyword || typeof keyword !== 'string' || !intent || typeof intent !== 'string') {
                    return res.status(400).json({ error: 'keyword and intent are required strings' });
                }
                const kwToDelete = keyword.trim();
                const intentToDelete = intent.trim();
                const overrides = readRouterOverrides();
                const updated = overrides.filter(o => !(o.keyword === kwToDelete && o.intent === intentToDelete));
                writeRouterOverrides(updated);
                res.json({ ok: true, overrides: updated });
            } catch (err) {
                console.error('DELETE /router/keywords error:', err.message);
                res.status(500).json({ error: 'failed to delete override' });
            }
        },
    };
}

module.exports = { createRouterTrainerController };
