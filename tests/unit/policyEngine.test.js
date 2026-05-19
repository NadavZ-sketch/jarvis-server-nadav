'use strict';

// Reset module registry before each test so the `cached` singleton in
// policyEngine.js is cleared.  We also re-acquire the fs mock each time
// because jest.resetModules() creates a fresh mock instance.

beforeEach(() => {
    jest.resetModules();
    jest.mock('fs');
});

function makePolicyJson(overrides = {}) {
    return JSON.stringify({
        blocklist: ['admin.reset_system', 'contacts.export_all'],
        allowlist: {
            free:  { member: ['chat.ask', 'contacts.read', 'contacts.create', 'contacts.update', 'contacts.delete', 'messaging.send'] },
            pro:   { member: ['*'], admin: ['*'] },
        },
        ...overrides,
    });
}

// Returns a fresh {policyEngine, fs} where fs.readFileSync returns validPolicy
function load(fileContent = makePolicyJson()) {
    const fs = require('fs');
    if (fileContent instanceof Error) {
        fs.readFileSync.mockImplementation(() => { throw fileContent; });
    } else {
        fs.readFileSync.mockReturnValue(fileContent);
    }
    return { engine: require('../../services/policyEngine'), fs };
}

// ── isAllowedByRolePlan ───────────────────────────────────────────────────────

describe('isAllowedByRolePlan', () => {
    test('free/member: allowed action (chat.ask) → true', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'chat.ask', role: 'member', plan: 'free' })).toBe(true);
    });

    test('free/member: allowed action (messaging.send) → true', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'messaging.send', role: 'member', plan: 'free' })).toBe(true);
    });

    test('free/member: action not in allowlist → false', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'admin.reset_system', role: 'member', plan: 'free' })).toBe(false);
    });

    test('pro/member: wildcard * allows any action → true', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'admin.reset_system', role: 'member', plan: 'pro' })).toBe(true);
    });

    test('pro/admin: wildcard * allows any action → true', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'contacts.export_all', role: 'admin', plan: 'pro' })).toBe(true);
    });

    test('unknown plan → false', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'chat.ask', role: 'member', plan: 'enterprise' })).toBe(false);
    });

    test('unknown role → false', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'chat.ask', role: 'superuser', plan: 'free' })).toBe(false);
    });

    test('defaults to member/free when role and plan omitted', () => {
        const { engine } = load();
        expect(engine.isAllowedByRolePlan({ actionType: 'chat.ask' })).toBe(true);
        expect(engine.isAllowedByRolePlan({ actionType: 'admin.reset_system' })).toBe(false);
    });
});

// ── isBlockedAction ───────────────────────────────────────────────────────────

describe('isBlockedAction', () => {
    test('blocked action → true', () => {
        const { engine } = load();
        expect(engine.isBlockedAction('admin.reset_system')).toBe(true);
    });

    test('another blocked action → true', () => {
        const { engine } = load();
        expect(engine.isBlockedAction('contacts.export_all')).toBe(true);
    });

    test('normal action not in blocklist → false', () => {
        const { engine } = load();
        expect(engine.isBlockedAction('chat.ask')).toBe(false);
    });

    test('unknown action → false', () => {
        const { engine } = load();
        expect(engine.isBlockedAction('nonexistent.action')).toBe(false);
    });
});

// ── loadPolicyRules ───────────────────────────────────────────────────────────

describe('loadPolicyRules', () => {
    test('returns parsed rules from file', () => {
        const { engine } = load();
        const rules = engine.loadPolicyRules();
        expect(rules.blocklist).toContain('admin.reset_system');
        expect(rules.allowlist.pro.member).toContain('*');
    });

    test('caches result — reads file only once across multiple calls', () => {
        const { engine, fs } = load();
        engine.loadPolicyRules();
        engine.loadPolicyRules();
        engine.loadPolicyRules();
        expect(fs.readFileSync).toHaveBeenCalledTimes(1);
    });

    test('corrupt JSON → falls back to empty policy', () => {
        const { engine } = load('NOT_VALID_JSON');
        const rules = engine.loadPolicyRules();
        expect(rules).toEqual({ blocklist: [], allowlist: {} });
    });

    test('file read error → falls back to empty policy', () => {
        const { engine } = load(new Error('ENOENT'));
        const rules = engine.loadPolicyRules();
        expect(rules).toEqual({ blocklist: [], allowlist: {} });
    });

    test('empty blocklist in file → isBlockedAction returns false for anything', () => {
        const { engine } = load(JSON.stringify({ blocklist: [], allowlist: {} }));
        expect(engine.isBlockedAction('admin.reset_system')).toBe(false);
    });
});
