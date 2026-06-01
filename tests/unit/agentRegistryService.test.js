const path = require('path');
const fs = require('fs');
const os = require('os');

// Redirect the persistence target into a tmp dir for each test run.
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-status-'));
const fakeStatusPath = path.join(tmpDir, 'agent-status.json');

// Replace the real path constant by intercepting fs writes. The service
// uses fs.promises.* (async) so we patch those. We also keep the sync
// shims in case any transitive path still uses them.
const realFs = require('fs');
const origExists = realFs.existsSync;
const origRead = realFs.readFileSync;
const origWrite = realFs.writeFileSync;
const origMkdir = realFs.mkdirSync;
const origRename = realFs.renameSync;
const origPromisesRead = realFs.promises.readFile;
const origPromisesWrite = realFs.promises.writeFile;
const origPromisesMkdir = realFs.promises.mkdir;
const origPromisesRename = realFs.promises.rename;

function isStatusFile(p) {
    return typeof p === 'string' && (p.endsWith('agent-status.json') || p.includes('agent-status.json.tmp.'));
}
function statusRedirect(p) {
    if (typeof p === 'string' && p.includes('agent-status.json.tmp.')) {
        return fakeStatusPath + '.tmp.' + p.split('.tmp.').pop();
    }
    return fakeStatusPath;
}

// Sync shims (kept for safety)
realFs.existsSync = (p, ...rest) => isStatusFile(p) ? origExists(statusRedirect(p)) : origExists(p, ...rest);
realFs.readFileSync = (p, ...rest) => isStatusFile(p) ? origRead(statusRedirect(p), ...rest) : origRead(p, ...rest);
realFs.writeFileSync = (p, data, opts) => isStatusFile(p) ? origWrite(statusRedirect(p), data, opts) : origWrite(p, data, opts);
realFs.mkdirSync = (p, opts) => isStatusFile(p) ? undefined : origMkdir(p, opts);
realFs.renameSync = (src, dst) => (isStatusFile(src) || isStatusFile(dst)) ? origRename(statusRedirect(src), statusRedirect(dst)) : origRename(src, dst);

// Async (promises) shims
realFs.promises.readFile = (p, ...rest) => isStatusFile(p) ? origPromisesRead(statusRedirect(p), ...rest) : origPromisesRead(p, ...rest);
realFs.promises.writeFile = (p, data, opts) => isStatusFile(p) ? origPromisesWrite(statusRedirect(p), data, opts) : origPromisesWrite(p, data, opts);
realFs.promises.mkdir = (p, opts) => isStatusFile(p) ? Promise.resolve() : origPromisesMkdir(p, opts);
realFs.promises.rename = (src, dst) => (isStatusFile(src) || isStatusFile(dst)) ? origPromisesRename(statusRedirect(src), statusRedirect(dst)) : origPromisesRename(src, dst);

const { getAgentRegistry, setAgentStatus, setAgentRisk } = require('../../services/agentRegistryService');

// router/chatAgent are protected core agents; use a regular one for toggle tests.
const TOGGLE_TARGET = 'weatherAgent';

afterAll(() => {
    realFs.existsSync = origExists;
    realFs.readFileSync = origRead;
    realFs.writeFileSync = origWrite;
    realFs.mkdirSync = origMkdir;
    realFs.renameSync = origRename;
    realFs.promises.readFile = origPromisesRead;
    realFs.promises.writeFile = origPromisesWrite;
    realFs.promises.mkdir = origPromisesMkdir;
    realFs.promises.rename = origPromisesRename;
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) {}
});

beforeEach(() => {
    try { fs.unlinkSync(fakeStatusPath); } catch (_) {}
});

describe('agentRegistryService', () => {
    it('returns the static registry by default with active status', async () => {
        const registry = await getAgentRegistry();
        expect(registry.length).toBeGreaterThan(10);
        expect(registry[0]).toHaveProperty('id');
        expect(registry[0]).toHaveProperty('status');
    });

    it('persists and applies a disabled override', async () => {
        await setAgentStatus(TOGGLE_TARGET, 'disabled');
        const updated = (await getAgentRegistry()).find(a => a.id === TOGGLE_TARGET);
        expect(updated.status).toBe('disabled');
        expect(updated.statusUpdatedAt).toBeTruthy();
    });

    it('toggles back to active', async () => {
        await setAgentStatus(TOGGLE_TARGET, 'disabled');
        await setAgentStatus(TOGGLE_TARGET, 'active');
        const updated = (await getAgentRegistry()).find(a => a.id === TOGGLE_TARGET);
        expect(updated.status).toBe('active');
    });

    it('rejects invalid status values', async () => {
        await expect(setAgentStatus('chatAgent', 'sleeping')).rejects.toThrow();
    });

    it('rejects missing agent id', async () => {
        await expect(setAgentStatus('', 'active')).rejects.toThrow();
    });

    it('refuses to disable a protected core agent (router)', async () => {
        await expect(setAgentStatus('router', 'disabled')).rejects.toThrow();
        const router = (await getAgentRegistry()).find(a => a.id === 'router');
        expect(router.status).toBe('active');
    });

    it('allows re-activating a protected core agent', async () => {
        await expect(setAgentStatus('chatAgent', 'active')).resolves.not.toThrow();
    });

    it('persists and applies a risk-level override', async () => {
        await setAgentRisk(TOGGLE_TARGET, 'high');
        const updated = (await getAgentRegistry()).find(a => a.id === TOGGLE_TARGET);
        expect(updated.risk).toBe('high');
    });

    it('rejects invalid risk levels', async () => {
        await expect(setAgentRisk(TOGGLE_TARGET, 'extreme')).rejects.toThrow();
    });

    it('keeps status and risk overrides independent', async () => {
        await setAgentStatus(TOGGLE_TARGET, 'disabled');
        await setAgentRisk(TOGGLE_TARGET, 'high');
        const updated = (await getAgentRegistry()).find(a => a.id === TOGGLE_TARGET);
        expect(updated.status).toBe('disabled');
        expect(updated.risk).toBe('high');
    });
});
