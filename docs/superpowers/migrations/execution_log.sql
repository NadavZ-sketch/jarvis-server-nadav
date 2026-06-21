-- docs/superpowers/migrations/execution_log.sql
CREATE TABLE IF NOT EXISTS execution_log (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cmd         TEXT,
  agent       TEXT,
  model       TEXT,
  duration_ms INTEGER,
  status      TEXT        CHECK (status IN ('ok', 'fail')),
  error       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Keep table lean: auto-delete rows older than 30 days via pg_cron or manual cleanup.
-- Index for the dashboard query (latest N rows).
CREATE INDEX IF NOT EXISTS execution_log_created_at_idx ON execution_log (created_at DESC);
