'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn(), callGeminiVision: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({ isReady: jest.fn(() => false), embed: jest.fn() }));
jest.mock('../../services/styleLearner', () => ({ renderStyleHint: jest.fn(() => '') }));

const {
  detectFollowUp, analyzeUserStyle, filterRelevantMemories, buildSystemPrompt,
} = require('../../agents/chatAgent');

describe('detectFollowUp', () => {
  const history = [{ role: 'user', text: 'a' }, { role: 'jarvis', text: 'b' }];

  test('no history → never a follow-up', () => {
    expect(detectFollowUp('למה?', [])).toBe(false);
  });
  test('standalone question word → follow-up', () => {
    expect(detectFollowUp('למה?', history)).toBe(true);
    expect(detectFollowUp('המשך', history)).toBe(true);
  });
  test('short message containing a follow-up word → follow-up', () => {
    expect(detectFollowUp('אבל מה עם זה', history)).toBe(true);
  });
  test('very short message with enough history → follow-up', () => {
    expect(detectFollowUp('וזה', history)).toBe(true);
  });
  test('a long standalone statement is not a follow-up', () => {
    expect(detectFollowUp('אני רוצה לתכנן טיול משפחתי גדול לחו"ל בקיץ הקרוב', history)).toBe(false);
  });
});

describe('analyzeUserStyle', () => {
  test('casual marker → casual register', () => {
    expect(analyzeUserStyle('אחי מה קורה').register).toBe('casual');
  });
  test('short message → short length (and casual via length rule)', () => {
    expect(analyzeUserStyle('מה השעה').length).toBe('short');
  });
  test('long neutral message → long length, neutral register', () => {
    const msg = 'אני מעוניין לקבל סקירה מפורטת ומקצועית על כל האפשרויות השונות העומדות בפניי בנושא החשוב הזה כעת כדי שאוכל לקבל החלטה נבונה ומבוססת לטווח הארוך בהמשך הדרך';
    const { length, register } = analyzeUserStyle(msg);
    expect(length).toBe('long');
    expect(register).toBe('neutral');
  });
});

describe('filterRelevantMemories (token ranking)', () => {
  test('returns text unchanged when there are 8 or fewer lines', () => {
    const mem = Array.from({ length: 5 }, (_, i) => `- [x] memory ${i}`).join('\n');
    expect(filterRelevantMemories(mem, 'anything')).toBe(mem);
  });

  test('ranks the matching line to the top when over the threshold', () => {
    const lines = Array.from({ length: 12 }, (_, i) => `- [hobby] שורה לא רלוונטית ${i}`);
    lines.push('- [work] אני אוהב לתכנת בפייתון');
    const ranked = filterRelevantMemories(lines.join('\n'), 'ספר לי על תכנות בפייתון');
    expect(ranked.split('\n')[0]).toContain('פייתון');
  });

  test('passes through the empty-memories sentinel', () => {
    expect(filterRelevantMemories('אין עדיין זיכרונות שמורים.', 'x')).toBe('אין עדיין זיכרונות שמורים.');
  });
});

describe('buildSystemPrompt', () => {
  test('injects the user name and the selected personality description', () => {
    const p = buildSystemPrompt([], '', { userName: 'דני', personality: 'concise' }, null, 'שלום');
    expect(p).toContain('דני');
    expect(p).toContain('קצר, ישיר וממוקד'); // concise personality desc
  });

  test.each(['friendly', 'formal', 'concise', 'humorous', 'coach'])(
    'personality "%s" produces a non-empty prompt', (personality) => {
      const p = buildSystemPrompt([], '', { personality }, null, 'שלום');
      expect(p.length).toBeGreaterThan(100);
    });

  test('female gender switches to feminine instruction', () => {
    const p = buildSystemPrompt([], '', { gender: 'female' }, null, '');
    expect(p).toContain('עוזרת אישית');
  });

  test('voice mode adds the spoken-conversation block and skips the style hint', () => {
    const p = buildSystemPrompt([], '', { voiceMode: true }, null, 'שלום');
    expect(p).toContain('מצב שיחה קולית');
    expect(p).not.toContain('Style hint');
  });

  test('non-voice message adds a style hint mirroring the user', () => {
    const p = buildSystemPrompt([], '', {}, null, 'אחי מה קורה');
    expect(p).toContain('Style hint: mirror');
    expect(p).toContain('register=casual');
  });

  test('responseLength=short adds the brevity line outside voice mode', () => {
    const p = buildSystemPrompt([], '', { responseLength: 'short' }, null, 'שלום');
    expect(p).toContain('Keep answers short');
  });

  test('embeds long-term memories and recent history', () => {
    const history = [{ role: 'user', text: 'שאלה' }, { role: 'jarvis', text: 'תשובה' }];
    const p = buildSystemPrompt(history, '- [hobby] ריצה', {}, null, 'היי');
    expect(p).toContain('ריצה');
    expect(p).toContain('שאלה');
    expect(p).toContain('תשובה');
  });

  test('caps an oversized memory bank at 2000 chars', () => {
    const huge = '- [x] ' + 'מ'.repeat(5000);
    const p = buildSystemPrompt([], huge, {}, null, 'x');
    expect(p).toContain('(ועוד…)');
  });
});
