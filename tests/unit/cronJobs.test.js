'use strict';
// Infra mocks so requiring server.js doesn't open sockets/timers.
jest.mock('openai', () => ({
    OpenAI: jest.fn().mockImplementation(() => ({
        audio: { transcriptions: { create: jest.fn().mockResolvedValue({ text: '' }) } },
    })),
    toFile: jest.fn().mockResolvedValue({}),
}));
jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({
    createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn().mockResolvedValue({ messageId: 'm' }) }),
}));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: 'bW9jaw==' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({
    initSync: jest.fn().mockResolvedValue(undefined),
    fullSyncFromDb: jest.fn().mockResolvedValue(undefined),
    appendChatMessage: jest.fn().mockResolvedValue(undefined),
    syncAll: jest.fn().mockResolvedValue(undefined),
}));

const { fireDueReminders } = require('../../server');
const { makeChain } = require('../helpers/supabaseMock');

const NOW = '2026-06-05T12:00:00.000Z';

describe('fireDueReminders', () => {
    test('no due reminders → zero counts', async () => {
        const db = { from: jest.fn(() => makeChain([])) };
        const res = await fireDueReminders(db, NOW);
        expect(res).toEqual({ fired: 0, rescheduled: 0 });
    });

    test('db error is swallowed and reported as zero counts', async () => {
        const db = { from: jest.fn(() => makeChain(null, { message: 'db down' })) };
        const res = await fireDueReminders(db, NOW);
        expect(res).toEqual({ fired: 0, rescheduled: 0 });
    });

    test('marks a one-time due reminder as fired', async () => {
        const chain = makeChain([{ id: 1, text: 'תרופה', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: null }]);
        const db = { from: jest.fn(() => chain) };
        const res = await fireDueReminders(db, NOW);
        expect(res).toEqual({ fired: 1, rescheduled: 0 });
        expect(chain.update).toHaveBeenCalledWith({ fired: true });
        expect(chain.eq).toHaveBeenCalledWith('id', 1);
    });

    test('reschedules a recurring reminder to its next occurrence', async () => {
        const chain = makeChain([{ id: 2, text: 'אימון', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: 'daily' }]);
        const db = { from: jest.fn(() => chain) };
        const res = await fireDueReminders(db, NOW);
        expect(res).toEqual({ fired: 0, rescheduled: 1 });
        const updateArg = chain.update.mock.calls.find(c => c[0].fired === false)[0];
        expect(updateArg).toMatchObject({ fired: false });
        expect(typeof updateArg.scheduled_time).toBe('string');
        expect(new Date(updateArg.scheduled_time).getTime()).toBeGreaterThan(new Date('2026-06-05T11:00:00.000Z').getTime());
    });

    test('handles a mixed batch of one-time and recurring reminders', async () => {
        const chain = makeChain([
            { id: 1, text: 'a', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: null },
            { id: 2, text: 'b', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: 'weekly' },
        ]);
        const db = { from: jest.fn(() => chain) };
        const res = await fireDueReminders(db, NOW);
        expect(res).toEqual({ fired: 1, rescheduled: 1 });
    });
});
