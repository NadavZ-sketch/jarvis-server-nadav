-- Cron job run tracking — enables boot-time catch-up and health monitoring.
-- One row per named cron job; upserted on every run (success or error).

CREATE TABLE IF NOT EXISTS cron_runs (
    job_name    TEXT        NOT NULL,
    last_ok_at  TIMESTAMPTZ,
    last_err_at TIMESTAMPTZ,
    last_error  TEXT,
    CONSTRAINT cron_runs_pkey PRIMARY KEY (job_name)
);

COMMENT ON TABLE  cron_runs            IS 'Last-run timestamps for scheduled cron jobs';
COMMENT ON COLUMN cron_runs.job_name   IS 'Stable identifier, e.g. morning_briefing, proactive_push';
COMMENT ON COLUMN cron_runs.last_ok_at IS 'Timestamp of last successful run';
COMMENT ON COLUMN cron_runs.last_err_at IS 'Timestamp of last failed run';
COMMENT ON COLUMN cron_runs.last_error  IS 'Error message from the last failed run (truncated)';
