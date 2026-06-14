'use strict';

const { createSurveyRepo } = require('../../../services/dataAccess/surveyRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('surveyRepo', () => {
    test('recentCompleted filters by user + cooldown cutoff', async () => {
        const chain = makeChain([{ id: 1 }]);
        const repo = createSurveyRepo({ from: () => chain });
        await repo.recentCompleted('דנה', '2026-06-01');
        expect(chain.eq).toHaveBeenCalledWith('user_name', 'דנה');
        expect(chain.gte).toHaveBeenCalledWith('completed_at', '2026-06-01');
    });

    test('insertGraceful retries without the cooldown columns on a column error', async () => {
        const err = makeChain(null, { message: 'column "question_ids" does not exist' });
        const ok  = makeChain([], null);
        const supabase = { from: jest.fn().mockReturnValueOnce(err).mockReturnValueOnce(ok) };
        const repo = createSurveyRepo(supabase);
        const { error } = await repo.insertGraceful({ user_name: 'x', summary: 's', completed_at: 't', question_ids: ['a'] });
        expect(error).toBeNull();
        expect(ok.insert).toHaveBeenCalledWith([{ user_name: 'x', summary: 's' }]);
    });

    test('historyForUser throws on error', async () => {
        const bad = createSurveyRepo({ from: () => makeChain(null, { message: 'boom' }) });
        await expect(bad.historyForUser('x')).rejects.toEqual({ message: 'boom' });
    });

    test('recentResponsesById reads by user_id', async () => {
        const chain = makeChain([{ responses: '{}' }]);
        await createSurveyRepo({ from: () => chain }).recentResponsesById('u1', 5);
        expect(chain.eq).toHaveBeenCalledWith('user_id', 'u1');
        expect(chain.limit).toHaveBeenCalledWith(5);
    });
});
