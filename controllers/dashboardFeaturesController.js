'use strict';

// Feature tracker for the control-center dashboard — a simple three-bucket
// (done/building/planned) board backed by features.json, not Supabase. Fully
// self-contained: no shared state with the backlog/proposals cluster beyond
// GET /dashboard/backlog also reading this same file for its roadmap view.

const fs = require('fs');
const path = require('path');
const { callGemma4 } = require('../agents/models');
const { writeJsonAtomic } = require('../services/jsonFileStore');

const VALID_STATUSES = ['done', 'building', 'planned'];

function createDashboardFeaturesController() {
    const FEATURES_PATH = path.join(__dirname, '..', 'features.json');

    function readFeatures() {
        return JSON.parse(fs.readFileSync(FEATURES_PATH, 'utf8'));
    }

    function statusHe(status) {
        return status === 'done' ? 'הושלמה' : status === 'building' ? 'בפיתוח' : 'מתוכננת';
    }

    return {
        list(_req, res) {
            try {
                res.json(readFeatures());
            } catch {
                res.status(500).json({ error: 'features.json not found' });
            }
        },

        // Move a feature between buckets and/or update its description.
        move(req, res) {
            const { name, oldStatus, newStatus, desc } = req.body;
            if (!name || !oldStatus) return res.status(400).json({ error: 'name and oldStatus required' });
            if (!VALID_STATUSES.includes(oldStatus)) return res.status(400).json({ error: 'invalid oldStatus' });
            const dst = VALID_STATUSES.includes(newStatus) ? newStatus : oldStatus;
            try {
                const data = readFeatures();
                const feats = data.features;
                const idx = (feats[oldStatus] || []).findIndex(f => f.name === name);
                if (idx === -1) return res.status(404).json({ error: 'Feature not found' });
                const feature = { ...feats[oldStatus][idx] };
                if (desc !== undefined) feature.desc = desc;
                feats[oldStatus].splice(idx, 1);
                if (!feats[dst]) feats[dst] = [];
                feats[dst].push(feature);
                data.lastUpdated = new Date().toISOString().slice(0, 10);
                writeJsonAtomic(FEATURES_PATH, data);
                res.json({ ok: true, feature, movedFrom: oldStatus, movedTo: dst });
            } catch (err) {
                console.error('PATCH /dashboard/features error:', err.message);
                res.status(500).json({ error: 'Internal error' });
            }
        },

        create(req, res) {
            const { name, desc = '', status = 'planned' } = req.body;
            if (!name?.trim()) return res.status(400).json({ error: 'name required' });
            const bucket = VALID_STATUSES.includes(status) ? status : 'planned';
            try {
                const data = readFeatures();
                if (!data.features[bucket]) data.features[bucket] = [];
                // Prevent duplicates
                const exists = (data.features.done || []).concat(data.features.building || [], data.features.planned || [])
                    .some(f => f.name.trim().toLowerCase() === name.trim().toLowerCase());
                if (exists) return res.status(409).json({ error: 'Feature with this name already exists' });
                data.features[bucket].push({ name: name.trim(), desc: desc.trim() });
                data.lastUpdated = new Date().toISOString().slice(0, 10);
                writeJsonAtomic(FEATURES_PATH, data);
                res.json({ ok: true });
            } catch (err) {
                console.error('POST /dashboard/features error:', err.message);
                res.status(500).json({ error: 'Internal error' });
            }
        },

        remove(req, res) {
            const { name, status } = req.body;
            if (!name || !status) return res.status(400).json({ error: 'name and status required' });
            try {
                const data = readFeatures();
                const before = (data.features[status] || []).length;
                data.features[status] = (data.features[status] || []).filter(f => f.name !== name);
                if (data.features[status].length === before) return res.status(404).json({ error: 'Not found' });
                data.lastUpdated = new Date().toISOString().slice(0, 10);
                writeJsonAtomic(FEATURES_PATH, data);
                res.json({ ok: true });
            } catch (err) {
                console.error('DELETE /dashboard/features error:', err.message);
                res.status(500).json({ error: 'Internal error' });
            }
        },

        async suggestDescription(req, res) {
            const { name, status = 'planned' } = req.body;
            if (!name?.trim()) return res.status(400).json({ error: 'name required' });
            try {
                const prompt = `אתה מתאר יכולת של "ג'רביס" — עוזר AI אישי בעברית (Flutter + Node.js).

יכולת: "${name}" (סטטוס: ${statusHe(status)})

כתוב תיאור קצר וברור של היכולת — 1-2 משפטים בעברית.
התיאור צריך להסביר: מה היכולת עושה ואיך היא מועילה למשתמש.
ענה בתיאור בלבד, ללא כותרת, ללא JSON.`;
                const raw = await callGemma4(prompt, false, 200);
                const description = raw.trim().replace(/^["']|["']$/g, '').slice(0, 300);
                res.json({ description });
            } catch (err) {
                console.error('POST /dashboard/features/suggest-description error:', err.message);
                res.status(500).json({ error: 'שגיאה בייצור תיאור' });
            }
        },

        async generateDescriptions(req, res) {
            const { features = [] } = req.body; // [{ name, status, desc }]
            const needDesc = features.filter(f => !f.desc?.trim()).slice(0, 12); // cap at 12
            if (needDesc.length === 0) return res.json({ descriptions: [] });
            try {
                const list = needDesc.map(f => `- "${f.name}" (${statusHe(f.status)})`).join('\n');
                const prompt = `אתה מתאר יכולות של "ג'רביס" — עוזר AI אישי בעברית (Flutter + Node.js).

צור תיאור קצר (משפט אחד, עד 100 תווים) לכל יכולת הבאה:
${list}

ענה JSON בלבד (ללא markdown):
[{"name":"שם היכולת","description":"תיאור קצר"}]`;
                const raw = await callGemma4(prompt, false, 800);
                const stripped = raw.replace(/```(?:json)?/gi, '').replace(/```/g, '').trim();
                const start = stripped.indexOf('[');
                const end   = stripped.lastIndexOf(']');
                if (start === -1 || end === -1) return res.json({ descriptions: [] });
                const parsed = JSON.parse(stripped.slice(start, end + 1));
                const descriptions = (Array.isArray(parsed) ? parsed : [])
                    .filter(d => d.name && d.description)
                    .map(d => ({ name: d.name.toString(), description: d.description.toString().slice(0, 150) }));
                res.json({ descriptions });
            } catch (err) {
                console.error('POST /dashboard/features/generate-descriptions error:', err.message);
                res.status(500).json({ error: 'שגיאה בייצור תיאורים' });
            }
        },
    };
}

module.exports = { createDashboardFeaturesController };
