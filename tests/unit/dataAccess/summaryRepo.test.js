'use strict';

const { createSummaryRepo } = require('../../../services/dataAccess/summaryRepo');
const { makeChain } = require('../../helpers/supabaseMock');

describe('summaryRepo', () => {
    test('get returns the summary or "" (swallows errors)', async () => {
        expect(await createSummaryRepo({ from: () => makeChain({ summary: 's' }) }).get('c1')).toBe('s');
        expect(await createSummaryRepo({ from: () => makeChain(null) }).get('c1')).toBe('');
    });

    test('getMeta returns the row or {}', async () => {
        expect(await createSummaryRepo({ from: () => makeChain({ turns_covered: 5, summary: 's' }) }).getMeta('c1'))
            .toEqual({ turns_covered: 5, summary: 's' });
        expect(await createSummaryRepo({ from: () => makeChain(null) }).getMeta('c1')).toEqual({});
    });

    test('upsert targets the chat_id conflict key', async () => {
        const chain = makeChain([], null);
        await createSummaryRepo({ from: () => chain }).upsert({ chat_id: 'c1', summary: 's' });
        expect(chain.upsert).toHaveBeenCalledWith({ chat_id: 'c1', summary: 's' }, { onConflict: 'chat_id' });
    });
});
