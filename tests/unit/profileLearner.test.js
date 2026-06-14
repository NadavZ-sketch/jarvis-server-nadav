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
    // repos whose chat/tasks/memories reads return the seeded data and whose
    // profile writes capture the payload.
    function makeSupabase(chats, tasks, capture) {
        return {
            chat: { recentForSearch: jest.fn().mockResolvedValue(chats) },
            tasks: { allBasic: jest.fn().mockResolvedValue(tasks) },
            memories: { allContents: jest.fn().mockResolvedValue([]) },
            profile: {
                update: jest.fn(async (_id, p) => { if (capture) capture.payload = p; return { data: null, error: null }; }),
                create: jest.fn(async (p) => { if (capture) capture.payload = p; return { data: null, error: null }; }),
            },
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
