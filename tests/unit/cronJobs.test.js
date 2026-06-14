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

const NOW = '2026-06-05T12:00:00.000Z';

// A reminder repo fake whose dueNow yields `due` (or throws `error`).
function makeReminders(due = [], error = null) {
    return {
        dueNow: error ? jest.fn(async () => { throw error; }) : jest.fn(async () => due),
        rescheduleRecurring: jest.fn(async () => ({ error: null })),
        markFired: jest.fn(async () => ({ error: null })),
    };
}

describe('fireDueReminders', () => {
    test('no due reminders → zero counts', async () => {
        const res = await fireDueReminders(makeReminders([]), NOW);
        expect(res).toEqual({ fired: 0, rescheduled: 0 });
    });

    test('db error is swallowed and reported as zero counts', async () => {
        const res = await fireDueReminders(makeReminders([], new Error('db down')), NOW);
        expect(res).toEqual({ fired: 0, rescheduled: 0 });
    });

    test('marks a one-time due reminder as fired', async () => {
        const reminders = makeReminders([{ id: 1, text: 'תרופה', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: null }]);
        const res = await fireDueReminders(reminders, NOW);
        expect(res).toEqual({ fired: 1, rescheduled: 0 });
        expect(reminders.markFired).toHaveBeenCalledWith(1);
    });

    test('reschedules a recurring reminder to its next occurrence', async () => {
        const reminders = makeReminders([{ id: 2, text: 'אימון', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: 'daily' }]);
        const res = await fireDueReminders(reminders, NOW);
        expect(res).toEqual({ fired: 0, rescheduled: 1 });
        const [id, iso] = reminders.rescheduleRecurring.mock.calls[0];
        expect(id).toBe(2);
        expect(new Date(iso).getTime()).toBeGreaterThan(new Date('2026-06-05T11:00:00.000Z').getTime());
    });

    test('handles a mixed batch of one-time and recurring reminders', async () => {
        const reminders = makeReminders([
            { id: 1, text: 'a', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: null },
            { id: 2, text: 'b', scheduled_time: '2026-06-05T11:00:00.000Z', recurrence: 'weekly' },
        ]);
        const res = await fireDueReminders(reminders, NOW);
        expect(res).toEqual({ fired: 1, rescheduled: 1 });
    });
});
