'use strict';
jest.mock('axios');
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const axios = require('axios');
const { callGemma4 } = require('../../agents/models');
const { runCalendarAgent, buildAuthUrl, getAccessToken } = require('../../agents/calendarAgent');

function makeRepos(tokenData = null) {
    return {
        profile: {
            getCalendarToken: jest.fn().mockResolvedValue(tokenData),
        },
    };
}

beforeEach(() => {
    jest.clearAllMocks();
    delete process.env.GOOGLE_CLIENT_ID;
    delete process.env.GOOGLE_CLIENT_SECRET;
});

// ── buildAuthUrl ──────────────────────────────────────────────────────────────

describe('buildAuthUrl', () => {
    test('returns Google OAuth URL with required params', () => {
        process.env.GOOGLE_CLIENT_ID = 'test-client-id';
        const url = buildAuthUrl('https://example.com/callback');
        expect(url).toContain('accounts.google.com');
        expect(url).toContain('client_id=test-client-id');
        expect(url).toContain('redirect_uri=');
        expect(url).toContain('response_type=code');
    });

    test('includes state param when provided', () => {
        process.env.GOOGLE_CLIENT_ID = 'test-client-id';
        const url = buildAuthUrl('https://example.com/callback', 'abc123nonce');
        expect(url).toContain('state=abc123nonce');
    });

    test('omits state param when not provided', () => {
        process.env.GOOGLE_CLIENT_ID = 'test-client-id';
        const url = buildAuthUrl('https://example.com/callback');
        expect(url).not.toContain('state=');
    });
});

// ── getAccessToken ────────────────────────────────────────────────────────────

describe('getAccessToken', () => {
    test('no stored token → returns null', async () => {
        const repos = makeRepos(null);
        expect(await getAccessToken(repos)).toBeNull();
    });

    test('stored token without refresh_token → returns null', async () => {
        const repos = makeRepos(JSON.stringify({ access_token: 'old' }));
        expect(await getAccessToken(repos)).toBeNull();
    });

    test('stored token with refresh_token → calls Google and returns access_token', async () => {
        axios.post.mockResolvedValueOnce({ data: { access_token: 'new-access-token' } });
        const stored = JSON.stringify({ refresh_token: 'rt-123', access_token: 'old' });
        const repos = makeRepos(stored);
        const token = await getAccessToken(repos);
        expect(token).toBe('new-access-token');
        expect(axios.post).toHaveBeenCalledWith(
            expect.stringContaining('oauth2.googleapis.com/token'),
            expect.objectContaining({ refresh_token: 'rt-123', grant_type: 'refresh_token' }),
        );
    });

    test('refresh request fails → returns null', async () => {
        axios.post.mockRejectedValueOnce(new Error('401 Unauthorized'));
        const repos = makeRepos(JSON.stringify({ refresh_token: 'bad-token' }));
        expect(await getAccessToken(repos)).toBeNull();
    });

    test('profile repo throws → returns null', async () => {
        const repos = {
            profile: { getCalendarToken: jest.fn().mockRejectedValue(new Error('DB error')) },
        };
        expect(await getAccessToken(repos)).toBeNull();
    });
});

// ── runCalendarAgent ──────────────────────────────────────────────────────────

