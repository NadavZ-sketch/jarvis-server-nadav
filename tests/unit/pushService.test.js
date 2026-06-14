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

function makeRepos(rows = []) {
    const devices = {
        upsertToken:  jest.fn().mockResolvedValue({ error: null }),
        list:         jest.fn().mockResolvedValue(rows),
        deleteTokens: jest.fn().mockResolvedValue({ error: null }),
    };
    return { devices };
}

describe('pushService', () => {
    beforeEach(() => jest.clearAllMocks());

    test('registerToken upserts into device_tokens', async () => {
        const repos = makeRepos();
        pushService.init(repos);
        await pushService.registerToken({ token: 'tok123', platform: 'android' });
        expect(repos.devices.upsertToken).toHaveBeenCalledWith(
            expect.objectContaining({ token: 'tok123', platform: 'android' }),
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
