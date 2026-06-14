'use strict';

// In-memory fake of the data-access seam — the second adapter that makes the
// seam real (real Supabase repos in prod, this fake in tests). Lets agent and
// controller tests assert against repo methods instead of hand-rolled `.from()`
// chains.
//
// Usage:
//   const { makeRepos, makeTaskRepo } = require('../helpers/fakeRepos');
//   const repos = makeRepos({ tasks: [{ id: 1, content: '…' }] });
//   await runTaskAgent('…', repos, false, {});
//   expect(repos.tasks.deleteById).toHaveBeenCalledWith(1);

// Read methods return the seeded rows; write methods are spies returning a
// Supabase-shaped result. Override any write result via opts.
function makeTaskRepo(opts = {}) {
    const {
        rows = [],
        createResult,
        updateResult,
        removeResult,
        completeResult,
        setCategoryResult,
        insertNextResult,
    } = opts;
    const firstRow = rows[0] || { id: 1 };
    return {
        listAll:          jest.fn(async () => rows),
        allBasic:         jest.fn(async () => rows),
        listWithSubtasks: jest.fn(async () => rows),
        listDueUpTo:      jest.fn(async () => rows),
        listOverdue:      jest.fn(async () => rows),
        recentTop:        jest.fn(async () => rows),
        firstOpen:        jest.fn(async () => rows),
        findByContent:    jest.fn(async () => rows),
        openForNudge:     jest.fn(async () => rows),
        addGraceful:      jest.fn(async () => {}),
        create:           jest.fn(async () => createResult        || { data: firstRow, error: null }),
        insertNext:       jest.fn(async () => insertNextResult    || { error: null }),
        complete:         jest.fn(async () => completeResult      || { error: null }),
        setCategory:      jest.fn(async () => setCategoryResult   || { error: null }),
        update:           jest.fn(async () => updateResult        || { data: firstRow, error: null }),
        deleteById:       jest.fn(async () => removeResult        || { error: null }),
    };
}

function makeReminderRepo(opts = {}) {
    const {
        rows = [],
        addResult, createResult, updateResult, removeResult,
        rescheduleResult, deleteManyResult,
    } = opts;
    const firstRow = rows[0] || { id: 1 };
    return {
        listUpcoming: jest.fn(async () => rows),
        nextUpcoming: jest.fn(async () => rows),
        listUnfired:  jest.fn(async () => rows),
        deleteByText: jest.fn(async () => rows),
        add:          jest.fn(async () => addResult        || { error: null }),
        create:       jest.fn(async () => createResult     || { data: firstRow, error: null }),
        update:       jest.fn(async () => updateResult     || { data: firstRow, error: null }),
        reschedule:   jest.fn(async () => rescheduleResult || { error: null }),
        deleteById:   jest.fn(async () => removeResult     || { error: null }),
        deleteMany:   jest.fn(async () => deleteManyResult || { error: null }),
    };
}

function makeMemoryRepo(opts = {}) {
    const { rows = [], insertResult, updateResult } = opts;
    return {
        findByContent:   jest.fn(async () => rows),
        allContents:     jest.fn(async () => rows.map(r => r.content)),
        insert:          jest.fn(async () => insertResult || rows),
        update:          jest.fn(async () => updateResult || { error: null }),
        deleteByContent: jest.fn(async () => rows),
        expiredByScope:  jest.fn(async () => rows),
        deleteMany:      jest.fn(async () => ({ error: null })),
    };
}

function makeNoteRepo(opts = {}) {
    const { rows = [], addResult } = opts;
    return {
        add:            jest.fn(async () => (addResult !== undefined ? addResult : (rows[0] || null))),
        listRecent:     jest.fn(async () => rows),
        search:         jest.fn(async () => rows),
        deleteMatching: jest.fn(async () => rows),
    };
}

function makeShoppingRepo(opts = {}) {
    const { rows = [], addResult } = opts;
    return {
        add:            jest.fn(async () => addResult || { error: null }),
        listOpen:       jest.fn(async () => rows),
        deleteMatching: jest.fn(async () => rows),
    };
}

function makeHabitRepo(opts = {}) {
    const { habits = [], doneDates = [], addResult, deactivateResult, logResult } = opts;
    return {
        findActiveByName: jest.fn(async () => habits),
        listActive:       jest.fn(async () => habits),
        add:              jest.fn(async () => addResult        || { error: null }),
        deactivate:       jest.fn(async () => deactivateResult || { error: null }),
        logToday:         jest.fn(async () => logResult        || { error: null }),
        doneDates:        jest.fn(async () => doneDates),
    };
}

