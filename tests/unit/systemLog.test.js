'use strict';

function makeMockSupabase() {
    const chain = {
        insert: jest.fn().mockResolvedValue({ data: null, error: null }),
        then(fn) { return Promise.resolve({ data: null, error: null }).then(fn); },
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('systemLog', () => {
    let systemLog;
    let mockSupabase;
    let mockPush;

    beforeEach(() => {
        jest.resetModules();
        systemLog   = require('../../services/systemLog');
        mockSupabase = makeMockSupabase();
        mockPush     = { sendPush: jest.fn().mockResolvedValue(undefined) };
        systemLog.init(mockSupabase, mockPush);
    });

    test('logEvent inserts into system_events', async () => {
        await systemLog.logEvent('error', 'test:source', 'something broke', { detail: 'x' });
        expect(mockSupabase.from).toHaveBeenCalledWith('system_events');
        expect(mockSupabase._chain.insert).toHaveBeenCalledWith([
            expect.objectContaining({
                level: 'error',
                source: 'test:source',
                message: 'something broke',
                acked: false,
            }),
        ]);
    });

    test('logError extracts message and stack from Error', async () => {
        const err = new Error('oops');
        await systemLog.logError('agent:chatAgent', err);
        expect(mockSupabase._chain.insert).toHaveBeenCalledWith([
            expect.objectContaining({ level: 'error', message: 'oops' }),
        ]);
    });

    test('critical level triggers push notification', async () => {
        await systemLog.logCritical('cron:morning_briefing', new Error('cron failed'));
        expect(mockPush.sendPush).toHaveBeenCalledWith(
            expect.objectContaining({ title: expect.stringContaining('קריטית'), category: 'alert' })
        );
    });

    test('critical push is rate-limited per fingerprint (6h cooldown)', async () => {
        const err = new Error('same error');
        await systemLog.logCritical('cron:test', err);
        await systemLog.logCritical('cron:test', err); // second call — same fingerprint
        expect(mockPush.sendPush).toHaveBeenCalledTimes(1); // only first gets a push
    });

    test('logEvent is resilient to Supabase failure', async () => {
        mockSupabase._chain.insert.mockRejectedValueOnce(new Error('db down'));
        // Must not throw
        await expect(systemLog.logEvent('warn', 'test', 'quiet failure')).resolves.toBeUndefined();
    });

    test('works without supabase (no crash)', async () => {
        jest.resetModules();
        const sl = require('../../services/systemLog');
        sl.init(null, null); // no supabase, no push
        await expect(sl.logError('anywhere', new Error('test'))).resolves.toBeUndefined();
    });
});
