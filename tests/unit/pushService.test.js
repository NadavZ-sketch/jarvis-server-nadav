'use strict';

jest.mock('firebase-admin', () => ({
    apps: [],
    initializeApp: jest.fn(),
    credential: { cert: jest.fn() },
    messaging: jest.fn(() => ({
        sendEachForMulticast: jest.fn().mockResolvedValue({
            successCount: 1,
            responses: [{ success: true }],
        }),
    })),
}), { virtual: true });

jest.mock('axios', () => ({
    post: jest.fn().mockResolvedValue({ status: 200 }),
}), { virtual: true });

const pushService = require('../../services/pushService');

function makeMockSupabase(rows = []) {
    const chain = {
        data: rows,
        error: null,
        select: jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        upsert: jest.fn().mockReturnThis(),
        eq:     jest.fn().mockReturnThis(),
        in:     jest.fn().mockReturnThis(),
        then(fn) { return Promise.resolve({ data: rows, error: null }).then(fn); },
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('pushService', () => {
    beforeEach(() => jest.clearAllMocks());

    test('registerToken upserts into device_tokens', async () => {
        const mock = makeMockSupabase();
        pushService.init(mock);
        await pushService.registerToken({ token: 'tok123', platform: 'android' });
        expect(mock.from).toHaveBeenCalledWith('device_tokens');
        expect(mock._chain.upsert).toHaveBeenCalledWith(
            expect.objectContaining({ token: 'tok123', platform: 'android' }),
            expect.any(Object)
        );
    });

    test('sendPush with driver=none is a no-op', async () => {
        const origDriver = process.env.PUSH_DRIVER;
        delete process.env.PUSH_DRIVER;
        // Re-require to pick up the unset env
        jest.resetModules();
        const ps = require('../../services/pushService');
        await expect(ps.sendPush({ body: 'hello' })).resolves.toBeUndefined();
        process.env.PUSH_DRIVER = origDriver;
    });

    test('sendPush with driver=ntfy calls axios.post', async () => {
        process.env.PUSH_DRIVER = 'ntfy';
        process.env.NTFY_TOPIC = 'my-topic';
        jest.resetModules();
        jest.mock('axios', () => ({ post: jest.fn().mockResolvedValue({ status: 200 }) }), { virtual: true });
        const ps = require('../../services/pushService');
        const axios = require('axios');
        await ps.sendPush({ title: 'שלום', body: 'בדיקה' });
        expect(axios.post).toHaveBeenCalledWith(
            'https://ntfy.sh/my-topic',
            'בדיקה',
            expect.objectContaining({ headers: expect.objectContaining({ Title: 'שלום' }) })
        );
        delete process.env.PUSH_DRIVER;
        delete process.env.NTFY_TOPIC;
    });
});
