// Executor registry. Mission records carry a string `executor` field;
// runExecutor looks the implementation up here.
//
// New executors plug in by adding a key here and exporting `run(mission, ctx)`
// that returns { tasks, prompt, errors, ...extras }.

const local      = require('./localExecutor');
const claudeSdk  = require('./claudeSdkExecutor');

const REGISTRY = {
    local,
    'claude-agent-sdk': claudeSdk,
};

async function runExecutor(mission, ctx = {}) {
    const impl = REGISTRY[mission.executor] || REGISTRY.local;
    return impl.run(mission, ctx);
}

function listExecutors() {
    return Object.keys(REGISTRY);
}

module.exports = { runExecutor, listExecutors };
