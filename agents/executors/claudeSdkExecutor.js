// Stub for the future Claude Agent SDK executor.
//
// Phase 2 will spawn an Anthropic SDK agent loop with Bash/Read/Edit/Write
// tools against a worktree of the repo, streaming logs back into
// mission.executorState. This file holds the seam so mission records can
// already store `executor: 'claude-agent-sdk'` and the orchestrator will
// dispatch to it once the implementation lands.

async function run(mission) {
    return {
        tasks:  [],
        prompt: null,
        notice: 'אקזקיוטר Claude Agent SDK עדיין לא מחובר — יופעל בעדכון הבא. בינתיים נשתמש באקזקיוטר המקומי.',
        errors: [],
        deferred: true,
    };
}

module.exports = { run };
