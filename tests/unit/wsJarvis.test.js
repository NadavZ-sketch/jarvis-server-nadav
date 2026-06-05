'use strict';

const { EventEmitter } = require('events');
const { createWsHandler } = require('../../routes/wsJarvis');

// A fake ws connection: an EventEmitter that records the frames the handler
// sends. readyState 1 === OPEN (so `send` is allowed).
function makeWs() {
  const ws = new EventEmitter();
  ws.readyState = 1;
  ws.sent = [];
  ws.send = jest.fn((s) => ws.sent.push(JSON.parse(s)));
  ws.close = jest.fn(() => { ws.readyState = 3; });
  return ws;
}

function makeDeps(overrides = {}) {
  return {
    classifyIntent: jest.fn().mockResolvedValue('chat'),
    contextResolver: { shouldResolve: jest.fn().mockReturnValue(false), resolveReferences: jest.fn() },
    loadChatHistory: jest.fn().mockResolvedValue([]),
    fetchLongTermMemories: jest.fn().mockResolvedValue([]),
    conversationSummary: {
      getSummary: jest.fn().mockResolvedValue(''),
      updateSummaryIfNeeded: jest.fn().mockResolvedValue(undefined),
    },
    buildSystemPrompt: jest.fn().mockReturnValue('system'),
    callGemma4Stream: jest.fn(async (_msgs, _local, onChunk) => { onChunk('שלום '); onChunk('עולם'); }),
    runChatAgent: jest.fn().mockResolvedValue({ answer: 'chat answer' }),
    runWeatherAgent: jest.fn().mockResolvedValue({ answer: 'גשם היום' }),
    runNewsAgent: jest.fn().mockResolvedValue({ answer: 'חדשות' }),
    runStocksAgent: jest.fn().mockResolvedValue({ answer: 'מניות' }),
    runTranslationAgent: jest.fn().mockResolvedValue({ answer: 'translation' }),
    saveChatMessage: jest.fn().mockResolvedValue(undefined),
    cacheInvalidate: jest.fn(),
    autoExtractMemory: jest.fn().mockResolvedValue(undefined),
    generateSpeech: jest.fn().mockResolvedValue('base64audio'),
    supabase: {},
    ...overrides,
  };
}

const emit = (ws, obj) => ws.emit('message', Buffer.from(JSON.stringify(obj)));

async function waitFor(ws, type, tries = 60) {
  for (let i = 0; i < tries; i++) {
    if (ws.sent.some(f => f.type === type)) return;
    await new Promise(r => setImmediate(r));
  }
  throw new Error(`timed out waiting for "${type}"; got: ${JSON.stringify(ws.sent)}`);
}

describe('ws handler — handshake & control frames', () => {
  test('hello → ack with a generated chatId', async () => {
    const ws = makeWs();
    createWsHandler(makeDeps())(ws);
    emit(ws, { type: 'hello', settings: { useLocalModel: true } });
    await waitFor(ws, 'ack');
    expect(ws.sent[0].chatId).toBeTruthy();
  });

  test('invalid JSON is ignored without throwing', async () => {
    const ws = makeWs();
    createWsHandler(makeDeps())(ws);
    expect(() => ws.emit('message', Buffer.from('not json'))).not.toThrow();
    await new Promise(r => setImmediate(r));
    expect(ws.sent).toHaveLength(0);
  });

  test('bye closes the socket', async () => {
    const ws = makeWs();
    createWsHandler(makeDeps())(ws);
    emit(ws, { type: 'bye' });
    await new Promise(r => setImmediate(r));
    expect(ws.close).toHaveBeenCalled();
  });

  test('barge_in with no active generation is a no-op', async () => {
    const ws = makeWs();
    createWsHandler(makeDeps())(ws);
    emit(ws, { type: 'barge_in' });
    await new Promise(r => setImmediate(r));
    expect(ws.sent).toHaveLength(0);
  });
});

