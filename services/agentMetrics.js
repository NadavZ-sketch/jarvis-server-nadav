'use strict';

// Per-agent latency + intent-classification metrics.
// Records into an in-memory buffer for instant reads, and flushes batches to
// the Supabase `agent_metrics` table so data survives a server restart.
// Degrades gracefully to in-memory only when the table/connection is absent.

const FLUSH_INTERVAL_MS = 30_000;
const FLUSH_THRESHOLD = 40;
const WINDOW_MS = 24 * 60 * 60 * 1000;
const READ_LIMIT = 5000;

let _repos = null;
let _flushTimer = null;

// Rows recorded since the last successful flush (disjoint from what's in the DB).
let pending = [];
// All-time aggregate for this process — the fallback used when the DB is down.
const lifetime = new Map(); // agent -> { sum, count, lastCalledAt }
const lifetimeIntent = { fast: 0, llm: 0 };

function _bumpLifetime(agent, ms, intentMode) {
  const cur = lifetime.get(agent) || { sum: 0, count: 0, lastCalledAt: null };
  cur.sum += ms;
  cur.count += 1;
  cur.lastCalledAt = new Date().toISOString();
  lifetime.set(agent, cur);
  if (intentMode === 'fast') lifetimeIntent.fast += 1;
  else if (intentMode === 'llm') lifetimeIntent.llm += 1;
}

function init(repos) {
  _repos = repos || null;
  if (!_flushTimer && _repos) {
    _flushTimer = setInterval(() => { flush().catch(() => {}); }, FLUSH_INTERVAL_MS);
    if (_flushTimer.unref) _flushTimer.unref();
  }
}

function record(agentName, ms, intentMode) {
  if (!agentName || typeof ms !== 'number' || !isFinite(ms)) return;
  const row = {
    agent: agentName,
    ms: Math.round(ms),
    intent_mode: intentMode || null,
    created_at: new Date().toISOString(),
  };
  pending.push(row);
  _bumpLifetime(agentName, row.ms, intentMode);
  if (pending.length >= FLUSH_THRESHOLD) flush().catch(() => {});
}

async function flush() {
  if (!_repos || pending.length === 0) return;
  const batch = pending;
  pending = [];
  try {
    const { error } = await _repos.metrics.insertBatch(batch);
    if (error) throw error;
  } catch (e) {
    // Re-queue so nothing is lost; cap to avoid unbounded growth if DB stays down.
    pending = batch.concat(pending).slice(-500);
  }
}

function _aggregateRows(rows) {
  const byAgent = new Map();
  const intent = { fast: 0, llm: 0 };
  for (const r of rows) {
    const agent = r.agent;
    const ms = Number(r.ms) || 0;
    const cur = byAgent.get(agent) || { sum: 0, count: 0, lastCalledAt: null };
    cur.sum += ms;
    cur.count += 1;
    if (!cur.lastCalledAt || r.created_at > cur.lastCalledAt) cur.lastCalledAt = r.created_at;
    byAgent.set(agent, cur);
    if (r.intent_mode === 'fast') intent.fast += 1;
    else if (r.intent_mode === 'llm') intent.llm += 1;
  }
  return { byAgent, intent };
}

function _format(byAgent, intent) {
  const latency = [...byAgent.entries()]
    .map(([agent, { sum, count, lastCalledAt }]) => ({
      agent,
      avgMs: Math.round(sum / count),
      count,
      lastCalledAt: lastCalledAt || null,
    }))
    .sort((a, b) => b.count - a.count);
  return { latency, intent };
}

function stop() {
  if (_flushTimer) {
    clearInterval(_flushTimer);
    _flushTimer = null;
  }
  _repos = null;
  pending = [];
}

async function snapshot() {
  // Fallback aggregate (always available).
  const fallback = () => _format(new Map(lifetime), { ...lifetimeIntent });

  if (!_repos) return fallback();

  try {
    const sinceISO = new Date(Date.now() - WINDOW_MS).toISOString();
    const data = await _repos.metrics.recentSince(sinceISO, READ_LIMIT);

    const { byAgent, intent } = _aggregateRows(data || []);
    // Merge unflushed pending rows so the snapshot reflects the very latest calls.
    for (const r of pending) {
      const cur = byAgent.get(r.agent) || { sum: 0, count: 0, lastCalledAt: null };
      cur.sum += r.ms;
      cur.count += 1;
      if (!cur.lastCalledAt || r.created_at > cur.lastCalledAt) cur.lastCalledAt = r.created_at;
      byAgent.set(r.agent, cur);
      if (r.intent_mode === 'fast') intent.fast += 1;
      else if (r.intent_mode === 'llm') intent.llm += 1;
    }
    return _format(byAgent, intent);
  } catch (_) {
    return fallback();
  }
}

module.exports = { init, record, flush, snapshot, stop };
