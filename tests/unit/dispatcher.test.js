'use strict';

const { REGISTRY, getEntry, getEntryForMode, dispatch } = require('../../agents/dispatcher');

// A mock `agents` bag: every run* function is a jest.fn returning a sentinel so
// we can assert which one each entry invokes and with what argument order.
function makeAgents() {
  const names = [
    'runTaskAgent', 'runReminderAgent', 'runMemoryAgent', 'runWeatherAgent',
    'runNewsAgent', 'runShoppingAgent', 'runNotesAgent', 'runStocksAgent',
    'runTranslationAgent', 'runMusicAgent', 'runSportsAgent', 'runMessagingAgent',
    'runDraftAgent', 'runCalendarAgent', 'runPromptAgent', 'runSettingsAgent',
    'runProjectAgent', 'runSecurityAgent', 'runManusAgent', 'runCodeErrorAgent',
    'runE2EAgent',
  ];
  const agents = {};
  for (const n of names) agents[n] = jest.fn((...args) => ({ fn: n, args }));
  return agents;
}

function makeCtx() {
  return {
    userMessage: 'שלום',
    supabase: { from: jest.fn() },
    repos: { tasks: {}, table: jest.fn() },
    useLocal: false,
    settings: { userName: 'נדב' },
    chatHistory: [{ role: 'user', text: 'hi' }],
    longTermMemories: ['[hobby] ריצה'],
    imageBase64: null,
    sendEmail: jest.fn(),
    chatId: 'session-1',
  };
}

describe('dispatcher REGISTRY', () => {
  test('every entry has a valid mode and an invoke function', () => {
    for (const [name, entry] of Object.entries(REGISTRY)) {
      expect(['sync', 'background']).toContain(entry.mode);
      expect(typeof entry.invoke).toBe('function');
      // background entries must carry a user-facing placeholder
      if (entry.mode === 'background') {
        expect(typeof entry.placeholder).toBe('string');
        expect(entry.placeholder.length).toBeGreaterThan(0);
      }
    }
  });

  test('memory entry declares a cacheBust key', () => {
    expect(REGISTRY.memory.cacheBust).toBe('memories');
  });
});

describe('getEntry', () => {
  test('returns the entry for a known agent', () => {
    expect(getEntry('task')).toBe(REGISTRY.task);
  });
  test('returns null for an unknown agent', () => {
    expect(getEntry('does-not-exist')).toBeNull();
  });
});

describe('getEntryForMode', () => {
  test('returns the sync entry unchanged by default', () => {
    expect(getEntryForMode('security')).toBe(REGISTRY.security);
    expect(getEntryForMode('security').mode).toBe('sync');
  });

  test('forceBackground swaps a backgroundPlaceholder entry to background mode', () => {
    const entry = getEntryForMode('security', { forceBackground: true });
    expect(entry.mode).toBe('background');
    expect(entry.placeholder).toBe(REGISTRY.security.backgroundPlaceholder);
  });

  test('forceBackground is a no-op for entries without a backgroundPlaceholder', () => {
    const entry = getEntryForMode('task', { forceBackground: true });
    expect(entry.mode).toBe('sync');
  });

  test('returns null for an unknown agent', () => {
    expect(getEntryForMode('nope', { forceBackground: true })).toBeNull();
  });
});

describe('dispatch', () => {
  test('throws for an unknown agent', async () => {
    await expect(dispatch('nope', makeCtx(), makeAgents()))
      .rejects.toThrow(/No registry entry/);
  });

  test('throws when called on a background-only agent', async () => {
    await expect(dispatch('manus', makeCtx(), makeAgents()))
      .rejects.toThrow(/not sync/);
  });

  test('task → runTaskAgent(userMessage, repos, useLocal, settings)', async () => {
    const ctx = makeCtx();
    const agents = makeAgents();
    await dispatch('task', ctx, agents);
    expect(agents.runTaskAgent).toHaveBeenCalledWith(ctx.userMessage, ctx.repos, ctx.useLocal, ctx.settings);
  });

  test('reminder → runReminderAgent(userMessage, supabase) only', async () => {
    const ctx = makeCtx();
    const agents = makeAgents();
    await dispatch('reminder', ctx, agents);
    expect(agents.runReminderAgent).toHaveBeenCalledWith(ctx.userMessage, ctx.supabase);
  });

  test('weather → runWeatherAgent(userMessage, settings)', async () => {
    const ctx = makeCtx();
    const agents = makeAgents();
    await dispatch('weather', ctx, agents);
    expect(agents.runWeatherAgent).toHaveBeenCalledWith(ctx.userMessage, ctx.settings);
  });

  test('draft → runDraftAgent(userMessage, chatHistory, longTermMemories, settings)', async () => {
    const ctx = makeCtx();
    const agents = makeAgents();
    await dispatch('draft', ctx, agents);
    expect(agents.runDraftAgent).toHaveBeenCalledWith(
      ctx.userMessage, ctx.chatHistory, ctx.longTermMemories, ctx.settings,
    );
  });

  test('stocks → runStocksAgent(userMessage) only', async () => {
    const ctx = makeCtx();
    const agents = makeAgents();
    await dispatch('stocks', ctx, agents);
    expect(agents.runStocksAgent).toHaveBeenCalledWith(ctx.userMessage);
  });

  test('security (sync) → runSecurityAgent(userMessage, useLocal, sendEmail)', async () => {
    const ctx = makeCtx();
    const agents = makeAgents();
    await dispatch('security', ctx, agents);
    expect(agents.runSecurityAgent).toHaveBeenCalledWith(ctx.userMessage, ctx.useLocal, ctx.sendEmail);
  });

  test('returns the agent result', async () => {
    const result = await dispatch('task', makeCtx(), makeAgents());
    expect(result).toEqual({ fn: 'runTaskAgent', args: expect.any(Array) });
  });
});
