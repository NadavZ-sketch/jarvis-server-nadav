jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('fs', () => ({
    ...jest.requireActual('fs'),
    writeFileSync: jest.fn(),
    readFileSync: jest.fn().mockReturnValue('[]'),
    existsSync: jest.fn().mockReturnValue(true),
}));

const { callGemma4 } = require('../../agents/models');
const { runAgentFactoryAgent } = require('../../agents/agentFactoryAgent');
const mockSupabase = {};

beforeEach(() => jest.clearAllMocks());

describe('runAgentFactoryAgent', () => {
    it('returns response for agent creation request', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({
            name: 'testAgent', description: 'test', keywords: ['test'], prompt: 'you are a test agent'
        }));
        const result = await runAgentFactoryAgent('צור סוכן בדיקה', mockSupabase, false);
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });

    it('lists existing agents', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list' }));
        const result = await runAgentFactoryAgent('הצג אייג\'נטים', mockSupabase, false);
        expect(result).toHaveProperty('answer');
    });

    it('handles LLM failure gracefully', async () => {
        callGemma4.mockRejectedValue(new Error('LLM error'));
        const result = await runAgentFactoryAgent('צור אייג\'נט', mockSupabase, false);
        expect(result).toHaveProperty('answer');
        expect(typeof result.answer).toBe('string');
    });
});