function makeProjectRepo(opts = {}) {
    const {
        projects = [], milestones = [], tasks = [], openMilestones = [],
        backlog = [], upcomingTasks = [], upcomingMilestones = [],
        taskDone = [], milestoneCompleted = [], createResult,
    } = opts;
    const firstProject = projects[0] || { id: 'p1' };
    return {
        searchByName:            jest.fn(async () => projects),
        create:                  jest.fn(async () => createResult || { data: firstProject, error: null }),
        listAll:                 jest.fn(async () => projects),
        getById:                 jest.fn(async () => projects[0] || null),
        countsForProjects:       jest.fn(async () => ({ tasks, milestones })),
        detail:                  jest.fn(async () => ({ milestones, tasks, reminders: [], notes: [], sprints: [] })),
        insightsData:            jest.fn(async () => ({ tasks, milestones, sprints: [] })),
        createMilestone:         jest.fn(async () => ({ data: milestones[0] || { id: 'm1' }, error: null })),
        updateMilestoneScoped:   jest.fn(async () => ({ data: milestones[0] || { id: 'm1' }, error: null })),
        removeMilestoneScoped:   jest.fn(async () => ({ error: null })),
        listNonArchived:         jest.fn(async () => projects),
        listActive:              jest.fn(async () => projects),
        listActiveOrPaused:      jest.fn(async () => projects),
        update:                  jest.fn(async () => ({ data: firstProject, error: null })),
        remove:                  jest.fn(async () => ({ error: null })),
        taskDoneFlags:           jest.fn(async () => taskDone),
        milestoneCompletedFlags: jest.fn(async () => milestoneCompleted),
        listMilestones:          jest.fn(async () => milestones),
        addMilestone:            jest.fn(async () => ({ error: null })),
        findOpenMilestones:      jest.fn(async () => openMilestones),
        completeMilestone:       jest.fn(async () => ({ error: null })),
        upcomingMilestones:      jest.fn(async () => upcomingMilestones),
        listTasks:               jest.fn(async () => tasks),
        addTask:                 jest.fn(async () => ({ error: null })),
        sprintBacklog:           jest.fn(async () => backlog),
        upcomingTasks:           jest.fn(async () => upcomingTasks),
        addReminder:             jest.fn(async () => ({ error: null })),
    };
}

function makeSubtaskRepo(opts = {}) {
    const { rows = [], addResult, updateResult, removeResult } = opts;
    const firstRow = rows[0] || { id: 1 };
    return {
        listForParent: jest.fn(async () => rows),
        add:           jest.fn(async () => addResult    || { data: firstRow, error: null }),
        updateScoped:  jest.fn(async () => updateResult || { data: firstRow, error: null }),
        removeScoped:  jest.fn(async () => removeResult || { error: null }),
    };
}

function makeContactRepo(opts = {}) {
    const { rows = [], createResult, updateResult, removeResult } = opts;
    const firstRow = rows[0] || { id: 1 };
    return {
        listByName:  jest.fn(async () => rows),
        searchByName: jest.fn(async () => rows),
        create:      jest.fn(async () => createResult || { data: firstRow, error: null }),
        updateById:  jest.fn(async () => updateResult || { data: firstRow, error: null }),
        removeById:  jest.fn(async () => removeResult || { error: null }),
    };
}

function makeSurveyRepo(opts = {}) {
    const { rows = [], insertError = null } = opts;
    return {
        recentCompleted:              jest.fn(async () => rows),
        recentQuestionIds:            jest.fn(async () => rows),
        insertGraceful:               jest.fn(async () => ({ error: insertError })),
        historyForUser:               jest.fn(async () => rows),
        responsesForUser:             jest.fn(async () => rows),
        recentResponsesById:          jest.fn(async () => rows),
        recentResponsesWithDateById:  jest.fn(async () => rows),
        lastForUser:                  jest.fn(async () => rows),
    };
}

function makeSprintRepo(opts = {}) {
    const { rows = [], createResult, updateResult, removeResult, activeOthers = [] } = opts;
    const firstRow = rows[0] || { id: 'sp1' };
    return {
        listForProject: jest.fn(async () => rows),
        create:         jest.fn(async () => createResult || { data: firstRow, error: null }),
        updateScoped:   jest.fn(async () => updateResult || { data: firstRow, error: null }),
        removeScoped:   jest.fn(async () => removeResult || { error: null }),
        activeOthers:   jest.fn(async () => activeOthers),
        releaseTasks:   jest.fn(async () => ({ error: null })),
    };
}

function makeProfileRepo(opts = {}) {
    const { rows = [], updateResult, createResult, removeResult, latestError } = opts;
    const firstRow = rows[0] || { id: 'default' };
    return {
        latest:            jest.fn(async () => { if (latestError) throw latestError; return rows; }),
        update:            jest.fn(async () => updateResult || { data: firstRow, error: null }),
        create:            jest.fn(async () => createResult || { data: firstRow, error: null }),
        removeById:        jest.fn(async () => removeResult || { error: null }),
        saveCalendarToken: jest.fn(async () => ({ error: null })),
    };
}

function makeTelemetryRepo(opts = {}) {
    const { rows = [], recordError = null } = opts;
    return {
        record:       jest.fn(async () => ({ error: recordError })),
        recentEvents: jest.fn(async () => rows),
    };
}

