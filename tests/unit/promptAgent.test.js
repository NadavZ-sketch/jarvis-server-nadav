'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
}));

const { callGemma4 } = require('../../agents/models');
const { runPromptAgent, detectIntent, parseOptions } = require('../../agents/promptAgent');

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

// ── parseOptions ──────────────────────────────────────────────────────────
describe('parseOptions', () => {
    test('detects Claude target from "קלוד" or "claude"', () => {
        expect(parseOptions('צור פרומפט לקלוד עם XML').targetClaude).toBe(true);
        expect(parseOptions('צור פרומפט ל-Claude').targetClaude).toBe(true);
        expect(parseOptions('צור פרומפט לכתיבה').targetClaude).toBe(false);
    });
    test('detects few-shot from "דוגמ"', () => {
        expect(parseOptions('צור פרומפט עם דוגמאות').fewShot).toBe(true);
        expect(parseOptions('צור פרומפט few-shot').fewShot).toBe(true);
        expect(parseOptions('צור פרומפט').fewShot).toBe(false);
    });
    test('detects negative constraints from "אל ת" or "ללא"', () => {
        expect(parseOptions('פרומפט ללא הלוצינציות').constraints).toBe(true);
        expect(parseOptions('פרומפט — אל תמציא נתונים').constraints).toBe(true);
        expect(parseOptions('פרומפט רגיל ליצירת תוכן').constraints).toBe(false);
    });
    test('detects chaining from "שרשור" or "מורכב"', () => {
        expect(parseOptions('צור שרשור פרומפטים').chaining).toBe(true);
        expect(parseOptions('משימה מורכב מאוד').chaining).toBe(true);
        expect(parseOptions('פרומפט פשוט').chaining).toBe(false);
    });
    test('detects scratchpad from "חשוב שלב"', () => {
        expect(parseOptions('חשוב שלב אחר שלב').scratchpad).toBe(true);
        expect(parseOptions('CoT enabled').scratchpad).toBe(true);
        expect(parseOptions('פרומפט רגיל').scratchpad).toBe(false);
    });
});

// ── create ────────────────────────────────────────────────────────────────
describe('runPromptAgent — create', () => {
    test('calls LLM and returns formatted answer with action', async () => {
        callGemma4.mockResolvedValue(
            '<strategy>גישת מומחה</strategy><prompt>**תפקיד:** אתה כותב...</prompt>'
        );
        const result = await runPromptAgent('צור פרומפט לסיכום פגישות', mockSupabase(), false, {});
        expect(callGemma4).toHaveBeenCalledTimes(1);
        expect(result.answer).toContain('אתה כותב');
        expect(result.action).toEqual({ type: 'prompt_created' });
    });

    test('includes strategy in output when present', async () => {
        callGemma4.mockResolvedValue(
            '<strategy>השתמשתי בגישת CoT</strategy><prompt>הפרומפט כאן</prompt>'
        );
        const result = await runPromptAgent('צור פרומפט', mockSupabase(), false, {});
        expect(result.answer).toContain('אסטרטגיה');
        expect(result.answer).toContain('השתמשתי בגישת CoT');
    });

    test('shows applied techniques when detected', async () => {
        callGemma4.mockResolvedValue('<strategy>s</strategy><prompt>p</prompt>');
        const result = await runPromptAgent('צור פרומפט לקלוד עם דוגמאות', mockSupabase(), false, {});
        expect(result.answer).toContain('few-shot');
    });

    test('falls back gracefully when LLM returns no XML tags', async () => {
        callGemma4.mockResolvedValue('פרומפט ללא תגיות');
        const result = await runPromptAgent('צור פרומפט', mockSupabase(), false, {});
        expect(result.answer).toContain('פרומפט ללא תגיות');
    });

    test('uses useLocalModel from settings', async () => {
        callGemma4.mockResolvedValue('<strategy>s</strategy><prompt>p</prompt>');
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

// ── refine (Evaluate & Repair) ────────────────────────────────────────────
describe('runPromptAgent — refine', () => {
    test('returns holes-found + improved prompt', async () => {
        callGemma4.mockResolvedValue('🔍 **חורים שמצאתי:**\n- חסרה פרסונה\n\n✅ **הפרומפט לאחר Evaluate & Repair:**\n```\nגרסה משופרת\n```');
        const result = await runPromptAgent('שפר פרומפט: כתוב לי מייל', mockSupabase(), false, {});
        expect(result.answer).toContain('Evaluate & Repair');
    });

    test('uses XML structure hint when Claude target detected', async () => {
        callGemma4.mockResolvedValue('improved');
        await runPromptAgent('שפר פרומפט לקלוד: כתוב', mockSupabase(), false, {});
        const [messages] = callGemma4.mock.calls[0];
        const systemContent = messages[0].content;
        expect(systemContent).toContain('XML');
    });
});

// ── evaluate ──────────────────────────────────────────────────────────────
describe('runPromptAgent — evaluate', () => {
    test('returns scoring table', async () => {
        callGemma4.mockResolvedValue('📊 **הערכת הפרומפט:**\n| בהירות | 7/10 | טוב |');
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
                    { id: '2', title: 'פרומפט קוד',    category: 'coding',    created_at: '2026-05-02T10:00:00Z' },
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
