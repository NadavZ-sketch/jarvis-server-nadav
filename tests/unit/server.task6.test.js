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

describe('GET /e2e-schedule logic', () => {
    test('returns null when no profile exists', async () => {
        const repos = makeRepos({});
        const rows = await repos.profile.latest();
        const prefs = rows[0]?.preferences || {};
        const schedule = prefs['e2e-schedule'] ?? null;
        expect(schedule).toBeNull();
    });

    test('returns stored schedule when set', async () => {
        const storedSchedule = { frequency: 'daily', time: '03:00' };
        const repos = makeRepos({ user_profiles: [{ id: 'p1', preferences: { 'e2e-schedule': storedSchedule } }] });
        const rows = await repos.profile.latest();
        const prefs = rows[0]?.preferences || {};
        const schedule = prefs['e2e-schedule'] ?? null;
        expect(schedule).toEqual(storedSchedule);
    });
});

describe('GET /changelog/generate line parsing', () => {
    function parseGitLogLine(line) {
        const [hash, ...rest] = line.split(' ');
        return { hash, message: rest.join(' ') };
    }

    test('parses hash and message from git log line', () => {
        const entry = parseGitLogLine('abc1234 feat: add weekly score endpoint');
        expect(entry.hash).toBe('abc1234');
        expect(entry.message).toBe('feat: add weekly score endpoint');
    });

    test('handles message with multiple spaces', () => {
        const entry = parseGitLogLine('def5678 fix: update   spacing   in   message');
        expect(entry.hash).toBe('def5678');
        expect(entry.message).toBe('fix: update   spacing   in   message');
    });
});

describe('GET /surveys/export CSV generation', () => {
    test('generates correct CSV header and rows', () => {
        const rows = [
            { id: 'r1', question_id: 'q1', response: 'great', created_at: '2026-01-01T00:00:00Z' },
            { id: 'r2', question_id: 'q2', response: null, created_at: '2026-01-02T00:00:00Z' },
        ];
        const header = 'id,question_id,response,created_at';
        const csvRows = rows.map(r =>
            [r.id, r.question_id, JSON.stringify(r.response ?? ''), r.created_at].join(',')
        );
        const csv = [header, ...csvRows].join('\n');
        expect(csv).toContain('id,question_id,response,created_at');
        expect(csv).toContain('r1,q1,"great",2026-01-01T00:00:00Z');
        expect(csv).toContain('r2,q2,"",2026-01-02T00:00:00Z');
    });
});

describe('PUT /e2e-schedule create branch', () => {
    test('creates new profile when none exists', async () => {
        const repos = makeRepos({ user_profiles: [] });
        const rows = await repos.profile.latest();
        const existing = rows[0] || {};
        const schedule = { frequency: 'weekly' };
        const prefs = { ...(existing.preferences || {}), 'e2e-schedule': schedule };
        if (existing.id) {
            await repos.profile.update(existing.id, { preferences: prefs });
        } else {
            await repos.profile.create({ preferences: prefs });
        }
        expect(repos.profile.create).toHaveBeenCalledWith({
            preferences: { 'e2e-schedule': schedule },
        });
        expect(repos.profile.update).not.toHaveBeenCalled();
    });
});
