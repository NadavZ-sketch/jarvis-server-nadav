const path = require('path');
const fs = require('fs');
const os = require('os');

// Redirect the persistence target into a tmp dir for each test run.
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-status-'));
const fakeStatusPath = path.join(tmpDir, 'agent-status.json');

// Replace the real path constant by intercepting fs writes. The service
// derives its path from __dirname, so we patch fs.* to redirect any
// access to '*agent-status.json' to our tmp file.
const realFs = require('fs');
const origExists = realFs.existsSync;
const origRead = realFs.readFileSync;
const origWrite = realFs.writeFileSync;
const origMkdir = realFs.mkdirSync;

function isStatusFile(p) {
    return typeof p === 'string' && p.endsWith('agent-status.json');
}
realFs.existsSync = (p, ...rest) => isStatusFile(p) ? origExists(fakeStatusPath) : origExists(p, ...rest);
realFs.readFileSync = (p, ...rest) => isStatusFile(p) ? origRead(fakeStatusPath, ...rest) : origRead(p, ...rest);
realFs.writeFileSync = (p, data, opts) => isStatusFile(p) ? origWrite(fakeStatusPath, data, opts) : origWrite(p, data, opts);
realFs.mkdirSync = (p, opts) => isStatusFile(p) ? undefined : origMkdir(p, opts);

const { getAgentRegistry, setAgentStatus } = require('../../services/agentRegistryService');

afterAll(() => {
    realFs.existsSync = origExists;
    realFs.readFileSync = origRead;
    realFs.writeFileSync = origWrite;
    realFs.mkdirSync = origMkdir;
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
        const before = getAgentRegistry();
        const target = before[0].id;
        setAgentStatus(target, 'disabled');
        const after = getAgentRegistry();
        const updated = after.find(a => a.id === target);
        expect(updated.status).toBe('disabled');
        expect(updated.statusUpdatedAt).toBeTruthy();
    });

    it('toggles back to active', () => {
        const id = getAgentRegistry()[0].id;
        setAgentStatus(id, 'disabled');
        setAgentStatus(id, 'active');
        const updated = getAgentRegistry().find(a => a.id === id);
        expect(updated.status).toBe('active');
    });

    it('rejects invalid status values', () => {
        expect(() => setAgentStatus('chatAgent', 'sleeping')).toThrow();
    });

    it('rejects missing agent id', () => {
        expect(() => setAgentStatus('', 'active')).toThrow();
    });
});
