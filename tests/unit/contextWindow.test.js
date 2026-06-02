'use strict';

const { estimateTokens, selectByTokenBudget } = require('../../services/contextWindow');

const msg = (text) => ({ role: 'user', text });

describe('estimateTokens', () => {
    it('returns 0 for empty/falsy input', () => {
        expect(estimateTokens('')).toBe(0);
        expect(estimateTokens(null)).toBe(0);
    });

    it('grows with text length', () => {
        expect(estimateTokens('שלום')).toBeLessThan(estimateTokens('שלום עולם גדול ויפה'));
    });
});

describe('selectByTokenBudget', () => {
    it('returns the input unchanged for empty/short histories', () => {
        expect(selectByTokenBudget([])).toEqual([]);
        const two = [msg('a'), msg('b')];
        expect(selectByTokenBudget(two)).toEqual(two);
    });

    it('keeps the most recent messages and drops the oldest first', () => {
        const history = Array.from({ length: 10 }, (_, i) => msg(`m${i}`));
        const kept = selectByTokenBudget(history, { maxMessages: 4, maxTokens: 99999 });
        expect(kept).toHaveLength(4);
        expect(kept.map(m => m.text)).toEqual(['m6', 'm7', 'm8', 'm9']);
    });

    it('preserves chronological order in the result', () => {
        const history = Array.from({ length: 6 }, (_, i) => msg(`m${i}`));
        const kept = selectByTokenBudget(history, { maxMessages: 3, maxTokens: 99999 });
        expect(kept.map(m => m.text)).toEqual(['m3', 'm4', 'm5']);
    });

    it('respects the token budget over the message cap', () => {
        const big = 'x'.repeat(600); // ~204 tokens each
        const history = Array.from({ length: 40 }, () => msg(big));
        const kept = selectByTokenBudget(history, { maxTokens: 600, maxMessages: 40 });
        // ~3 messages fit in 600 tokens; far fewer than the 40 cap.
        expect(kept.length).toBeGreaterThan(0);
        expect(kept.length).toBeLessThan(6);
    });

    it('always keeps at least the most recent message even if it exceeds the budget', () => {
        const huge = 'x'.repeat(100000);
        const kept = selectByTokenBudget([msg('old'), msg(huge)], { maxTokens: 10 });
        expect(kept).toHaveLength(1);
        expect(kept[0].text).toBe(huge);
    });

    it('prefers more short messages than few long ones for the same budget', () => {
        const shorts = Array.from({ length: 30 }, (_, i) => msg(`s${i}`));
        const longs = Array.from({ length: 30 }, () => msg('y'.repeat(300)));
        const keptShort = selectByTokenBudget(shorts, { maxTokens: 500, maxMessages: 40 });
        const keptLong = selectByTokenBudget(longs, { maxTokens: 500, maxMessages: 40 });
        expect(keptShort.length).toBeGreaterThan(keptLong.length);
    });
});
