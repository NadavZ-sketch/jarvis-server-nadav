'use strict';

// Data-access seam. `createRepos(supabase)` builds the repos bundle that crosses
// the seam: deep, named-method repos for the hot tables and a generic
// `table(name)` helper for the simple CRUD tables. Callers (agents, controllers,
// routes) receive this bundle instead of the raw Supabase client, so query
// construction and error modes live in one place and tests swap a second
// adapter (see tests/helpers/fakeRepos.js).

const { createTaskRepo } = require('./taskRepo');
const { createReminderRepo } = require('./reminderRepo');
const { createMemoryRepo } = require('./memoryRepo');
const { createTableRepo } = require('./tableRepo');

function createRepos(supabase) {
    const generic = {};
    return {
        tasks: createTaskRepo(supabase),
        reminders: createReminderRepo(supabase),
        memories: createMemoryRepo(supabase),
        // Lazily-built, memoised generic repo for any other table.
        table(name) {
            return generic[name] || (generic[name] = createTableRepo(supabase, name));
        },
    };
}

module.exports = { createRepos };
