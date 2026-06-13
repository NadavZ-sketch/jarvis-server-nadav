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
        listWithSubtasks: jest.fn(async () => rows),
        listDueUpTo:      jest.fn(async () => rows),
        listOverdue:      jest.fn(async () => rows),
        recentTop:        jest.fn(async () => rows),
        firstOpen:        jest.fn(async () => rows),
        findByContent:    jest.fn(async () => rows),
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
        table(name) {
            return generic[name] || (generic[name] = makeTableRepo(tableData[name] || []));
        },
    };
}

module.exports = { makeRepos, makeTaskRepo, makeReminderRepo, makeMemoryRepo, makeNoteRepo, makeTableRepo };
