'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = process.cwd();
const IGNORE_DIRS = new Set(['node_modules', '.git', 'jarvis_mobile/build']);

function collectJsFiles(dir, out = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    const rel = path.relative(ROOT, fullPath);

    if (entry.isDirectory()) {
      if (IGNORE_DIRS.has(rel) || IGNORE_DIRS.has(entry.name)) continue;
      collectJsFiles(fullPath, out);
      continue;
    }

    if (entry.isFile() && fullPath.endsWith('.js')) {
      out.push(fullPath);
    }
  }
  return out;
}

const files = collectJsFiles(ROOT);
for (const file of files) {
  execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' });
}

console.log(`lint: syntax ok for ${files.length} files`);
