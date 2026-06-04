'use strict';

const {
    selectSurveyQuestions,
    SURVEY_QUESTIONS,
    buildSurveySummary,
    aggregateSurveys,
    insightsFromAggregation,
    isNegativeAnswer,
} = require('../../agents/surveyAgent');

describe('selectSurveyQuestions', () => {
    test('without exclusions: always includes responseQuality as anchor', () => {
        for (let i = 0; i < 10; i++) {
            const sel = selectSurveyQuestions({});
            expect(sel.responseQuality).toBe(SURVEY_QUESTIONS.responseQuality);
        }
    });

    test('returns between 3 and 8 questions', () => {
        for (let i = 0; i < 20; i++) {
            const sel = selectSurveyQuestions({});
            const n = Object.keys(sel).length;
            expect(n).toBeGreaterThanOrEqual(3);
            expect(n).toBeLessThanOrEqual(8);
        }
    });

    test('excludeIds filters out the listed question keys', () => {
        const exclude = ['responseQuality', 'taskUsage', 'reminderUsage'];
        const sel = selectSurveyQuestions({}, exclude);
        for (const id of exclude) expect(sel[id]).toBeUndefined();
    });

    test('accepts a Set as excludeIds', () => {
        const sel = selectSurveyQuestions({}, new Set(['responseQuality']));
        expect(sel.responseQuality).toBeUndefined();
    });
});

describe('buildSurveySummary (deterministic, no LLM)', () => {
    const survey = [
        { id: 'responseQuality', question: SURVEY_QUESTIONS.responseQuality.question },
        { id: 'dailyValue', question: SURVEY_QUESTIONS.dailyValue.question },
    ];

    test('restates only the actual answers and flags concerns', () => {
        const { text, breakdown } = buildSurveySummary(
            survey,
            { responseQuality: 'מעולה', dailyValue: 'לא במיוחד' },
            'נדב',
        );
        expect(text).toContain('נדב');
        expect(text).toContain('מעולה');         // positive echoed
        expect(text).toContain('לא במיוחד');      // concern echoed
        const concern = breakdown.find(b => b.id === 'dailyValue');
        expect(concern.concern).toBe(true);
        const positive = breakdown.find(b => b.id === 'responseQuality');
        expect(positive.concern).toBe(false);
    });

    test('ignores unanswered questions', () => {
        const { breakdown } = buildSurveySummary(survey, { responseQuality: 'טובה' }, '');
        expect(breakdown).toHaveLength(1);
    });
});

describe('aggregateSurveys (real counts, not LLM)', () => {
    const rows = [
        { responses: { responseQuality: 'מעולה', dailyValue: 'מאוד' }, created_at: '2026-01-01' },
        { responses: JSON.stringify({ responseQuality: 'מעולה', dailyValue: 'קצת' }), created_at: '2026-02-01' },
        { responses: { responseQuality: 'טובה' }, created_at: '2026-03-01' },
    ];

    test('tallies answers with counts and percentages', () => {
        const agg = aggregateSurveys(rows);
        expect(agg.surveyCount).toBe(3);
        const rq = agg.questions.find(q => q.id === 'responseQuality');
        expect(rq.total).toBe(3);
        const top = rq.distribution[0];
        expect(top.answer).toBe('מעולה');
        expect(top.count).toBe(2);
        expect(top.pct).toBe(67);
    });

    test('builds chronological anchor trend', () => {
        const agg = aggregateSurveys(rows);
        expect(agg.anchorTrend.map(t => t.answer)).toEqual(['מעולה', 'מעולה', 'טובה']);
    });

    test('insightsFromAggregation reports only dominant answers', () => {
        const insights = insightsFromAggregation(aggregateSurveys(rows));
        expect(insights.some(i => i.includes('מעולה') && i.includes('67%'))).toBe(true);
    });
});

describe('isNegativeAnswer', () => {
    test('detects dissatisfaction phrases', () => {
        expect(isNegativeAnswer('לא כל כך')).toBe(true);
        expect(isNegativeAnswer('יש מקום לשיפור')).toBe(true);
        expect(isNegativeAnswer('בינונית')).toBe(true);
        expect(isNegativeAnswer('מעולה')).toBe(false);
        expect(isNegativeAnswer('כן מאוד')).toBe(false);
    });
});
