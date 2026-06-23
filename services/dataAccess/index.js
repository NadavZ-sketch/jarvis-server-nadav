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
const { createNoteRepo } = require('./noteRepo');
const { createShoppingRepo } = require('./shoppingRepo');
const { createHabitRepo } = require('./habitRepo');
const { createProjectRepo } = require('./projectRepo');
const { createSubtaskRepo } = require('./subtaskRepo');
const { createContactRepo } = require('./contactRepo');
const { createChatRepo } = require('./chatRepo');
const { createSurveyRepo } = require('./surveyRepo');
const { createSummaryRepo } = require('./summaryRepo');
const { createProfileRepo } = require('./profileRepo');
const { createSprintRepo } = require('./sprintRepo');
const { createCronRepo } = require('./cronRepo');
const { createTelemetryRepo } = require('./telemetryRepo');
const { createMetricsRepo } = require('./metricsRepo');
const { createDeviceRepo } = require('./deviceRepo');
const { createStatsRepo } = require('./statsRepo');
const { createE2eRepo } = require('./e2eRepo');
const { createExecutionLogRepo } = require('./executionLogRepo');
const { createPromptLibraryRepo } = require('./promptLibraryRepo');
const { createTestCasesRepo } = require('./testCasesRepo');
const { createTableRepo } = require('./tableRepo');
const { createPlaylistRepo } = require('./playlistRepo');
const { createUserPromptRepo } = require('./userPromptRepo');

function createRepos(supabase) {
    const generic = {};
    return {
        tasks: createTaskRepo(supabase),
        reminders: createReminderRepo(supabase),
        memories: createMemoryRepo(supabase),
        notes: createNoteRepo(supabase),
        shopping: createShoppingRepo(supabase),
        habits: createHabitRepo(supabase),
        projects: createProjectRepo(supabase),
        subtasks: createSubtaskRepo(supabase),
        contacts: createContactRepo(supabase),
        chat: createChatRepo(supabase),
        surveys: createSurveyRepo(supabase),
        summaries: createSummaryRepo(supabase),
        profile: createProfileRepo(supabase),
        sprints: createSprintRepo(supabase),
        cron: createCronRepo(supabase),
        telemetry: createTelemetryRepo(supabase),
        metrics: createMetricsRepo(supabase),
        devices: createDeviceRepo(supabase),
        stats: createStatsRepo(supabase),
        e2e: createE2eRepo(supabase),
        executionLog: createExecutionLogRepo(supabase),
        promptLibrary: createPromptLibraryRepo(supabase),
        testCases: createTestCasesRepo(supabase),
        playlist: createPlaylistRepo(supabase),
        userPrompts: createUserPromptRepo(supabase),
        // Lazily-built, memoised generic repo for any other table.
        table(name) {
            return generic[name] || (generic[name] = createTableRepo(supabase, name));
        },
    };
}

module.exports = { createRepos };
