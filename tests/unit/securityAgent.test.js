jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { callGemma4 } = require('../../agents/models');
const { runSecurityAgent } = require('../../agents/securityAgent');

const mockSendEmail = jest.fn().mockResolvedValue(true);

beforeEach(() => jest.clearAllMocks());

describe('runSecurityAgent', () => {
    it('returns security scan result', async () => {
        callGemma4.mockResolvedValue('✅ לא נמצאו בעיות אבטחה קריטיות.');
        const result = await runSecurityAgent('סרוק אבטחה', false, mockSendEmail);
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('handles scan failure gracefully', async () => {
        callGemma4.mockRejectedValue(new Error('scan failed'));
        const result = await runSecurityAgent('בדיקת אבטחה', false, mockSendEmail);
        expect(result).toHaveProperty('answer');
    });

    it('does not expose raw errors to user', async () => {
        callGemma4.mockRejectedValue(new Error('internal API key leak test'));
        const result = await runSecurityAgent('סריקה', false, mockSendEmail);
        expect(result.answer).not.toContain('API key leak test');
    });
});
