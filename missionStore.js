// missions.json CRUD — mirrors the backlog.json storage pattern in server.js.
// Storage shape:
//   { missions: [Mission], _nextId: number }
//
// Mission shape:
//   {
//     id, source ('proposal'|'manual'|'factory'), sourceId,
//     title, origin,
//     status: 'clarifying'|'planning'|'awaiting_approval'|'executing'|'paused'|'done'|'cancelled',
//     goal: string|null,
//     plan: [{ id, text, status: 'pending'|'doing'|'done' }] | null,
//     conversation: [{ role: 'user'|'jarvis', text, ts }],
//     executor: 'local' | 'claude-agent-sdk',
//     executorState: object,
//     created_at, updated_at
//   }

const fs   = require('fs');
const path = require('path');

const MISSIONS_PATH = () => path.join(__dirname, 'missions.json');

function readAll() {
    try {
        const raw = fs.readFileSync(MISSIONS_PATH(), 'utf8');
        const data = JSON.parse(raw);
        if (!Array.isArray(data.missions)) data.missions = [];
        if (typeof data._nextId !== 'number') {
            data._nextId = data.missions.length === 0
                ? 1
                : Math.max(...data.missions.map(m => Number(m.id) || 0)) + 1;
        }
        return data;
    } catch {
        return { missions: [], _nextId: 1 };
    }
}

function writeAll(data) {
    fs.writeFileSync(MISSIONS_PATH(), JSON.stringify(data, null, 2));
}

function listMissions() {
    return readAll().missions;
}

function getMission(id) {
    const numId = Number(id);
    return readAll().missions.find(m => Number(m.id) === numId) || null;
}

function createMission({ source, sourceId, title, origin, executor = 'local' }) {
    const data = readAll();
    const now  = new Date().toISOString();
    const mission = {
        id:            data._nextId,
        source,
        sourceId:      sourceId == null ? null : String(sourceId),
        title:         (title || '').trim(),
        origin:        (origin || '').trim(),
        status:        'clarifying',
        goal:          null,
        plan:          null,
        conversation:  [],
        executor,
        executorState: {},
        created_at:    now,
        updated_at:    now,
    };
    data.missions.unshift(mission);
    data._nextId++;
    writeAll(data);
    return mission;
}

function updateMission(id, patch) {
    const data = readAll();
    const numId = Number(id);
    const idx = data.missions.findIndex(m => Number(m.id) === numId);
    if (idx === -1) return null;
    data.missions[idx] = {
        ...data.missions[idx],
        ...patch,
        id: data.missions[idx].id,            // never mutate id
        updated_at: new Date().toISOString(),
    };
    writeAll(data);
    return data.missions[idx];
}

function appendMessage(id, role, text) {
    const mission = getMission(id);
    if (!mission) return null;
    const conversation = [...(mission.conversation || []), {
        role,
        text: String(text || ''),
        ts:   new Date().toISOString(),
    }];
    return updateMission(id, { conversation });
}

function setPlan(id, plan, goal = null) {
    const normalized = (plan || []).map((step, i) => ({
        id:     step.id || `step-${Date.now()}-${i}`,
        text:   String(step.text || step || '').trim(),
        why:    step.why ? String(step.why) : '',
        status: step.status || 'pending',
    }));
    const patch = { plan: normalized };
    if (goal != null) patch.goal = String(goal).trim();
    return updateMission(id, patch);
}

function setStepStatus(missionId, stepId, status) {
    const mission = getMission(missionId);
    if (!mission || !Array.isArray(mission.plan)) return null;
    const plan = mission.plan.map(s =>
        s.id === stepId ? { ...s, status } : s
    );
    let next = updateMission(missionId, { plan });
    // Auto-complete when all steps done
    if (next && plan.length > 0 && plan.every(s => s.status === 'done') && next.status === 'executing') {
        next = updateMission(missionId, { status: 'done' });
    }
    return next;
}

function deleteMission(id) {
    const data = readAll();
    const numId = Number(id);
    const before = data.missions.length;
    data.missions = data.missions.filter(m => Number(m.id) !== numId);
    if (data.missions.length === before) return false;
    writeAll(data);
    return true;
}

// Convenience: missions that are still in-flight (not done/cancelled)
function listActiveMissions() {
    return listMissions().filter(m =>
        !['done', 'cancelled'].includes(m.status)
    );
}

module.exports = {
    listMissions,
    listActiveMissions,
    getMission,
    createMission,
    updateMission,
    appendMessage,
    setPlan,
    setStepStatus,
    deleteMission,
};
