'use strict';

// Shared writer for the repo's local JSON state files (backlog.json,
// features.json, router-overrides.json, the local profile fallback…).
// The payload is written to a temp file and rename()d into place — atomic on
// POSIX — so a crash mid-write or a concurrent reader never sees a truncated
// or half-written file. (Same pattern as agentRegistryService.)

const fs = require('fs');

function writeJsonAtomic(filePath, data) {
    const tmp = `${filePath}.tmp.${process.pid}`;
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf8');
    fs.renameSync(tmp, filePath);
}

module.exports = { writeJsonAtomic };
