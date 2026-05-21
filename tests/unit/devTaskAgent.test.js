'use strict';

jest.mock('fs', () => ({
    promises: {
        readFile: jest.fn(),
        writeFile: jest.fn(),
        unlink: jest.fn(),
    },
}));
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const fs = require('fs');
const { callGemma4 } = require('../../agents/models');
const {
    detectCapabilityGap,
    generateClaudePrompt,
    savePendingGap,
    loadPendingGap,
    clearPendingGap,
    saveDevTask,
    handleConfirmation,
    YES_PATTERN,
    NO_PATTERN,
} = require('../../agents/devTaskAgent');

beforeEach(() => {
    jest.clearAllMocks();
    fs.promises.writeFile.mockResolvedValue();
    fs.promises.unlink.mockResolvedValue();
});

describe('confirmation patterns', () => {
    test('YES_PATTERN matches affirmatives', () => {
        ['כן', 'אשר', 'בסדר', 'אוקי', 'יאללה', 'שמור', 'תוסיף'].forEach(w =>
            expect(YES_PATTERN.test(w)).toBe(true));
    });
    test('NO_PATTERN matches negatives', () => {
        ['לא', 'בטל', 'דלג', 'תדלג', 'לא צריך'].forEach(w =>
            expect(NO_PATTERN.test(w)).toBe(true));
    });
    test('patterns are mutually exclusive on clear inputs', () => {
        expect(YES_PATTERN.test('לא')).toBe(false);
        expect(NO_PATTERN.test('כן')).toBe(false);
    });
});

describe('generateClaudePrompt', () => {
    test('embeds the user request, action and capability title', () => {
        const out = generateClaudePrompt('שלח SMS לאשתי', {
            actionDescription: 'שליחת SMS לאיש קשר',
            capabilityTitle: 'שליחת SMS',
        });
        expect(out).toContain('שלח SMS לאשתי');
        expect(out).toContain('שליחת SMS לאיש קשר');
        expect(out).toContain('שליחת SMS');
        expect(out).toContain('router.js');
        expect(out).toContain('server.js');
    });
});

describe('detectCapabilityGap', () => {
    test('parses a positive gap result', async () => {
        callGemma4.mockResolvedValue('{"isGap": true, "actionDescription": "שליחת SMS", "capabilityTitle": "SMS"}');
        const r = await detectCapabilityGap('שלח SMS', 'אני לא יכול לשלוח SMS');
        expect(r).toEqual({ isGap: true, actionDescription: 'שליחת SMS', capabilityTitle: 'SMS' });
    });

    test('parses JSON embedded in extra text', async () => {
        callGemma4.mockResolvedValue('Here: {"isGap": true, "actionDescription": "x", "capabilityTitle": "y"} done');
        const r = await detectCapabilityGap('a', 'b');
        expect(r.isGap).toBe(true);
    });

    test('isGap=false when LLM says so', async () => {
        callGemma4.mockResolvedValue('{"isGap": false}');
        const r = await detectCapabilityGap('מה השעה', 'השעה 10:00');
        expect(r.isGap).toBe(false);
    });

    test('no JSON in response → { isGap:false }', async () => {
        callGemma4.mockResolvedValue('totally unstructured answer');
        const r = await detectCapabilityGap('a', 'b');
        expect(r).toEqual({ isGap: false });
    });

    test('malformed JSON → { isGap:false } (no throw)', async () => {
        callGemma4.mockResolvedValue('{ isGap: true, broken }');
        const r = await detectCapabilityGap('a', 'b');
        expect(r).toEqual({ isGap: false });
    });

    test('LLM throwing → { isGap:false }', async () => {
        callGemma4.mockRejectedValue(new Error('LLM down'));
        const r = await detectCapabilityGap('a', 'b');
        expect(r).toEqual({ isGap: false });
    });

    test('defaults missing fields to empty strings', async () => {
        callGemma4.mockResolvedValue('{"isGap": true}');
        const r = await detectCapabilityGap('a', 'b');
        expect(r).toEqual({ isGap: true, actionDescription: '', capabilityTitle: '' });
    });
});

