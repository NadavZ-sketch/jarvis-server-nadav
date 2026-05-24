const path = require('path');
const fs = require('fs');
const os = require('os');

// Redirect the persistence target into a tmp dir for each test run.
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-status-'));
const fakeStatusPath = path.join(tmpDir, 'agent-status.json');

// Replace the real path constant by intercepting fs writes. The service
// derives its path from __dirname, so we patch fs.* to redirect any
// access to '*agent-status.json' (and its .tmp.* variants) to our tmp file.
const realFs = require('fs');
const origExists = realFs.existsSync;
const origRead = realFs.readFileSync;
const origWrite = realFs.writeFileSync;
const origMkdir = realFs.mkdirSync;
const origRename = realFs.renameSync;

function isStatusFile(p) {
    return typeof p === 'string' && (p.endsWith('agent-status.json') || p.includes('agent-status.json.tmp.'));
}
function statusRedirect(p) {
    // Map .tmp.* variants to a matching tmp path so rename works within tmpDir
    if (typeof p === 'string' && p.includes('agent-status.json.tmp.')) {
        return fakeStatusPath + '.tmp.' + p.split('.tmp.').pop();
    }
    return fakeStatusPath;
}
realFs.existsSync = (p, ...rest) => isStatusFile(p) ? origExists(statusRedirect(p)) : origExists(p, ...rest);
realFs.readFileSync = (p, ...rest) => isStatusFile(p) ? origRead(statusRedirect(p), ...rest) : origRead(p, ...rest);
realFs.writeFileSync = (p, data, opts) => isStatusFile(p) ? origWrite(statusRedirect(p), data, opts) : origWrite(p, data, opts);
realFs.mkdirSync = (p, opts) => isStatusFile(p) ? undefined : origMkdir(p, opts);
realFs.renameSync = (src, dst) => (isStatusFile(src) || isStatusFile(dst)) ? origRename(statusRedirect(src), statusRedirect(dst)) : origRename(src, dst);

const { getAgentRegistry, setAgentStatus, setAgentRisk } = require('../../services/agentRegistryService');

// router/chatAgent are protected core agents; use a regular one for toggle tests.
const TOGGLE_TARGET = 'weatherAgent';

afterAll(() => {
    realFs.existsSync = origExists;
    realFs.readFileSync = origRead;
    realFs.writeFileSync = origWrite;
    realFs.mkdirSync = origMkdir;
    realFs.renameSync = origRename;
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) {}
});

beforeEach(() => {
    try { fs.unlinkSync(fakeStatusPath); } catch (_) {}
});

describe('agentRegistryService', () => {
    it('returns the static registry by default with active status', () => {
        const registry = getAgentRegistry();
        expect(registry.length).toBeGreaterThan(10);
        expect(registry[0]).toHaveProperty('id');
        expect(registry[0]).toHaveProperty('status');
    });

    it('persists and applies a disabled override', () => {
        setAgentStatus(TOGGLE_TARGET, 'disabled');
        const updated = getAgentRegistry().find(a => a.id === TOGGLE_TARGET);
        expect(updated.status).toBe('disabled');
        expect(updated.statusUpdatedAt).toBeTruthy();
    });

    it('toggles back to active', () => {
        setAgentStatus(TOGGLE_TARGET, 'disabled');
        setAgentStatus(TOGGLE_TARGET, 'active');
        const updated = getAgentRegistry().find(a => a.id === TOGGLE_TARGET);
        expect(updated.status).toBe('active');
    });

    it('rejects invalid status values', () => {
        expect(() => setAgentStatus('chatAgent', 'sleeping')).toThrow();
    });

    it('rejects missing agent id', () => {
        expect(() => setAgentStatus('', 'active')).toThrow();
    });

    it('refuses to disable a protected core agent (router)', () => {
        expect(() => setAgentStatus('router', 'disabled')).toThrow();
        const router = getAgentRegistry().find(a => a.id === 'router');
        expect(router.status).toBe('active');
    });

    it('allows re-activating a protected core agent', () => {
        expect(() => setAgentStatus('chatAgent', 'active')).not.toThrow();
    });

    it('persists and applies a risk-level override', () => {
        setAgentRisk(TOGGLE_TARGET, 'high');
        const updated = getAgentRegistry().find(a => a.id === TOGGLE_TARGET);
        expect(updated.risk).toBe('high');
    });

    it('rejects invalid risk levels', () => {
        expect(() => setAgentRisk(TOGGLE_TARGET, 'extreme')).toThrow();
    });

    it('keeps status and risk overrides independent', () => {
        setAgentStatus(TOGGLE_TARGET, 'disabled');
        setAgentRisk(TOGGLE_TARGET, 'high');
        const updated = getAgentRegistry().find(a => a.id === TOGGLE_TARGET);
        expect(updated.status).toBe('disabled');
        expect(updated.risk).toBe('high');
    });
});
