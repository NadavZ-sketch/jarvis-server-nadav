'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../agents/router',  () => ({ invalidateRouterCache: jest.fn() }));

const fs = require('fs');
const { callGemma4 } = require('../../agents/models');
const {
    runAgentFactoryAgent,
    sanitizeAgentName,
    isCodeSafe,
    readRegistry,
} = require('../../agents/agentFactoryAgent');

afterEach(() => jest.restoreAllMocks());

// Helpers
const SAFE_CODE   = 'async function runFoo(u,r,l,s){return{answer:"hi"}}\nmodule.exports={runFoo};';
const REGISTRY_1  = JSON.stringify([
    { name: 'myAgent', filePath: 'agents/custom/myAgent.js', description: 'test', createdAt: '2024-01-01T00:00:00Z' },
]);

function mockEmptyRegistry() {
    jest.spyOn(fs, 'readFileSync').mockImplementation(() => { throw new Error('ENOENT'); });
}
function mockRegistry(data) {
    jest.spyOn(fs, 'readFileSync').mockReturnValue(typeof data === 'string' ? data : JSON.stringify(data));
}
function mockWriteOps() {
    jest.spyOn(fs, 'writeFileSync').mockImplementation(() => {});
    jest.spyOn(fs, 'renameSync').mockImplementation(() => {});
    jest.spyOn(fs, 'mkdirSync').mockImplementation(() => {});
    jest.spyOn(fs, 'unlinkSync').mockImplementation(() => {});
}

// ─── sanitizeAgentName ────────────────────────────────────────────────────────

describe('sanitizeAgentName', () => {
    test.each([
        ['myAgent',   'myAgent'],
        ['weather123','weather123'],
        ['my agent',  'myAgent'],
    ])('valid: "%s" → "%s"', (input, expected) => {
        expect(sanitizeAgentName(input)).toBe(expected);
    });

    test.each([
        ['ab'],
        ['../etc/passwd'],
        ['has spaces extra long name that exceeds limit'],
        [''],
        [null],
    ])('invalid: "%s" → null', (input) => {
        expect(sanitizeAgentName(input)).toBeNull();
    });
});

// ─── isCodeSafe ───────────────────────────────────────────────────────────────

describe('isCodeSafe', () => {
    test('valid code passes',                    () => expect(isCodeSafe(SAFE_CODE)).toBe(true));
    test('missing module.exports fails',         () => expect(isCodeSafe('async function run(){}' )).toBe(false));
    test('child_process require fails',          () => expect(isCodeSafe("require('child_process'); module.exports={};")).toBe(false));
    test('eval fails',                           () => expect(isCodeSafe("eval('x'); module.exports={};")).toBe(false));
});

// ─── readRegistry ─────────────────────────────────────────────────────────────

describe('readRegistry', () => {
    test('returns [] when file missing', () => {
        mockEmptyRegistry();
        expect(readRegistry()).toEqual([]);
    });

    test('parses registry file', () => {
        mockRegistry(REGISTRY_1);
        expect(readRegistry()).toHaveLength(1);
        expect(readRegistry()[0].name).toBe('myAgent');
    });
});

// ─── list ─────────────────────────────────────────────────────────────────────

describe('list agents', () => {
    test('empty → no-agents message', async () => {
        mockEmptyRegistry();
        const res = await runAgentFactoryAgent('רשימת סוכנים', {}, false, {});
        expect(res.answer).toContain('אין');
    });

    test('lists registered agents', async () => {
        mockRegistry(REGISTRY_1);
        const res = await runAgentFactoryAgent('הסוכנים שלי', {}, false, {});
        expect(res.answer).toContain('myAgent');
        expect(res.answer).toContain('test');
    });
});

// ─── create ───────────────────────────────────────────────────────────────────

describe('create agent', () => {
    beforeEach(() => {
        callGemma4.mockResolvedValue(SAFE_CODE);
        mockEmptyRegistry();
        mockWriteOps();
    });

    test('creates agent and returns action', async () => {
        const res = await runAgentFactoryAgent('צור סוכן testbot שיענה בברכה', {}, false, {});
        expect(res.answer).toContain('testbot');
        expect(res.action?.type).toBe('agent_created');
        expect(res.action?.agentName).toBe('testbot');
    });

    test('rejects duplicate name', async () => {
        mockRegistry(REGISTRY_1);
        const res = await runAgentFactoryAgent('צור סוכן myAgent שיעשה משהו', {}, false, {});
        expect(res.answer).toContain('כבר קיים');
    });

    test('rejects unsafe generated code', async () => {
        callGemma4.mockResolvedValue("require('child_process'); module.exports={};");
        const res = await runAgentFactoryAgent('צור סוכן testbot שמריץ פקודות', {}, false, {});
        expect(res.answer).toContain('אבטחה');
        expect(fs.writeFileSync).not.toHaveBeenCalledWith(
            expect.stringContaining('.js'),
            expect.anything(),
            expect.anything()
        );
    });
});

// ─── delete ───────────────────────────────────────────────────────────────────

describe('delete agent', () => {
    beforeEach(() => {
        mockRegistry(REGISTRY_1);
        mockWriteOps();
    });

    test('deletes existing agent', async () => {
        const res = await runAgentFactoryAgent('מחק סוכן myAgent', {}, false, {});
        expect(res.answer).toContain('נמחק');
        expect(res.action?.type).toBe('agent_deleted');
    });

    test('not-found for unknown agent', async () => {
        const res = await runAgentFactoryAgent('מחק סוכן unknownAgent', {}, false, {});
        expect(res.answer).toContain('לא נמצא');
    });
});

// ─── help fallback ────────────────────────────────────────────────────────────

describe('help fallback', () => {
    test('returns usage instructions for unrecognised message', async () => {
        mockEmptyRegistry();
        const res = await runAgentFactoryAgent('מה אתה יכול?', {}, false, {});
        expect(res.answer).toContain('ניהול סוכנים');
    });
});
