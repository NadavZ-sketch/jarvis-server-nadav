'use strict';
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { selectSurveyQuestions, SURVEY_QUESTIONS } = require('../../agents/surveyAgent');

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

    test('when nearly all questions are excluded, returns the remaining ones', () => {
        const allKeys = Object.keys(SURVEY_QUESTIONS);
        const exclude = allKeys.slice(0, allKeys.length - 2); // leave 2
        const sel = selectSurveyQuestions({}, exclude);
        const keys = Object.keys(sel);
        expect(keys.length).toBeGreaterThanOrEqual(1);
        expect(keys.length).toBeLessThanOrEqual(2);
        for (const id of exclude) expect(sel[id]).toBeUndefined();
    });

    test('when ALL questions excluded, falls back to a small default set', () => {
        const allKeys = Object.keys(SURVEY_QUESTIONS);
        const sel = selectSurveyQuestions({}, allKeys);
        // Fallback returns at least one question to keep the survey useful.
        expect(Object.keys(sel).length).toBeGreaterThanOrEqual(1);
    });

    test('accepts a Set as excludeIds', () => {
        const sel = selectSurveyQuestions({}, new Set(['responseQuality']));
        expect(sel.responseQuality).toBeUndefined();
    });
});
