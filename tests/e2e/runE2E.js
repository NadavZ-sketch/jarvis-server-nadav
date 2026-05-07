#!/usr/bin/env node
// CLI runner for the E2E testing agent.
//   npm run e2e
//   npm run e2e -- --probes=api,static --base-url=http://localhost:3000
//   npm run e2e:local

require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');
const { runE2EAgent } = require('../../agents/e2eAgent');

function parseArgs(argv) {
    const out = { useLocal: false, disableLearning: false };
    for (const a of argv.slice(2)) {
        if (a === '--local') out.useLocal = true;
        else if (a === '--no-learn') out.disableLearning = true;
        else if (a.startsWith('--probes=')) out.onlyProbes = a.split('=')[1].split(',').map(s => s.trim()).filter(Boolean);
        else if (a.startsWith('--base-url=')) out.baseUrl = a.split('=')[1];
    }
    return out;
}

async function main() {
    const args = parseArgs(process.argv);

    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
    const supabase = (url && key) ? createClient(url, key) : null;
    if (!supabase) console.warn('⚠️  No Supabase credentials — findings will not be persisted.');

    const result = await runE2EAgent('בצע בדיקות קצה', supabase, args.useLocal, {
        onlyProbes: args.onlyProbes,
        baseUrl: args.baseUrl,
        disableLearning: args.disableLearning,
    });

    console.log('\n' + result.answer + '\n');

    const counts = result.action?.counts || {};
    process.exit(counts.critical > 0 ? 1 : 0);
}

main().catch(err => {
    console.error('E2E runner crashed:', err);
    process.exit(2);
});