function makeMetricsRepo(opts = {}) {
    const { rows = [] } = opts;
    return {
        insertBatch: jest.fn(async () => ({ error: null })),
        recentSince: jest.fn(async () => rows),
    };
}

function makeDeviceRepo(opts = {}) {
    const { rows = [] } = opts;
    return {
        upsertToken:  jest.fn(async () => ({ error: null })),
        list:         jest.fn(async () => rows),
        deleteTokens: jest.fn(async () => ({ error: null })),
    };
}

function makeCronRepo(opts = {}) {
    const { lastOk = null } = opts;
    return {
        markOk:    jest.fn(() => Promise.resolve({ error: null })),
        markError: jest.fn(() => Promise.resolve({ error: null })),
        lastOkAt:  jest.fn(async () => lastOk),
    };
}

function makeChatRepo(opts = {}) {
    const { rows = [], addResult, count = 0 } = opts;
    return {
        recentTail:      jest.fn(async () => rows),
        add:             jest.fn(async () => addResult || { error: null }),
        recentForSearch: jest.fn(async () => rows),
        countForChat:    jest.fn(async () => count),
        deleteForChat:   jest.fn(async () => ({ error: null })),
    };
}

function makeSummaryRepo(opts = {}) {
    const { summary = '', meta = {} } = opts;
    return {
        get:     jest.fn(async () => summary),
        getMeta: jest.fn(async () => meta),
        upsert:  jest.fn(async () => ({ error: null })),
    };
}

function makeTableRepo(rows = []) {
    return {
        all:      jest.fn(async () => rows),
        findLike: jest.fn(async () => rows),
        insert:   jest.fn(async () => ({ data: rows[0] || { id: 1 }, error: null })),
        update:   jest.fn(async () => ({ data: rows[0] || { id: 1 }, error: null })),
        remove:   jest.fn(async () => ({ error: null })),
    };
}

// Build a repos bundle seeded per table. Generic tables share one fake.
function makeRepos(tableData = {}) {
    const generic = {};
    return {
        tasks: makeTaskRepo({ rows: tableData.tasks || [] }),
        reminders: makeReminderRepo({ rows: tableData.reminders || [] }),
        memories: makeMemoryRepo({ rows: tableData.memories || [] }),
        notes: makeNoteRepo({ rows: tableData.notes || [] }),
        shopping: makeShoppingRepo({ rows: tableData.shopping || [] }),
        habits: makeHabitRepo({
            habits: tableData.habits || [],
            doneDates: (tableData.habit_logs || []).map(l => l.date),
        }),
        projects: makeProjectRepo({ projects: tableData.projects || [] }),
        subtasks: makeSubtaskRepo({ rows: tableData.subtasks || [] }),
        contacts: makeContactRepo({ rows: tableData.contacts || [] }),
        chat: makeChatRepo({ rows: tableData.chat_history || [] }),
        summaries: makeSummaryRepo({}),
        surveys: makeSurveyRepo({ rows: tableData.user_surveys || [] }),
        profile: makeProfileRepo({ rows: tableData.user_profiles || [] }),
        sprints: makeSprintRepo({ rows: tableData.project_sprints || [] }),
        cron: makeCronRepo({ lastOk: tableData._cronLastOk || null }),
        telemetry: makeTelemetryRepo({ rows: tableData.smart_telemetry_events || [] }),
        metrics: makeMetricsRepo({ rows: tableData.agent_metrics || [] }),
        devices: makeDeviceRepo({ rows: tableData.device_tokens || [] }),
        e2e: {
            listRecent: jest.fn(async () => tableData.e2e_reports || []),
            byRun: jest.fn(async () => tableData.e2e_reports || []),
            byRunAndFingerprints: jest.fn(async () => tableData.e2e_reports || []),
            deleteRun: jest.fn(async () => ({ error: null })),
            markDone: jest.fn(async () => ({ error: null })),
            recentScores: jest.fn(async () => tableData.e2e_reports || []),
            recentFailures: jest.fn(async () => tableData.e2e_reports || []),
        },
        stats: { dashboardCounts: jest.fn(async () => ({
            chat: { total: 0, today: 0 },
            tasks: { total: 0, done: 0, pending: 0, byCategory: {} },
            reminders: { total: 0, active: 0 },
            memories: { total: 0 }, notes: { total: 0 }, shopping: { total: 0, checked: 0 },
        })) },
        table(name) {
            return generic[name] || (generic[name] = makeTableRepo(tableData[name] || []));
        },
    };
}

module.exports = { makeRepos, makeTaskRepo, makeReminderRepo, makeMemoryRepo, makeNoteRepo, makeShoppingRepo, makeHabitRepo, makeProjectRepo, makeSubtaskRepo, makeContactRepo, makeChatRepo, makeSummaryRepo, makeSurveyRepo, makeProfileRepo, makeSprintRepo, makeCronRepo, makeTelemetryRepo, makeMetricsRepo, makeDeviceRepo, makeTableRepo };
