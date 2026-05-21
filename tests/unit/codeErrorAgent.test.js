'use strict';

jest.mock('../../agents/e2e/codeErrorScanner', () => ({ runCodeErrorScanner: jest.fn() }));

const { runCodeErrorScanner } = require('../../agents/e2e/codeErrorScanner');
const { runCodeErrorAgent } = require('../../agents/codeErrorAgent');

const finding = (sev, target = 'server.js:10') => ({
    severity: sev,
    target,
    finding: `בעיה ב-${target}`,
    recommendation: `תקן את ${target}`,
});

beforeEach(() => jest.clearAllMocks());

describe('runCodeErrorAgent — report formatting', () => {
    test('renders header, score and severity counts', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [finding('critical'), finding('critical'), finding('high'), finding('medium'), finding('low')],
            claudePrompt: 'FIX PROMPT BLOCK',
            summary: 'נמצאו 5 בעיות',
            score: 42,
        });

        const result = await runCodeErrorAgent('סרוק שגיאות קוד', false);
        expect(result.answer).toContain('דוח שגיאות קוד');
        expect(result.answer).toContain('42/100');
        expect(result.answer).toContain('🔴 קריטי: 2');
        expect(result.answer).toContain('🟠 גבוה: 1');
        expect(result.answer).toContain('🟡 בינוני: 1');
        expect(result.answer).toContain('🟢 נמוך: 1');
        expect(result.answer).toContain('נמצאו 5 בעיות');
    });

    test('appends Claude prompt block when findings exist', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [finding('high')],
            claudePrompt: 'COPY-ME-PROMPT',
            summary: 'בעיה אחת',
            score: 80,
        });
        const result = await runCodeErrorAgent('סרוק', false);
        expect(result.answer).toContain('לתיקון בקלוד');
        expect(result.answer).toContain('COPY-ME-PROMPT');
    });

    test('no findings → clean message, no Claude block', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [],
            claudePrompt: '',
            summary: 'הכל תקין',
            score: 100,
        });
        const result = await runCodeErrorAgent('סרוק', false);
        expect(result.answer).toContain('לא נמצאו שגיאות קוד');
        expect(result.answer).not.toContain('לתיקון בקלוד');
        expect(result.answer).toContain('100/100');
    });

    test('unknown severity uses neutral marker and is not miscounted', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [finding('bogus')],
            claudePrompt: 'p',
            summary: 's',
            score: 90,
        });
        const result = await runCodeErrorAgent('סרוק', false);
        expect(result.answer).toContain('⚪');
        expect(result.answer).toContain('🔴 קריטי: 0');
    });
});

describe('runCodeErrorAgent — email path', () => {
    test('sends email when asked and findings exist', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [finding('critical')],
            claudePrompt: 'p',
            summary: 's',
            score: 30,
        });
        const sendEmailFn = jest.fn().mockResolvedValue();
        const result = await runCodeErrorAgent('שלח דוח במייל', false, sendEmailFn);
        expect(sendEmailFn).toHaveBeenCalledTimes(1);
        expect(result.answer).toContain('נשלח למייל');
    });

    test('email failure is swallowed; report still returned', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [finding('high')],
            claudePrompt: 'p',
            summary: 's',
            score: 70,
        });
        const sendEmailFn = jest.fn().mockRejectedValue(new Error('SMTP down'));
        const result = await runCodeErrorAgent('שלח את הדוח למייל', false, sendEmailFn);
        expect(sendEmailFn).toHaveBeenCalled();
        expect(result.answer).not.toContain('נשלח למייל');
        expect(result.answer).toContain('דוח שגיאות קוד');
    });

    test('does not email when "שלח" present but there are no findings', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [],
            claudePrompt: '',
            summary: 'נקי',
            score: 100,
        });
        const sendEmailFn = jest.fn();
        await runCodeErrorAgent('שלח דוח', false, sendEmailFn);
        expect(sendEmailFn).not.toHaveBeenCalled();
    });

    test('does not email when no sendEmailFn provided', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [finding('low')],
            claudePrompt: 'p',
            summary: 's',
            score: 95,
        });
        const result = await runCodeErrorAgent('שלח דוח', false);
        expect(result.answer).not.toContain('נשלח למייל');
    });
});

describe('runCodeErrorAgent — failure handling', () => {
    test('scanner throwing returns a graceful Hebrew error', async () => {
        runCodeErrorScanner.mockRejectedValue(new Error('scan exploded'));
        const result = await runCodeErrorAgent('סרוק', false);
        expect(result.answer).toContain('לא הצלחתי לסרוק את הקוד');
    });

    test('works with default empty userMessage argument', async () => {
        runCodeErrorScanner.mockResolvedValue({
            findings: [], claudePrompt: '', summary: 'ok', score: 100,
        });
        const result = await runCodeErrorAgent();
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });
});
