'use strict';

// callGemma4 is the only external dependency — stub it so no network is hit.
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn().mockResolvedValue('סיכום קצר של השיחה'),
}));

const { updateSummaryIfNeeded } = require('../../services/conversationSummary');
const { callGemma4 } = require('../../agents/models');

// Builds a Supabase mock that reports `totalCount` via a head count, returns
// `existing` for the chat_summaries row, and records any upsert.
function makeSupabase({ totalCount, existing = null }) {
    const upsert = jest.fn().mockResolvedValue({ data: null, error: null });
    const from = jest.fn((table) => {
        if (table === 'chat_history') {
            return {
                select: jest.fn().mockReturnThis(),
                eq: jest.fn().mockResolvedValue({ count: totalCount, error: null }),
            };
        }
        // chat_summaries
        return {
            select: jest.fn().mockReturnThis(),
            eq: jest.fn().mockReturnThis(),
            maybeSingle: jest.fn().mockResolvedValue({ data: existing, error: null }),
            upsert,
        };
    });
    return { client: { from }, upsert };
}

const history = (n) => Array.from({ length: n }, (_, i) => ({
    role: i % 2 ? 'jarvis' : 'user', text: `הודעה ${i}`,
}));

beforeEach(() => callGemma4.mockClear());

describe('updateSummaryIfNeeded', () => {
    it('does nothing below the minimum total-turns threshold', async () => {
        const { client, upsert } = makeSupabase({ totalCount: 5 });
        await updateSummaryIfNeeded('c1', history(5), client);
        expect(callGemma4).not.toHaveBeenCalled();
        expect(upsert).not.toHaveBeenCalled();
    });

    it('creates a summary once enough turns exist and none is covered yet', async () => {
        const { client, upsert } = makeSupabase({ totalCount: 14, existing: null });
        await updateSummaryIfNeeded('c2', history(14), client);
        expect(callGemma4).toHaveBeenCalled();
        expect(upsert).toHaveBeenCalledWith(
            expect.objectContaining({ chat_id: 'c2', turns_covered: 14 }),
            expect.anything(),
        );
    });

    it('re-summarizes after only 4 new turns (lowered threshold)', async () => {
        const { client, upsert } = makeSupabase({
            totalCount: 20, existing: { turns_covered: 16, summary: 'קודם' },
        });
        await updateSummaryIfNeeded('c3', history(20), client);
        expect(callGemma4).toHaveBeenCalled();
        expect(upsert).toHaveBeenCalled();
    });

    it('skips when fewer than 4 new turns have accumulated', async () => {
        const { client, upsert } = makeSupabase({
            totalCount: 18, existing: { turns_covered: 16, summary: 'קודם' },
        });
        await updateSummaryIfNeeded('c4', history(18), client);
        expect(callGemma4).not.toHaveBeenCalled();
        expect(upsert).not.toHaveBeenCalled();
    });

    it('uses the true total count (not the capped window) to keep advancing', async () => {
        // Window is capped at 40 messages, but the chat actually has 100 turns
        // and the last summary covered 40 — the head count must unblock it.
        const { client, upsert } = makeSupabase({
            totalCount: 100, existing: { turns_covered: 40, summary: 'קודם' },
        });
        await updateSummaryIfNeeded('c5', history(40), client);
        expect(callGemma4).toHaveBeenCalled();
        expect(upsert).toHaveBeenCalledWith(
            expect.objectContaining({ turns_covered: 100 }),
            expect.anything(),
        );
    });
});
