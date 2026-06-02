'use strict';

const { classifyIntentDetailed, classifyIntent } = require('../../agents/router');

describe('classifyIntentDetailed', () => {
    it('returns chat with no matches for plain conversation', () => {
        const r = classifyIntentDetailed('שלום מה שלומך');
        expect(r.intent).toBe('chat');
        expect(r.matches).toEqual([]);
        expect(r.ambiguous).toBe(false);
    });

    it('returns a single confident match for a clear intent', () => {
        const r = classifyIntentDetailed('מה התחזית מזג אוויר מחר');
        expect(r.intent).toBe('weather');
        expect(r.matches).toEqual(['weather']);
        expect(r.ambiguous).toBe(false);
    });

    it('flags ambiguity when multiple keyword intents match', () => {
        // "תזכיר לי מה אמרת" matches both past_conv and reminder patterns.
        const r = classifyIntentDetailed('תזכיר לי מה אמרת לי אתמול');
        expect(r.ambiguous).toBe(true);
        expect(r.matches.length).toBeGreaterThan(1);
        // Best single guess is the first matching intent.
        expect(r.intent).toBe(r.matches[0]);
    });

    it('agrees with classifyIntent on the chosen intent (backward compatible)', () => {
        const inputs = [
            'מה התחזית מזג אוויר מחר',
            'הוסף משימה לקנות חלב',
            'שלום מה שלומך',
        ];
        for (const m of inputs) {
            expect(classifyIntentDetailed(m).intent).toBe(classifyIntent(m));
        }
    });
});
