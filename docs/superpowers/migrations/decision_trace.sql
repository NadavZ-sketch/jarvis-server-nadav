-- docs/superpowers/migrations/decision_trace.sql
CREATE TABLE IF NOT EXISTS decision_trace (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id     TEXT,
  input       TEXT,
  intent      TEXT,
  candidates  JSONB,
  ambiguous   BOOLEAN,
  route_mode  TEXT,
  agent       TEXT,
  model       TEXT,
  duration_ms INTEGER,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Keep table lean: auto-delete rows older than 30 days via pg_cron or manual cleanup.
-- Index for the dashboard query (latest N rows).
CREATE INDEX IF NOT EXISTS decision_trace_created_at_idx ON decision_trace (created_at DESC);
