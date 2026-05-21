'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../agents/taskAgent', () => ({ runTaskAgent: jest.fn() }));
jest.mock('../../agents/reminderAgent', () => ({ runReminderAgent: jest.fn() }));
jest.mock('../../agents/memoryAgent', () => ({ runMemoryAgent: jest.fn() }));
jest.mock('../../agents/weatherAgent', () => ({ runWeatherAgent: jest.fn() }));
jest.mock('../../agents/newsAgent', () => ({ runNewsAgent: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runTaskAgent } = require('../../agents/taskAgent');
const { runReminderAgent } = require('../../agents/reminderAgent');
const { runWeatherAgent } = require('../../agents/weatherAgent');
const { runNewsAgent } = require('../../agents/newsAgent');
const { runOrchestratorAgent } = require('../../agents/orchestratorAgent');

const supabase = {};
const multiHintMsg = 'הוסף משימה לפגישה וגם תזכיר לי שעה לפני';

function multiIntentJSON(tasks) {
    return JSON.stringify({ isMultiIntent: true, tasks });
}

beforeEach(() => jest.clearAllMocks());

describe('runOrchestratorAgent — fast path gating', () => {
    test('returns null without calling the LLM when message has no multi-intent hint', async () => {
        const result = await runOrchestratorAgent('מה השעה עכשיו', supabase, false, {});
        expect(result).toBeNull();
        expect(callGemma4).not.toHaveBeenCalled();
    });

    test('hint present but LLM says single intent → returns null', async () => {
        callGemma4.mockResolvedValue('{"isMultiIntent": false, "tasks": []}');
        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result).toBeNull();
    });

    test('hint present but fewer than 2 sub-tasks → returns null', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([{ intent: 'task', message: 'הוסף פגישה' }]));
        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result).toBeNull();
    });
});

describe('runOrchestratorAgent — detectMultiIntent error handling', () => {
    test('LLM returns non-JSON text → returns null', async () => {
        callGemma4.mockResolvedValue('I cannot parse this request into intents.');
        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result).toBeNull();
    });

    test('LLM returns malformed JSON → returns null (no throw)', async () => {
        callGemma4.mockResolvedValue('{"isMultiIntent": true, "tasks": [oops not json]}');
        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result).toBeNull();
    });

    test('LLM throws → returns null (swallowed)', async () => {
        callGemma4.mockRejectedValue(new Error('LLM unavailable'));
        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result).toBeNull();
    });
});

describe('runOrchestratorAgent — dispatch & aggregation', () => {
    test('combines answers from multiple sub-agents with separator', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([
            { intent: 'task', message: 'הוסף פגישה' },
            { intent: 'reminder', message: 'תזכיר לי שעה לפני' },
        ]));
        runTaskAgent.mockResolvedValue({ answer: 'הוספתי משימה' });
        runReminderAgent.mockResolvedValue({ answer: 'אזכיר לך' });

        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result.answer).toContain('הוספתי משימה');
        expect(result.answer).toContain('אזכיר לך');
        expect(result.answer).toContain('---');
    });

    test('extracts JSON embedded in surrounding prose', async () => {
        callGemma4.mockResolvedValue(
            'Sure! ' + multiIntentJSON([
                { intent: 'weather', message: 'מזג אוויר' },
                { intent: 'news', message: 'חדשות' },
            ]) + ' hope that helps'
        );
        runWeatherAgent.mockResolvedValue({ answer: 'שמשי היום' });
        runNewsAgent.mockResolvedValue({ answer: 'מבזק חדשות' });

        const result = await runOrchestratorAgent('מה מזג האוויר וגם מה חדשות', supabase, false, {});
        expect(result.answer).toContain('שמשי היום');
        expect(result.answer).toContain('מבזק חדשות');
    });

    test('a sub-agent that throws is skipped, others still returned', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([
            { intent: 'task', message: 'הוסף פגישה' },
            { intent: 'reminder', message: 'תזכיר לי' },
        ]));
        runTaskAgent.mockResolvedValue({ answer: 'הוספתי משימה' });
        runReminderAgent.mockRejectedValue(new Error('DB down'));

        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result.answer).toBe('הוספתי משימה');
        expect(result.answer).not.toContain('---');
    });

    test('all sub-agents fail → returns null', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([
            { intent: 'task', message: 'x' },
            { intent: 'reminder', message: 'y' },
        ]));
        runTaskAgent.mockResolvedValue(null);
        runReminderAgent.mockResolvedValue(null);

        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result).toBeNull();
    });

    test('unknown intent dispatches to null and is skipped', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([
            { intent: 'task', message: 'הוסף פגישה' },
            { intent: 'nonexistent_intent', message: 'whatever' },
        ]));
        runTaskAgent.mockResolvedValue({ answer: 'הוספתי משימה' });

        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result.answer).toBe('הוספתי משימה');
    });
});

describe('runOrchestratorAgent — action aggregation', () => {
    test('single action is returned as object', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([
            { intent: 'task', message: 'הוסף פגישה' },
            { intent: 'reminder', message: 'תזכיר לי' },
        ]));
        runTaskAgent.mockResolvedValue({ answer: 'a', action: { type: 'task_added' } });
        runReminderAgent.mockResolvedValue({ answer: 'b' });

        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result.action).toEqual({ type: 'task_added' });
    });

    test('multiple actions are returned as array', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([
            { intent: 'task', message: 'הוסף פגישה' },
            { intent: 'reminder', message: 'תזכיר לי' },
        ]));
        runTaskAgent.mockResolvedValue({ answer: 'a', action: { type: 'task_added' } });
        runReminderAgent.mockResolvedValue({ answer: 'b', action: { type: 'reminder_set' } });

        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(Array.isArray(result.action)).toBe(true);
        expect(result.action).toHaveLength(2);
    });

    test('no actions → action is null', async () => {
        callGemma4.mockResolvedValue(multiIntentJSON([
            { intent: 'task', message: 'הוסף פגישה' },
            { intent: 'reminder', message: 'תזכיר לי' },
        ]));
        runTaskAgent.mockResolvedValue({ answer: 'a' });
        runReminderAgent.mockResolvedValue({ answer: 'b' });

        const result = await runOrchestratorAgent(multiHintMsg, supabase, false, {});
        expect(result.action).toBeNull();
    });
});
