'use strict';

/**
 * Shared Supabase mock helpers for the test suite.
 *
 * Historically every test file hand-rolled its own `makeChain()` thenable (the
 * same ~15-line builder copy-pasted ~50 times). This module is the single source
 * of truth so the mocked query surface doesn't drift between files.
 *
 * Usage (matches the existing convention):
 *
 *   const { makeChain } = require('../helpers/supabaseMock');
 *   supabaseClient.from.mockImplementation(() => makeChain(rows));
 *
 *   // sequential calls with different results:
 *   supabaseClient.from
 *     .mockImplementationOnce(() => makeChain(null, { message: 'boom' }))
 *     .mockImplementationOnce(() => makeChain(rows));
 *
 *   // route .from(table) to per-table data:
 *   const supabase = makeSupabase({ tasks: taskRows, reminders: reminderRows });
 */

// A chainable, awaitable query-builder stub. Every chain method returns `this`
// so any call order resolves; awaiting the chain (or .single()/.maybeSingle())
// yields `{ data, error }`.
function makeChain(data = [], error = null) {
  const result = { data, error };
  const chain = {
    then(onF, onR) { return Promise.resolve(result).then(onF, onR); },
    catch(onR)     { return Promise.resolve(result).catch(onR); },
    finally(cb)    { return Promise.resolve(result).finally(cb); },
  };
  const CHAINABLE = [
    'select', 'insert', 'update', 'upsert', 'delete',
    'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'is', 'in',
    'ilike', 'like', 'match', 'filter', 'or', 'not', 'contains',
    'order', 'limit', 'range', 'single', 'maybeSingle',
  ];
  for (const m of CHAINABLE) chain[m] = jest.fn(() => chain);
  return chain;
}

// Build a Supabase client whose `.from(table)` returns a chain seeded with that
// table's rows (defaults to []). Pass `{ _error: {...} }` to force every chain
// to resolve with an error.
function makeSupabase(tableData = {}) {
  const { _error = null, ...tables } = tableData;
  return {
    from: jest.fn((table) => makeChain(tables[table] ?? [], _error)),
  };
}

module.exports = { makeChain, makeSupabase };
