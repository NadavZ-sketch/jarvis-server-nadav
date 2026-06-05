'use strict';

const { createChatController } = require('../../controllers/chatController');
const { makeChain } = require('../helpers/supabaseMock');

function makeRes() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

describe('createChatController.getChatHistory', () => {
  test('returns messages oldest-first with the resolved chatId', async () => {
    const rows = [
      { role: 'assistant', text: 'שלום', created_at: '2026-06-05T10:01:00Z' },
      { role: 'user', text: 'היי', created_at: '2026-06-05T10:00:00Z' },
    ]; // controller fetches DESC then reverses → expect oldest first
    const chain = makeChain(rows);
    const supabase = { from: jest.fn(() => chain) };
    const ctrl = createChatController({ supabase });
    const res = makeRes();

    await ctrl.getChatHistory({ query: { chatId: 's1' } }, res);

    expect(supabase.from).toHaveBeenCalledWith('chat_history');
    expect(chain.eq).toHaveBeenCalledWith('chat_id', 's1');
    expect(res.body.chatId).toBe('s1');
    expect(res.body.messages[0].text).toBe('היי');
  });

  test('defaults chatId and caps the limit at 200', async () => {
    const chain = makeChain([]);
    const supabase = { from: jest.fn(() => chain) };
    const ctrl = createChatController({ supabase });
    const res = makeRes();

    await ctrl.getChatHistory({ query: { limit: '5000' } }, res);

    expect(res.body.chatId).toBe('default-session');
    expect(chain.limit).toHaveBeenCalledWith(200);
  });

  test('returns 500 with an empty list on db error', async () => {
    const supabase = { from: jest.fn(() => makeChain(null, { message: 'boom' })) };
    const ctrl = createChatController({ supabase });
    const res = makeRes();

    await ctrl.getChatHistory({ query: {} }, res);

    expect(res.statusCode).toBe(500);
    expect(res.body.messages).toEqual([]);
  });
});

describe('createChatController handler delegation', () => {
  test('askJarvis delegates to the configured handler', async () => {
    const askJarvisHandler = jest.fn((_req, res) => res.json({ answer: 'ok' }));
    const ctrl = createChatController({ supabase: {}, askJarvisHandler });
    const res = makeRes();
    await ctrl.askJarvis({}, res);
    expect(askJarvisHandler).toHaveBeenCalled();
    expect(res.body).toEqual({ answer: 'ok' });
  });

  test('askJarvis returns 500 when no handler is configured', async () => {
    const ctrl = createChatController({ supabase: {} });
    const res = makeRes();
    await ctrl.askJarvis({}, res);
    expect(res.statusCode).toBe(500);
  });

  test('streamJarvis returns 500 when no handler is configured', async () => {
    const ctrl = createChatController({ supabase: {} });
    const res = makeRes();
    await ctrl.streamJarvis({}, res);
    expect(res.statusCode).toBe(500);
    expect(res.body.error).toMatch(/Stream handler/);
  });
});