describe('runCalendarAgent', () => {
    test('missing Google credentials → returns setup instructions', async () => {
        const repos = makeRepos(null);
        const result = await runCalendarAgent('מה יש לי היום', repos);
        expect(result.answer).toContain('GOOGLE_CLIENT_ID');
        expect(result.answer).toContain('.env');
    });

    test('no stored token → returns auth URL and open_url action', async () => {
        process.env.GOOGLE_CLIENT_ID     = 'cid';
        process.env.GOOGLE_CLIENT_SECRET = 'csec';
        const repos = makeRepos(null);
        const result = await runCalendarAgent('מה יש לי היום', repos);
        expect(result.answer).toContain('accounts.google.com');
        expect(result.action?.type).toBe('open_url');
    });

    test('list events today → returns formatted event list', async () => {
        process.env.GOOGLE_CLIENT_ID     = 'cid';
        process.env.GOOGLE_CLIENT_SECRET = 'csec';
        // Token refresh
        axios.post.mockResolvedValueOnce({ data: { access_token: 'tok' } });
        // listEvents
        axios.get.mockResolvedValueOnce({
            data: {
                items: [
                    { summary: 'פגישת צוות', start: { dateTime: '2026-05-19T09:00:00+03:00' }, end: { dateTime: '2026-05-19T10:00:00+03:00' } },
                ],
            },
        });
        const repos = makeRepos(JSON.stringify({ refresh_token: 'rt' }));
        const result = await runCalendarAgent('מה יש לי היום', repos);
        expect(result.answer).toContain('פגישת צוות');
        expect(result.answer).toContain('📅');
    });

    test('no events today → empty message', async () => {
        process.env.GOOGLE_CLIENT_ID     = 'cid';
        process.env.GOOGLE_CLIENT_SECRET = 'csec';
        axios.post.mockResolvedValueOnce({ data: { access_token: 'tok' } });
        axios.get.mockResolvedValueOnce({ data: { items: [] } });
        const repos = makeRepos(JSON.stringify({ refresh_token: 'rt' }));
        const result = await runCalendarAgent('מה יש לי היום', repos);
        expect(result.answer).toContain('אין אירועים');
    });

    test('create event → calls Calendar API and returns confirmation', async () => {
        process.env.GOOGLE_CLIENT_ID     = 'cid';
        process.env.GOOGLE_CLIENT_SECRET = 'csec';
        axios.post
            .mockResolvedValueOnce({ data: { access_token: 'tok' } })  // refresh
            .mockResolvedValueOnce({ data: { id: 'evt-1', htmlLink: 'https://cal.google.com/evt-1' } }); // createEvent
        callGemma4.mockResolvedValueOnce('{"summary":"ישיבה","startDateTime":"2026-05-20T10:00:00+03:00","endDateTime":"2026-05-20T11:00:00+03:00","description":"","location":""}');
        const repos = makeRepos(JSON.stringify({ refresh_token: 'rt' }));
        const result = await runCalendarAgent('קבע ישיבה מחר בעשר', repos);
        expect(result.answer).toContain('ישיבה');
        expect(result.answer).toContain('✅');
        expect(result.action?.type).toBe('calendar_event');
        expect(result.action?.eventId).toBe('evt-1');
    });

    test('upcoming 7 days (generic query) → returns event list', async () => {
        process.env.GOOGLE_CLIENT_ID     = 'cid';
        process.env.GOOGLE_CLIENT_SECRET = 'csec';
        axios.post.mockResolvedValueOnce({ data: { access_token: 'tok' } });
        axios.get.mockResolvedValueOnce({
            data: { items: [{ summary: 'ביקור רופא', start: { dateTime: '2026-05-21T14:00:00+03:00' }, end: { dateTime: '2026-05-21T15:00:00+03:00' } }] },
        });
        const repos = makeRepos(JSON.stringify({ refresh_token: 'rt' }));
        const result = await runCalendarAgent('מה יש לי השבוע', repos);
        expect(result.answer).toContain('ביקור רופא');
    });

    test('no upcoming events → empty upcoming message', async () => {
        process.env.GOOGLE_CLIENT_ID     = 'cid';
        process.env.GOOGLE_CLIENT_SECRET = 'csec';
        axios.post.mockResolvedValueOnce({ data: { access_token: 'tok' } });
        axios.get.mockResolvedValueOnce({ data: { items: [] } });
        const repos = makeRepos(JSON.stringify({ refresh_token: 'rt' }));
        const result = await runCalendarAgent('מה יש לי', repos);
        expect(result.answer).toContain('אין אירועים');
    });
});
