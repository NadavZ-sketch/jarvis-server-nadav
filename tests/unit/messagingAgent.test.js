'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));

const { callGemma4 } = require('../../agents/models');
const { runMessagingAgent } = require('../../agents/messagingAgent');
const { makeRepos } = require('../helpers/fakeRepos');

// repos seeded with the given contact rows (searchByName returns them; the
// agent does finer name/alias matching in JS).
function reposWithContacts(rows = []) {
    return makeRepos({ contacts: rows });
}

beforeEach(() => {
    jest.clearAllMocks();
});

describe('runMessagingAgent', () => {
    describe('save_contact', () => {
        test('new contact → calls insert', async () => {
            callGemma4.mockResolvedValue(JSON.stringify({
                action: 'save_contact',
                channel: null,
                recipient_name: 'רון',
                recipient_phone: '0501234567',
                recipient_email: null,
                message_intent: null,
            }));
            // No existing contact
            const repos = reposWithContacts([]);
            const result = await runMessagingAgent('שמור רון 0501234567', repos);
            expect(repos.contacts.create).toHaveBeenCalledWith(
                expect.objectContaining({ name: 'רון', phone: '0501234567' })
            );
            expect(result.answer).toContain('נשמר');
        });

        test('existing contact → calls update, not insert', async () => {
            callGemma4.mockResolvedValue(JSON.stringify({
                action: 'save_contact',
                channel: null,
                recipient_name: 'רון',
                recipient_phone: '0509999999',
                recipient_email: null,
                message_intent: null,
            }));
            const repos = reposWithContacts([{ id: 1, name: 'רון', phone: '0501234567' }]);
            const result = await runMessagingAgent('עדכן רון', repos);
            expect(repos.contacts.updateById).toHaveBeenCalled();
            expect(repos.contacts.create).not.toHaveBeenCalled();
            expect(result.answer).toContain('עודכן');
        });
    });

    describe('phone number normalization', () => {
        test('Israeli 05x number gains 972 prefix', async () => {
            callGemma4
                .mockResolvedValueOnce(JSON.stringify({
                    action: 'send',
                    channel: 'whatsapp',
                    recipient_name: 'רון',
                    recipient_phone: null,
                    recipient_email: null,
                    message_intent: 'שלום',
                }))
                .mockResolvedValueOnce('היי רון!');

            const repos = reposWithContacts([{ id: 1, name: 'רון', phone: '0501234567' }]);
            const result = await runMessagingAgent('שלח ווצאפ לרון שלום', repos);
            expect(result.action.type).toBe('whatsapp');
            expect(result.action.phone).toBe('972501234567');
        });

        test('number already with 972 prefix is not doubled', async () => {
            callGemma4
                .mockResolvedValueOnce(JSON.stringify({
                    action: 'send',
                    channel: 'whatsapp',
                    recipient_name: 'רון',
                    recipient_phone: null,
                    recipient_email: null,
                    message_intent: 'שלום',
                }))
                .mockResolvedValueOnce('היי רון!');

            const repos = reposWithContacts([{ id: 1, name: 'רון', phone: '972501234567' }]);
            const result = await runMessagingAgent('שלח ווצאפ לרון שלום', repos);
            expect(result.action.phone).toBe('972501234567');
        });
    });

    describe('send message', () => {
        test('email channel → action.type is email', async () => {
            callGemma4
                .mockResolvedValueOnce(JSON.stringify({
                    action: 'send',
                    channel: 'email',
                    recipient_name: 'אמא',
                    recipient_phone: null,
                    recipient_email: null,
                    message_intent: 'שלום',
                }))
                .mockResolvedValueOnce('שלום אמא!');

            const repos = reposWithContacts([{ id: 2, name: 'אמא', email: 'mom@example.com' }]);
            const result = await runMessagingAgent('שלח מייל לאמא', repos);
            expect(result.action.type).toBe('email');
            expect(result.action.email).toBe('mom@example.com');
        });

        test('contact not found → returns not found message', async () => {
            callGemma4.mockResolvedValueOnce(JSON.stringify({
                action: 'send',
                channel: 'whatsapp',
                recipient_name: 'אריאל',
                recipient_phone: null,
                recipient_email: null,
                message_intent: 'שלום',
            }));
            const repos = reposWithContacts([]);
            const result = await runMessagingAgent('שלח ווצאפ לאריאל', repos);
            expect(result.action).toBeNull();
            expect(result.answer).toContain('לא מצאתי');
        });

        test('invalid JSON from LLM → returns error message', async () => {
            callGemma4.mockResolvedValue('not valid json at all');
            const repos = reposWithContacts();
            const result = await runMessagingAgent('שלח הודעה', repos);
            expect(result.answer).toContain('לא הצלחתי להבין');
            expect(result.action).toBeNull();
        });

        test('empty draft from LLM → returns error, no action', async () => {
            callGemma4
                .mockResolvedValueOnce(JSON.stringify({
                    action: 'send',
                    channel: 'whatsapp',
                    recipient_name: 'רון',
                    recipient_phone: null,
                    recipient_email: null,
                    message_intent: 'שלום',
                }))
                .mockResolvedValueOnce('');  // empty draft
            const repos = reposWithContacts([{ id: 1, name: 'רון', phone: '0501234567' }]);
            const result = await runMessagingAgent('שלח לרון', repos);
            expect(result.action).toBeNull();
            expect(result.answer).toContain('לא הצלחתי לנסח');
        });

        test('8-digit phone → rejected as invalid', async () => {
            callGemma4
                .mockResolvedValueOnce(JSON.stringify({
                    action: 'send',
                    channel: 'whatsapp',
                    recipient_name: 'רון',
                    recipient_phone: null,
                    recipient_email: null,
                    message_intent: 'שלום',
                }))
                .mockResolvedValueOnce('שלום רון');
            const repos = reposWithContacts([{ id: 1, name: 'רון', phone: '12345678' }]);
            const result = await runMessagingAgent('שלח ווצאפ לרון', repos);
            expect(result.action).toBeNull();
            expect(result.answer).toContain('לא תקין');
        });
    });
});
