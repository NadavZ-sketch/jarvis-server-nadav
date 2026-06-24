'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
}));

const { callGemma4 } = require('../../agents/models');
const { runPromptAgent, detectIntent } = require('../../agents/promptAgent');

function makeRepos({ listData = [], addError = null } = {}) {
    return {
        userPrompts: {
            listRecent: jest.fn().mockResolvedValue(listData),
            add: jest.fn().mockResolvedValue({ error: addError }),
        },
    };
}

beforeEach(() => {
    jest.clearAllMocks();
});

// ── detectIntent ──────────────────────────────────────────────────────────
describe('detectIntent', () => {
    test('create — default for use-case description', () => {
        expect(detectIntent('פרומפט לכתיבת מיילים מכירתיים')).toBe('create');
        expect(detectIntent('צור פרומפט לסיכום ישיבות')).toBe('create');
    });

    test('refine — when user asks to improve a prompt', () => {
        expect(detectIntent('שפר פרומפט: כתוב לי מייל')).toBe('refine');
        expect(detectIntent('שדרג פרומפט זה')).toBe('refine');
    });

    test('evaluate — when user asks to score/analyze a prompt', () => {
        expect(detectIntent('הערך פרומפט: אתה עוזר כתיבה')).toBe('evaluate');
        expect(detectIntent('נתח פרומפט')).toBe('evaluate');
    });

    test('save — when user wants to persist a prompt', () => {
        expect(detectIntent('שמור פרומפט: אתה מומחה שיווק')).toBe('save');
    });

    test('list — when user wants their saved prompts', () => {
        expect(detectIntent('הצג פרומפטים שמורים')).toBe('list');
        expect(detectIntent('רשימת פרומפטים')).toBe('list');
        expect(detectIntent('הפרומפטים שלי')).toBe('list');
    });
});

// ── create ────────────────────────────────────────────────────────────────
describe('runPromptAgent — create', () => {
    test('calls LLM and returns answer', async () => {
        callGemma4.mockResolvedValue('📋 **פרומפט סיכום פגישות**\n```\nאתה...\n```');
        const result = await runPromptAgent('צור פרומפט לסיכום פגישות', makeRepos(), false, {});
        expect(callGemma4).toHaveBeenCalledTimes(1);
        expect(result.answer).toContain('פרומפט');
        expect(result.action).toEqual({ type: 'prompt_created' });
    });

    test('uses useLocalModel from settings', async () => {
        callGemma4.mockResolvedValue('פרומפט');
        await runPromptAgent('צור פרומפט', makeRepos(), false, { useLocalModel: true });
        const [, useLocal] = callGemma4.mock.calls[0];
        expect(useLocal).toBe(true);
    });

    test('LLM failure returns Hebrew error', async () => {
        callGemma4.mockRejectedValue(new Error('timeout'));
        const result = await runPromptAgent('צור פרומפט', makeRepos(), false, {});
        expect(result.answer).toContain('סליחה');
    });
});

// ── refine ────────────────────────────────────────────────────────────────
describe('runPromptAgent — refine', () => {
    test('returns improved prompt', async () => {
        callGemma4.mockResolvedValue('✅ **הפרומפט המשופר:**\n```\nגרסה משופרת\n```');
        const result = await runPromptAgent('שפר פרומפט: כתוב לי מייל', makeRepos(), false, {});
        expect(result.answer).toContain('משופר');
    });
});

// ── evaluate ──────────────────────────────────────────────────────────────
describe('runPromptAgent — evaluate', () => {
    test('returns scoring table', async () => {
        callGemma4.mockResolvedValue('📊 **הערכת הפרומפט:**\n| בהירות | 7/10 |');
        const result = await runPromptAgent('הערך פרומפט: כתוב מייל', makeRepos(), false, {});
        expect(result.answer).toContain('הערכת');
    });
});

// ── save ──────────────────────────────────────────────────────────────────
describe('runPromptAgent — save', () => {
    test('extracts title via LLM and saves via repo', async () => {
        callGemma4.mockResolvedValue('{"title": "פרומפט שיווקי", "prompt": "אתה מומחה שיווק", "category": "marketing"}');
        const repos = makeRepos();
        const result = await runPromptAgent('שמור פרומפט: אתה מומחה שיווק', repos, false, {});
        expect(repos.userPrompts.add).toHaveBeenCalledWith(
            expect.objectContaining({ title: 'פרומפט שיווקי' }),
        );
        expect(result.answer).toContain('שמרתי');
    });

    test('gracefully handles DB failure', async () => {
        callGemma4.mockResolvedValue('{"title": "כותרת", "prompt": "פרומפט", "category": "general"}');
        const repos = makeRepos({ addError: new Error('relation does not exist') });
        const result = await runPromptAgent('שמור פרומפט: פרומפט', repos, false, {});
        expect(result.answer).toContain('פרומפט');
    });
});

// ── list ──────────────────────────────────────────────────────────────────
describe('runPromptAgent — list', () => {
    test('shows saved prompts when data exists', async () => {
        const repos = makeRepos({
            listData: [
                { id: '1', title: 'פרומפט מכירות', category: 'marketing', created_at: '2026-05-01T10:00:00Z' },
                { id: '2', title: 'פרומפט קוד', category: 'coding', created_at: '2026-05-02T10:00:00Z' },
            ],
        });
        const result = await runPromptAgent('הצג פרומפטים שמורים', repos, false, {});
        expect(result.answer).toContain('פרומפט מכירות');
        expect(result.answer).toContain('פרומפט קוד');
    });

    test('empty list returns helpful message', async () => {
        const repos = makeRepos({ listData: [] });
        const result = await runPromptAgent('הפרומפטים שלי', repos, false, {});
        expect(result.answer).toContain('צור פרומפט');
    });

    test('DB error returns error message', async () => {
        const repos = {
            userPrompts: { listRecent: jest.fn().mockRejectedValue(new Error('DB error')) },
        };
        const result = await runPromptAgent('רשימת פרומפטים', repos, false, {});
        expect(result.answer).toContain('לא הצלחתי');
    });
});
