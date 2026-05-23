'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
}));

const { callGemma4 } = require('../../agents/models');
const { runPromptAgent, detectIntent } = require('../../agents/promptAgent');

const mockSupabase = () => ({
    from: jest.fn().mockReturnThis(),
    insert: jest.fn().mockResolvedValue({ data: [{ id: '1' }], error: null }),
    select: jest.fn().mockReturnThis(),
    order: jest.fn().mockReturnThis(),
    limit: jest.fn().mockResolvedValue({ data: [], error: null }),
});

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
        const result = await runPromptAgent('צור פרומפט לסיכום פגישות', mockSupabase(), false, {});
        expect(callGemma4).toHaveBeenCalledTimes(1);
        expect(result.answer).toContain('פרומפט');
        expect(result.action).toEqual({ type: 'prompt_created' });
    });

    test('uses useLocalModel from settings', async () => {
        callGemma4.mockResolvedValue('פרומפט');
        await runPromptAgent('צור פרומפט', mockSupabase(), false, { useLocalModel: true });
        const [, useLocal] = callGemma4.mock.calls[0];
        expect(useLocal).toBe(true);
    });

    test('LLM failure returns Hebrew error', async () => {
        callGemma4.mockRejectedValue(new Error('timeout'));
        const result = await runPromptAgent('צור פרומפט', mockSupabase(), false, {});
        expect(result.answer).toContain('סליחה');
    });
});

// ── refine ────────────────────────────────────────────────────────────────
describe('runPromptAgent — refine', () => {
    test('returns improved prompt', async () => {
        callGemma4.mockResolvedValue('✅ **הפרומפט המשופר:**\n```\nגרסה משופרת\n```');
        const result = await runPromptAgent('שפר פרומפט: כתוב לי מייל', mockSupabase(), false, {});
        expect(result.answer).toContain('משופר');
    });
});

// ── evaluate ──────────────────────────────────────────────────────────────
describe('runPromptAgent — evaluate', () => {
    test('returns scoring table', async () => {
        callGemma4.mockResolvedValue('📊 **הערכת הפרומפט:**\n| בהירות | 7/10 |');
        const result = await runPromptAgent('הערך פרומפט: כתוב מייל', mockSupabase(), false, {});
        expect(result.answer).toContain('הערכת');
    });
});

// ── save ──────────────────────────────────────────────────────────────────
describe('runPromptAgent — save', () => {
    test('extracts title via LLM and saves to Supabase', async () => {
        callGemma4.mockResolvedValue('{"title": "פרומפט שיווקי", "prompt": "אתה מומחה שיווק", "category": "marketing"}');
        const supabase = mockSupabase();
        const result = await runPromptAgent('שמור פרומפט: אתה מומחה שיווק', supabase, false, {});
        expect(supabase.from).toHaveBeenCalledWith('user_prompts');
        expect(result.answer).toContain('שמרתי');
    });

    test('gracefully handles DB failure', async () => {
        callGemma4.mockResolvedValue('{"title": "כותרת", "prompt": "פרומפט", "category": "general"}');
        const supabase = {
            from: jest.fn().mockReturnThis(),
            insert: jest.fn().mockRejectedValue(new Error('relation does not exist')),
        };
        const result = await runPromptAgent('שמור פרומפט: פרומפט', supabase, false, {});
        expect(result.answer).toContain('פרומפט');
    });
});

// ── list ──────────────────────────────────────────────────────────────────
describe('runPromptAgent — list', () => {
    test('shows saved prompts when data exists', async () => {
        const supabase = {
            from: jest.fn().mockReturnThis(),
            select: jest.fn().mockReturnThis(),
            order: jest.fn().mockReturnThis(),
            limit: jest.fn().mockResolvedValue({
                data: [
                    { id: '1', title: 'פרומפט מכירות', category: 'marketing', created_at: '2026-05-01T10:00:00Z' },
                    { id: '2', title: 'פרומפט קוד', category: 'coding', created_at: '2026-05-02T10:00:00Z' },
                ],
                error: null,
            }),
        };
        const result = await runPromptAgent('הצג פרומפטים שמורים', supabase, false, {});
        expect(result.answer).toContain('פרומפט מכירות');
        expect(result.answer).toContain('פרומפט קוד');
    });

    test('empty list returns helpful message', async () => {
        const supabase = {
            from: jest.fn().mockReturnThis(),
            select: jest.fn().mockReturnThis(),
            order: jest.fn().mockReturnThis(),
            limit: jest.fn().mockResolvedValue({ data: [], error: null }),
        };
        const result = await runPromptAgent('הפרומפטים שלי', supabase, false, {});
        expect(result.answer).toContain('צור פרומפט');
    });

    test('DB error returns error message', async () => {
        const supabase = {
            from: jest.fn().mockReturnThis(),
            select: jest.fn().mockReturnThis(),
            order: jest.fn().mockReturnThis(),
            limit: jest.fn().mockResolvedValue({ data: null, error: new Error('DB error') }),
        };
        const result = await runPromptAgent('רשימת פרומפטים', supabase, false, {});
        expect(result.answer).toContain('לא הצלחתי');
    });
});
