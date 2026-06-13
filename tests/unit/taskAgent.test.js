'use strict';
jest.mock('../../agents/models', () => ({
    callGemma4: jest.fn(),
    callGeminiWithSearch: jest.fn(),
    callGeminiVision: jest.fn(),
    GEMINI_URL: 'https://mock.gemini.url',
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runTaskAgent } = require('../../agents/taskAgent');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => {
    jest.clearAllMocks();
});

describe('runTaskAgent', () => {
    test('add intent inserts task and confirms', async () => {
        callGemma4.mockResolvedValue('{"intent":"add","taskDetails":"buy milk","category":"general"}');
        const repos = makeRepos();
        const result = await runTaskAgent('הוסף משימה לקנות חלב', repos);
        expect(repos.tasks.addGraceful).toHaveBeenCalledWith(
            expect.objectContaining({ content: 'buy milk', category: 'general' })
        );
        expect(result.answer).toContain('הוספתי');
        expect(result.action).toEqual({ type: 'navigate', target: 'tasks', label: 'פתח משימות' });
    });

    test('list intent queries tasks and returns list', async () => {
        callGemma4.mockResolvedValue('{"intent":"list","taskDetails":""}');
        const repos = makeRepos({ tasks: [{ content: 'buy milk' }, { content: 'call mom' }] });
        const result = await runTaskAgent('מה המשימות שלי', repos);
        expect(repos.tasks.listAll).toHaveBeenCalled();
        expect(result.answer).toContain('buy milk');
    });

    test('list intent with empty tasks → no tasks message', async () => {
        callGemma4.mockResolvedValue('{"intent":"list","taskDetails":""}');
        const result = await runTaskAgent('מה המשימות שלי', makeRepos({ tasks: [] }));
        expect(result.answer).toContain('אין לך משימות');
    });

    test('JSON wrapped in markdown still parsed via lastIndexOf', async () => {
        callGemma4.mockResolvedValue('Here is the result: {"intent":"list","taskDetails":""} — done');
        const result = await runTaskAgent('רשימת משימות', makeRepos({ tasks: [{ content: 'task1' }] }));
        expect(result.answer).toContain('task1');
    });

    test('delete intent removes matching task', async () => {
        callGemma4.mockResolvedValue('{"intent":"delete","taskDetails":"buy milk"}');
        const repos = makeRepos({ tasks: [{ id: 9, content: 'buy milk' }] });
        const result = await runTaskAgent('מחק משימה לקנות חלב', repos);
        expect(repos.tasks.findByContent).toHaveBeenCalledWith('buy milk');
        expect(repos.tasks.deleteById).toHaveBeenCalledWith(9);
        expect(result.answer).toContain('מחקתי');
    });

    test('delete intent with no match → not found message', async () => {
        callGemma4.mockResolvedValue('{"intent":"delete","taskDetails":"buy milk"}');
        const result = await runTaskAgent('מחק משימה', makeRepos({ tasks: [] }));
        expect(result.answer).toContain('לא מצאתי');
    });

    test('complete intent removes and celebrates', async () => {
        callGemma4.mockResolvedValue('{"intent":"complete","taskDetails":"buy milk"}');
        const result = await runTaskAgent('סיימתי לקנות חלב', makeRepos({ tasks: [{ id: 1, content: 'buy milk' }] }));
        expect(result.answer).toContain('כל הכבוד');
    });

    test('recategorize intent updates category of matching task', async () => {
        callGemma4.mockResolvedValue('{"intent":"recategorize","taskDetails":"קניות","category":"financial"}');
        const repos = makeRepos({ tasks: [{ id: 7, content: 'קניות לשבת' }] });
        const result = await runTaskAgent('תעביר את קניות לפיננסי', repos);
        expect(repos.tasks.setCategory).toHaveBeenCalledWith(7, 'financial');
        expect(result.answer).toContain('פיננסי');
    });

    test('recategorize with invalid category → asks for clarification', async () => {
        callGemma4.mockResolvedValue('{"intent":"recategorize","taskDetails":"קניות","category":"banana"}');
        const repos = makeRepos({ tasks: [{ id: 7, content: 'קניות' }] });
        const result = await runTaskAgent('תעביר את קניות לבננה', repos);
        expect(repos.tasks.setCategory).not.toHaveBeenCalled();
        expect(result.answer).toContain('קטגוריה');
    });

    test('recategorize with no matching task → not found message', async () => {
        callGemma4.mockResolvedValue('{"intent":"recategorize","taskDetails":"לא קיים","category":"work"}');
        const result = await runTaskAgent('תעביר את לא קיים לעבודה', makeRepos({ tasks: [] }));
        expect(result.answer).toContain('לא מצאתי');
    });

    test('LLM returns no JSON → error message', async () => {
        callGemma4.mockResolvedValue('Sorry, I cannot help with that.');
        const result = await runTaskAgent('בלה בלה', makeRepos());
        expect(result.answer).toContain('לא הצלחתי לעבד את הבקשה');
    });

    test('callGemma4 throws → error message', async () => {
        callGemma4.mockRejectedValue(new Error('Network error'));
        const result = await runTaskAgent('הוסף משימה', makeRepos());
        expect(result.answer).toContain('הייתה בעיה בעיבוד המשימה');
    });
});

describe('runTaskAgent — recurring tasks', () => {
    test('add with recurrence stores recurrence and notes it', async () => {
        callGemma4.mockResolvedValue('{"intent":"add","taskDetails":"שתיית מים","category":"personal","recurrence":"daily"}');
        const repos = makeRepos();
        const result = await runTaskAgent('הוסף משימה לשתות מים כל יום', repos);
        expect(repos.tasks.addGraceful).toHaveBeenCalledWith(
            expect.objectContaining({ content: 'שתיית מים', recurrence: 'daily' })
        );
        expect(result.answer).toContain('🔁');
    });

    test('recurrence falls back to keyword detection when LLM omits it', async () => {
        callGemma4.mockResolvedValue('{"intent":"add","taskDetails":"דוח שבועי","category":"work","recurrence":null}');
        const repos = makeRepos();
        await runTaskAgent('הוסף משימה דוח כל שבוע', repos);
        expect(repos.tasks.addGraceful).toHaveBeenCalledWith(
            expect.objectContaining({ recurrence: 'weekly' })
        );
    });

    test('completing a recurring task spawns the next occurrence', async () => {
        callGemma4.mockResolvedValue('{"intent":"complete","taskDetails":"שתיית מים"}');
        const repos = makeRepos({ tasks: [
            { id: 'r1', content: 'שתיית מים', category: 'personal', priority: 'medium', recurrence: 'daily', due_date: '2026-06-06' },
        ] });
        const result = await runTaskAgent('סיימתי לשתות מים', repos);
        expect(repos.tasks.complete).toHaveBeenCalledWith('r1');
        expect(repos.tasks.insertNext).toHaveBeenCalledWith(
            expect.objectContaining({ content: 'שתיית מים', recurrence: 'daily', due_date: '2026-06-07' })
        );
        expect(result.answer).toContain('🔁');
    });

    test('completing a non-recurring task does not insert anything', async () => {
        callGemma4.mockResolvedValue('{"intent":"complete","taskDetails":"buy milk"}');
        const repos = makeRepos({ tasks: [
            { id: 't1', content: 'buy milk', category: 'general', priority: 'low', recurrence: null, due_date: null },
        ] });
        const result = await runTaskAgent('סיימתי לקנות חלב', repos);
        expect(repos.tasks.insertNext).not.toHaveBeenCalled();
        expect(result.answer).toContain('כל הכבוד');
    });
});
