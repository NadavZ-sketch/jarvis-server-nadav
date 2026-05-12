'use strict';

const { execSync } = require('child_process');

const files = execSync('rg --files -g "*.js"', { encoding: 'utf8' })
  .trim()
  .split(/\n+/)
  .filter(Boolean);

for (const file of files) {
  execSync(`node --check "${file}"`, { stdio: 'pipe' });
}

console.log(`lint: syntax ok for ${files.length} files`);
