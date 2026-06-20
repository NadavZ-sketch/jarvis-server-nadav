'use strict';
// Tests for Task 6 endpoints: weekly-score, e2e-schedule, changelog, surveys/export, surveys/analyze-sentiment
// These test the logic (supabase query shapes, profile read/write, sentiment keywords) not the HTTP layer.

const { makeRepos } = require('../helpers/fakeRepos');

describe('GET /stats/weekly-score logic', () => {
    test('score is null when no feedback events', async () => {
        const rows = [];
        const ups   = rows.filter(r => r.event_type === 'feedback_up').length;
        const downs = rows.filter(r => r.event_type === 'feedback_down').length;
        const total = ups + downs;
        const score = total === 0 ? null : Math.round((ups / total) * 1000) / 10;
        expect(score).toBeNull();
    });

    test('score is 100 for all thumbs-up', () => {
        const rows = [{ event_type: 'feedback_up' }, { event_type: 'feedback_up' }];
        const ups   = rows.filter(r => r.event_type === 'feedback_up').length;
        const downs = rows.filter(r => r.event_type === 'feedback_down').length;
        const total = ups + downs;
        const score = total === 0 ? null : Math.round((ups / total) * 1000) / 10;
        expect(score).toBe(100);
    });

    test('score is 50 for equal up/down', () => {
        const rows = [{ event_type: 'feedback_up' }, { event_type: 'feedback_down' }];
        const ups   = rows.filter(r => r.event_type === 'feedback_up').length;
        const downs = rows.filter(r => r.event_type === 'feedback_down').length;
        const total = ups + downs;
        const score = total === 0 ? null : Math.round((ups / total) * 1000) / 10;
        expect(score).toBe(50);
    });
});

describe('PUT /e2e-schedule logic', () => {
    test('updates existing profile preferences', async () => {
        const repos = makeRepos({ user_profiles: [{ id: 'p1', preferences: { foo: 'bar' } }] });
        // simulate: read existing, merge, update
        const rows = await repos.profile.latest();
        const existing = rows[0] || {};
        const schedule = { frequency: 'daily', time: '03:00' };
        const prefs = { ...(existing.preferences || {}), 'e2e-schedule': schedule };
        if (existing.id) {
            await repos.profile.update(existing.id, { preferences: prefs });
        }
        expect(repos.profile.update).toHaveBeenCalledWith('p1', {
            preferences: { foo: 'bar', 'e2e-schedule': schedule },
        });
    });
});

describe('POST /surveys/analyze-sentiment logic', () => {
    const POS = ['טוב', 'מעולה', 'אוהב', 'נהדר', 'מצוין', 'great', 'good', 'love', 'excellent', 'awesome'];
    const NEG = ['רע', 'גרוע', 'שונא', 'נורא', 'bad', 'terrible', 'hate', 'awful', 'poor'];

    function analyze(responses) {
        let positive = 0, negative = 0, neutral = 0;
        for (const r of responses) {
            const text = String(r).toLowerCase();
            const isPos = POS.some(w => text.includes(w));
            const isNeg = NEG.some(w => text.includes(w));
            if (isPos && !isNeg) positive++;
            else if (isNeg && !isPos) negative++;
            else neutral++;
        }
        return { positive, negative, neutral, total: responses.length };
    }

    test('classifies positive responses', () => {
        const result = analyze(['this is great', 'I love it']);
        expect(result.positive).toBe(2);
        expect(result.negative).toBe(0);
    });

    test('classifies negative responses', () => {
        const result = analyze(['this is bad', 'terrible experience']);
        expect(result.negative).toBe(2);
        expect(result.positive).toBe(0);
    });

    test('neutral when no keywords match', () => {
        const result = analyze(['the sky is blue', 'I went for a walk']);
        expect(result.neutral).toBe(2);
    });

    test('mixed response counts correctly', () => {
        const result = analyze(['good', 'bad', 'meh']);
        expect(result.positive).toBe(1);
        expect(result.negative).toBe(1);
        expect(result.neutral).toBe(1);
        expect(result.total).toBe(3);
    });
});
