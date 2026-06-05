'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runSettingsAgent } = require('../../agents/settingsAgent');

beforeEach(() => jest.clearAllMocks());

describe('runSettingsAgent — personality changes', () => {
  test.each([
    ['תהיה יותר ידידותי', 'friendly'],
    ['דבר בצורה רשמית', 'formal'],
    ['ענה קצר ולעניין', 'concise'],
    ['תהיה מצחיק יותר', 'humorous'],
  ])('"%s" → personality %s', async (msg, expected) => {
    const res = await runSettingsAgent(msg, null, false, {});
    expect(res.action.type).toBe('settings_update');
    expect(res.action.data.personality).toBe(expected);
    expect(callGemma4).not.toHaveBeenCalled();
  });
});

describe('runSettingsAgent — voice speed (relative + clamped)', () => {
  test('slower decrements by 0.15 from current', async () => {
    const res = await runSettingsAgent('דבר יותר לאט', null, false, { ttsSpeed: 0.7 });
    expect(res.action.data.ttsSpeed).toBeCloseTo(0.55, 5);
  });

  test('slower clamps at the 0.3 floor', async () => {
    const res = await runSettingsAgent('האט בבקשה', null, false, { ttsSpeed: 0.35 });
    expect(res.action.data.ttsSpeed).toBe(0.3);
  });

  test('faster increments by 0.15 and clamps at the 1.0 ceiling', async () => {
    const res = await runSettingsAgent('דבר יותר מהר', null, false, { ttsSpeed: 0.95 });
    expect(res.action.data.ttsSpeed).toBe(1.0);
  });

  test('defaults current speed to 0.7 when unset', async () => {
    const res = await runSettingsAgent('האץ', null, false, {});
    expect(res.action.data.ttsSpeed).toBeCloseTo(0.85, 5);
  });
});

describe('runSettingsAgent — voice on/off and response length', () => {
  test('turn voice off', async () => {
    const res = await runSettingsAgent('בטל קול', null, false, {});
    expect(res.action.data.voiceEnabled).toBe(false);
  });
  test('turn voice on', async () => {
    const res = await runSettingsAgent('הפעל קול', null, false, {});
    expect(res.action.data.voiceEnabled).toBe(true);
  });
  test('short responses', async () => {
    const res = await runSettingsAgent('תן תשובות קצרות', null, false, {});
    expect(res.action.data.responseLength).toBe('short');
  });
  test('long responses', async () => {
    const res = await runSettingsAgent('ענה ארוך ומפורט יותר', null, false, {});
    expect(res.action.data.responseLength).toBe('long');
  });
});

describe('runSettingsAgent — name changes', () => {
  test('changes the user name via "קרא לי"', async () => {
    const res = await runSettingsAgent('קרא לי דני', null, false, {});
    expect(res.action.data.userName).toBe('דני');
  });

  test('changes the assistant name via "קרא לעצמך"', async () => {
    const res = await runSettingsAgent('קרא לעצמך אלפרד', null, false, {});
    expect(res.action.data.assistantName).toBe('אלפרד');
  });
});

describe('runSettingsAgent — show current settings', () => {
  test('summarises settings without an action or an LLM call', async () => {
    const res = await runSettingsAgent('מה ההגדרות שלי?', null, false, {
      userName: 'נדב', personality: 'formal', voiceEnabled: false, responseLength: 'short',
    });
    expect(res.action).toBeUndefined();
    expect(res.answer).toContain('נדב');
    expect(res.answer).toContain('רשמי');
    expect(res.answer).toContain('כבוי');
    expect(callGemma4).not.toHaveBeenCalled();
  });
});

describe('runSettingsAgent — LLM fallback', () => {
  test('falls back to callGemma4 when no intent is parsed', async () => {
    callGemma4.mockResolvedValue('לא הבנתי, מה תרצה לשנות?');
    const res = await runSettingsAgent('בלה בלה משהו לא ברור', null, true, {});
    expect(callGemma4).toHaveBeenCalledTimes(1);
    expect(res.answer).toBe('לא הבנתי, מה תרצה לשנות?');
    expect(res.action).toBeUndefined();
  });
});
