'use strict';
const { learnUserProfile, deriveProfile } = require('../../services/profileLearner');

describe('deriveProfile', () => {
    test('derives preferred_hours, interests and recurring_tasks', () => {
        const analysis = {
            buckets: { morning: 1, afternoon: 2, evening: 10, night: 0 },
            topFeatures: ['כדורגל / ספורט (12 פעמים)', 'משימות (5 פעמים)'],
        };
        const tasks = [
            { content: 'ללכת לחדר כושר' },
            { content: 'ללכת לחדר כושר' },
            { content: 'משימה חד פעמית' },
        ];
        const learned = deriveProfile(analysis, tasks);
        expect(learned.preferred_hours).toContain('17:00-22:00');
        expect(learned.interests).toContain('כדורגל / ספורט');
        expect(learned.recurring_tasks).toContain('ללכת לחדר כושר');
        expect(learned.recurring_tasks).not.toContain('משימה חד פעמית');
    });

    test('empty analysis yields nothing learned', () => {
        const learned = deriveProfile({ buckets: { morning: 0, afternoon: 0, evening: 0, night: 0 }, topFeatures: [] }, []);
        expect(Object.keys(learned)).toHaveLength(0);
    });
});

describe('learnUserProfile', () => {
    function makeChain(result) {
        const chain = {
            then(res) { return Promise.resolve(result).then(res); },
            select: jest.fn(() => chain),
            order: jest.fn(() => chain),
            limit: jest.fn(() => chain),
            eq: jest.fn(() => chain),
            update: jest.fn(() => chain),
            insert: jest.fn(() => chain),
        };
        return chain;
    }

    function makeSupabase(chats, tasks, capture) {
        return {
            from: jest.fn((table) => {
                if (table === 'chat_history') return makeChain({ data: chats, error: null });
                if (table === 'tasks') return makeChain({ data: tasks, error: null });
                if (table === 'memories') return makeChain({ data: [], error: null });
                // user_profiles write
                const chain = makeChain({ data: null, error: null });
                chain.update = jest.fn((p) => { if (capture) capture.payload = p; return chain; });
                chain.insert = jest.fn((p) => { if (capture) capture.payload = Array.isArray(p) ? p[0] : p; return chain; });
                return chain;
            }),
        };
    }

    const manyChats = Array.from({ length: 10 }, () => ({
        role: 'user', text: 'כדורגל', created_at: new Date().toISOString(),
    }));

    test('learns and updates an existing profile', async () => {
        const supabase = makeSupabase(manyChats, []);
        const getProfile = jest.fn().mockResolvedValue({ id: 'p1', auto_learned: {} });
        const r = await learnUserProfile(supabase, { getProfile });
        expect(r.updated).toBe(true);
    });

    test('skips when there is too little chat history', async () => {
        const supabase = makeSupabase([{ role: 'user', text: 'hi', created_at: new Date().toISOString() }], []);
        const r = await learnUserProfile(supabase, {});
        expect(r.updated).toBe(false);
        expect(r.reason).toBe('insufficient_data');
    });

    test('does not overwrite a user-set field but still tracks it in auto_learned', async () => {
        const capture = {};
        const supabase = makeSupabase(manyChats, [], capture);
        const getProfile = jest.fn().mockResolvedValue({ id: 'p1', auto_learned: { user_overridden: ['interests'] } });
        const r = await learnUserProfile(supabase, { getProfile });
        expect(r.updated).toBe(true);
        expect(capture.payload.interests).toBeUndefined();           // user-owned → not written to visible field
        expect(capture.payload.auto_learned.interests).toBeDefined(); // still learned/recorded
        expect(capture.payload.auto_learned.user_overridden).toContain('interests');
    });

    test('inserts when no profile exists', async () => {
        const capture = {};
        const supabase = makeSupabase(manyChats, [], capture);
        const r = await learnUserProfile(supabase, { getProfile: jest.fn().mockResolvedValue(null) });
        expect(r.updated).toBe(true);
        expect(capture.payload).toBeDefined();
    });
});