describe('ws handler — user_text validation', () => {
  test('empty text produces no frames', async () => {
    const ws = makeWs();
    createWsHandler(makeDeps())(ws);
    emit(ws, { type: 'hello' });
    await waitFor(ws, 'ack');
    ws.sent.length = 0;
    emit(ws, { type: 'user_text', text: '   ' });
    await new Promise(r => setImmediate(r));
    expect(ws.sent).toHaveLength(0);
  });

  test('over-long text returns an error frame', async () => {
    const ws = makeWs();
    createWsHandler(makeDeps())(ws);
    emit(ws, { type: 'hello' });
    await waitFor(ws, 'ack');
    emit(ws, { type: 'user_text', text: 'x'.repeat(5001) });
    await waitFor(ws, 'error');
    expect(ws.sent.find(f => f.type === 'error').message).toMatch(/ארוכה/);
  });
});

describe('ws handler — chat streaming path', () => {
  test('streams chunks then assistant_done with audio, and persists both turns', async () => {
    const deps = makeDeps({ classifyIntent: jest.fn().mockResolvedValue('chat') });
    const ws = makeWs();
    createWsHandler(deps)(ws);
    emit(ws, { type: 'hello', chatId: 'c1' });
    await waitFor(ws, 'ack');
    emit(ws, { type: 'user_text', text: 'מה שלומך?' });
    await waitFor(ws, 'assistant_done');

    const chunks = ws.sent.filter(f => f.type === 'assistant_chunk').map(f => f.text);
    expect(chunks.join('')).toBe('שלום עולם');
    const done = ws.sent.find(f => f.type === 'assistant_done');
    expect(done.audio).toBe('base64audio');
    expect(deps.saveChatMessage).toHaveBeenCalledWith('user', 'מה שלומך?', 'c1');
    expect(deps.saveChatMessage).toHaveBeenCalledWith('jarvis', 'שלום עולם', 'c1');
    expect(deps.cacheInvalidate).toHaveBeenCalledWith('chatHistory:c1');
  });
});

describe('ws handler — non-chat agent path', () => {
  test('weather intent routes to runWeatherAgent and emits a single chunk', async () => {
    const deps = makeDeps({ classifyIntent: jest.fn().mockResolvedValue('weather') });
    const ws = makeWs();
    createWsHandler(deps)(ws);
    emit(ws, { type: 'hello', chatId: 'c2' });
    await waitFor(ws, 'ack');
    emit(ws, { type: 'user_text', text: 'מה מזג האוויר?' });
    await waitFor(ws, 'assistant_done');

    expect(deps.runWeatherAgent).toHaveBeenCalledWith('מה מזג האוויר?');
    expect(deps.callGemma4Stream).not.toHaveBeenCalled();
    expect(ws.sent.find(f => f.type === 'assistant_done').text).toBe('גשם היום');
  });

  test('skips TTS when settings.ttsEnabled is false', async () => {
    const deps = makeDeps({ classifyIntent: jest.fn().mockResolvedValue('weather') });
    const ws = makeWs();
    createWsHandler(deps)(ws);
    emit(ws, { type: 'hello', chatId: 'c3', settings: { ttsEnabled: false } });
    await waitFor(ws, 'ack');
    emit(ws, { type: 'user_text', text: 'מזג אוויר' });
    await waitFor(ws, 'assistant_done');
    expect(deps.generateSpeech).not.toHaveBeenCalled();
    expect(ws.sent.find(f => f.type === 'assistant_done').audio).toBeNull();
  });
});

describe('ws handler — error handling', () => {
  test('an agent failure emits an error frame', async () => {
    const deps = makeDeps({
      classifyIntent: jest.fn().mockResolvedValue('weather'),
      runWeatherAgent: jest.fn().mockRejectedValue(new Error('upstream down')),
    });
    const ws = makeWs();
    createWsHandler(deps)(ws);
    emit(ws, { type: 'hello', chatId: 'c4' });
    await waitFor(ws, 'ack');
    emit(ws, { type: 'user_text', text: 'מזג אוויר' });
    await waitFor(ws, 'error');
    expect(ws.sent.find(f => f.type === 'error').message).toMatch(/שגיאת מערכת/);
  });
});
