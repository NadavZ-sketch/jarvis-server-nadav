'use strict';

const {
    deriveStylePrefs, renderStyleHint, learnStyle, MIN_SIGNAL,
} = require('../../services/styleLearner');

const correction = (text) => ({ event_name: 'feedback_correction', metadata: { correction: text } });
const up = () => ({ event_name: 'feedback_up', event_value: 1, metadata: {} });
const down = () => ({ event_name: 'feedback_down', event_value: -1, metadata: {} });

describe('deriveStylePrefs', () => {
    it('learns nothing from an empty event list', () => {
        expect(deriveStylePrefs([]).prefs).toEqual({});
    });

    it('does not learn a preference below the threshold', () => {
        const events = [correction('תכלס קצר'), correction('בקיצור בבקשה')]; // only 2 < MIN_SIGNAL
        expect(deriveStylePrefs(events).prefs.response_length).toBeUndefined();
    });

    it('learns "shorter" once the directional cue repeats past the threshold', () => {
        const events = Array.from({ length: MIN_SIGNAL }, () => correction('זה ארוך מדי, בקיצור'));
        expect(deriveStylePrefs(events).prefs.response_length).toBe('shorter');
    });

    it('learns "longer" from detail-seeking corrections', () => {
        const events = [
            correction('קצר מדי, תפרט'),
            correction('תסביר יותר בבקשה'),
            correction('חסר הסבר, הרחב'),
        ];
        expect(deriveStylePrefs(events).prefs.response_length).toBe('longer');
    });

    it('ignores ambiguous bare words like "קצר" with no direction', () => {
        const events = Array.from({ length: 4 }, () => correction('קצר'));
        expect(deriveStylePrefs(events).prefs.response_length).toBeUndefined();
    });

    it('does not pick a side when both directions tie above threshold', () => {
        const events = [
            correction('ארוך מדי'), correction('בקיצור'), correction('תקצר'),
            correction('קצר מדי'), correction('תפרט'), correction('הרחב'),
        ];
        expect(deriveStylePrefs(events).prefs.response_length).toBeUndefined();
    });

    it('learns tone and language dimensions independently', () => {
        const events = [
            correction('תהיה רשמי יותר'), correction('פחות סלנג'), correction('מקצועי יותר'),
            correction('תכתוב בעברית'), correction('דבר עברית'), correction('תענה בעברית'),
        ];
        const { prefs } = deriveStylePrefs(events);
        expect(prefs.tone).toBe('formal');
        expect(prefs.language).toBe('hebrew');
    });

    it('reports a low satisfaction trend when down-votes dominate', () => {
        const events = [down(), down(), down(), up(), up()]; // 3/5 = 60% down
        expect(deriveStylePrefs(events).prefs.satisfaction).toBe('low');
    });

    it('reports high satisfaction when down-rate is very low', () => {
        const events = [up(), up(), up(), up(), up(), up()]; // 0% down
        expect(deriveStylePrefs(events).prefs.satisfaction).toBe('high');
    });

    it('stays silent on satisfaction below the minimum vote count', () => {
        const events = [down(), down()];
        expect(deriveStylePrefs(events).prefs.satisfaction).toBeUndefined();
    });
});

describe('renderStyleHint', () => {
    it('returns empty string for no prefs', () => {
        expect(renderStyleHint(null)).toBe('');
        expect(renderStyleHint({})).toBe('');
    });

    it('renders Hebrew lines for each learned dimension', () => {
        const out = renderStyleHint({ response_length: 'shorter', tone: 'casual', language: 'hebrew' });
        expect(out).toContain('קצר');
        expect(out).toContain('סלנג');
        expect(out).toContain('עברית');
    });
});

describe('learnStyle', () => {
    function makeSupabase(existing) {
        const update = jest.fn().mockResolvedValue({ error: null });
        const insert = jest.fn().mockResolvedValue({ error: null });
        const client = {
            from: jest.fn(() => ({ update: (p) => ({ eq: () => update(p) }), insert })),
        };
        return { client, update, insert };
    }
    const aggregateWith = (events) => async () => ({ ok: true, events });

    it('returns nothing_learned when no preference crosses the threshold', async () => {
        const { client } = makeSupabase(null);
        const res = await learnStyle(client, {
            aggregate: aggregateWith([correction('משהו ניטרלי')]),
        });
        expect(res.updated).toBe(false);
    });

    it('persists learned prefs into auto_learned.style_prefs, preserving other keys', async () => {
        const existing = { id: 'p1', auto_learned: { interests: ['ספורט'], user_overridden: [] } };
        const { client, update } = makeSupabase(existing);
        const events = Array.from({ length: MIN_SIGNAL }, () => correction('ארוך מדי, בקיצור'));

        const res = await learnStyle(client, {
            aggregate: aggregateWith(events),
            getProfile: async () => existing,
        });

        expect(res.updated).toBe(true);
        const payload = update.mock.calls[0][0];
        expect(payload.auto_learned.interests).toEqual(['ספורט']); // preserved
        expect(payload.auto_learned.style_prefs.response_length).toBe('shorter');
    });

    it('does not learn tone when speaking_tone is user-overridden', async () => {
        const existing = { id: 'p1', auto_learned: { user_overridden: ['speaking_tone'] } };
        const { client, update } = makeSupabase(existing);
        const events = [
            correction('תהיה רשמי יותר'), correction('פחות סלנג'), correction('מקצועי יותר'),
        ];
        const res = await learnStyle(client, {
            aggregate: aggregateWith(events),
            getProfile: async () => existing,
        });
        // tone was the only signal and it's overridden → nothing to write
        expect(res.updated).toBe(false);
        expect(update).not.toHaveBeenCalled();
    });
});