describe('pending-gap persistence helpers', () => {
    test('loadPendingGap returns parsed object', async () => {
        fs.promises.readFile.mockResolvedValue('{"userRequest":"x"}');
        await expect(loadPendingGap()).resolves.toEqual({ userRequest: 'x' });
    });

    test('loadPendingGap returns null when file missing', async () => {
        fs.promises.readFile.mockRejectedValue(new Error('ENOENT'));
        await expect(loadPendingGap()).resolves.toBeNull();
    });

    test('savePendingGap writes the pending file as pretty JSON', async () => {
        await savePendingGap({ a: 1 });
        const [file, body] = fs.promises.writeFile.mock.calls[0];
        expect(String(file)).toContain('capability_gap_pending.json');
        expect(JSON.parse(body)).toEqual({ a: 1 });
    });

    test('clearPendingGap swallows unlink errors', async () => {
        fs.promises.unlink.mockRejectedValue(new Error('ENOENT'));
        await expect(clearPendingGap()).resolves.toBeUndefined();
    });
});

describe('saveDevTask', () => {
    test('appends a normalized task to existing backlog', async () => {
        fs.promises.readFile.mockResolvedValue(JSON.stringify({ dev_tasks: [], items: [] }));
        const task = await saveDevTask({
            title: 'SMS', userRequest: 'שלח SMS', actionDescription: 'A', claudePrompt: 'P',
        });
        expect(task.status).toBe('open');
        expect(task.id).toMatch(/^dt_/);
        expect(task.title).toBe('SMS');

        const written = JSON.parse(fs.promises.writeFile.mock.calls[0][1]);
        expect(written.dev_tasks).toHaveLength(1);
        expect(written.dev_tasks[0].title).toBe('SMS');
    });

    test('uses defaults when backlog file is unreadable', async () => {
        fs.promises.readFile.mockRejectedValue(new Error('no file'));
        await saveDevTask({ title: 'T', userRequest: 'U', actionDescription: 'A', claudePrompt: 'P' });
        const written = JSON.parse(fs.promises.writeFile.mock.calls[0][1]);
        expect(Array.isArray(written.dev_tasks)).toBe(true);
        expect(written.dev_tasks).toHaveLength(1);
    });

    test('repairs a corrupt non-array dev_tasks field', async () => {
        fs.promises.readFile.mockResolvedValue(JSON.stringify({ dev_tasks: 'corrupt' }));
        await saveDevTask({ title: 'T', userRequest: 'U', actionDescription: 'A', claudePrompt: 'P' });
        const written = JSON.parse(fs.promises.writeFile.mock.calls[0][1]);
        expect(Array.isArray(written.dev_tasks)).toBe(true);
        expect(written.dev_tasks).toHaveLength(1);
    });
});

describe('handleConfirmation', () => {
    const pending = {
        userRequest: 'שלח SMS',
        gapDetails: { capabilityTitle: 'שליחת SMS', actionDescription: 'שליחת SMS לאיש קשר' },
    };

    function mockFilesWithPending() {
        fs.promises.readFile.mockImplementation((p) => {
            if (String(p).includes('capability_gap_pending')) return Promise.resolve(JSON.stringify(pending));
            if (String(p).includes('backlog')) return Promise.resolve(JSON.stringify({ dev_tasks: [] }));
            return Promise.reject(new Error('unexpected read'));
        });
    }

    test('returns null when no pending gap exists', async () => {
        fs.promises.readFile.mockRejectedValue(new Error('ENOENT'));
        await expect(handleConfirmation('כן')).resolves.toBeNull();
    });

    test('YES creates a dev task, clears pending, and skips TTS', async () => {
        mockFilesWithPending();
        const r = await handleConfirmation('כן');
        expect(r.answer).toContain('נוספה משימת פיתוח');
        expect(r.answer).toContain('שליחת SMS');
        expect(r.skipTts).toBe(true);
        expect(fs.promises.unlink).toHaveBeenCalled();
    });

    test('NO clears pending without creating a task', async () => {
        mockFilesWithPending();
        const r = await handleConfirmation('לא');
        expect(r.answer).toContain('לא שמרתי');
        expect(fs.promises.unlink).toHaveBeenCalled();
        expect(fs.promises.writeFile).not.toHaveBeenCalled();
    });

    test('ambiguous reply with a pending gap → null', async () => {
        mockFilesWithPending();
        await expect(handleConfirmation('אולי אחר כך')).resolves.toBeNull();
    });
});
