'use strict';

jest.mock('../../agents/models', () => ({
  callGemma4: jest.fn(), callGeminiWithSearch: jest.fn(), callGeminiVision: jest.fn(),
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));
jest.mock('../../services/pineconeMemory', () => ({
  isReady: jest.fn(() => false), searchMemories: jest.fn(), upsertMemory: jest.fn(), findSimilarMemory: jest.fn(),
}));

const { classifyCategory, CATEGORY_META } = require('../../agents/taskAgent');

describe('classifyCategory', () => {
  test.each([
    ['פגישה עם הלקוח במשרד', 'work'],
    ['לקבוע תור לרופא שיניים', 'personal'],
    ['לשלם את חשבון החשמל', 'financial'],
    ['לתקן באג באפליקציה ולעשות deploy', 'project'],
  ])('"%s" → %s', (text, expected) => {
    expect(classifyCategory(text)).toBe(expected);
  });

  test('unmatched text falls back to general', () => {
    expect(classifyCategory('משהו אקראי לגמרי בלי מילות מפתח')).toBe('general');
  });

  test('empty/falsy input → general', () => {
    expect(classifyCategory('')).toBe('general');
    expect(classifyCategory(null)).toBe('general');
  });

  test('first matching category wins (work checked before personal)', () => {
    // contains both "פגישה" (work) and "משפחה" (personal); work is iterated first
    expect(classifyCategory('פגישה משפחתית')).toBe('work');
  });
});

describe('CATEGORY_META', () => {
  test('every classifiable category has a label and emoji', () => {
    for (const key of ['work', 'personal', 'financial', 'project', 'general']) {
      expect(CATEGORY_META[key]).toEqual(
        expect.objectContaining({ label: expect.any(String), emoji: expect.any(String) }),
      );
    }
  });
});
