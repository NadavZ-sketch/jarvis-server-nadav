'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));

const { callGemma4 } = require('../../agents/models');
const { runMessagingAgent } = require('../../agents/messagingAgent');

function makeChain(data = [], error = null) {
    const chain = {
        then(res) { return Promise.resolve({ data, error }).then(res); },
        catch(rej) { return Promise.resolve({ data, error }).catch(rej); },
        select:  jest.fn().mockReturnThis(),
        insert:  jest.fn().mockReturnThis(),
        update:  jest.fn().mockReturnThis(),
        delete:  jest.fn().mockReturnThis(),
        eq:      jest.fn().mockReturnThis(),
        ilike:   jest.fn().mockReturnThis(),
    };
    return chain;
}

function makeSupabase(data, error) {
    const chain = makeChain(data, error);
    return { from: jest.fn(() => chain), _chain: chain };
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
            const supabase = makeSupabase([]);
            const result = await runMessagingAgent('שמור רון 0501234567', supabase);
            expect(supabase._chain.insert).toHaveBeenCalledWith([
                expect.objectContaining({ name: 'רון', phone: '0501234567' })
            ]);
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
            const supabase = makeSupabase([{ id: 1, name: 'רון', phone: '0501234567' }]);
            const result = await runMessagingAgent('עדכן רון', supabase);
            expect(supabase._chain.update).toHaveBeenCalled();
            expect(supabase._chain.insert).not.toHaveBeenCalled();
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

            const supabase = makeSupabase([{ id: 1, name: 'רון', phone: '0501234567' }]);
            const result = await runMessagingAgent('שלח ווצאפ לרון שלום', supabase);
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

            const supabase = makeSupabase([{ id: 1, name: 'רון', phone: '972501234567' }]);
            const result = await runMessagingAgent('שלח ווצאפ לרון שלום', supabase);
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

            const supabase = makeSupabase([{ id: 2, name: 'אמא', email: 'mom@example.com' }]);
            const result = await runMessagingAgent('שלח מייל לאמא', supabase);
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
            const supabase = makeSupabase([]);
            const result = await runMessagingAgent('שלח ווצאפ לאריאל', supabase);
            expect(result.action).toBeNull();
            expect(result.answer).toContain('לא מצאתי');
        });

        test('invalid JSON from LLM → returns error message', async () => {
            callGemma4.mockResolvedValue('not valid json at all');
            const supabase = makeSupabase();
            const result = await runMessagingAgent('שלח הודעה', supabase);
            expect(result.answer).toContain('לא הצלחתי להבין');
            expect(result.action).toBeNull();
        });
    });
});
