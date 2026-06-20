CREATE TABLE IF NOT EXISTS test_cases (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT        NOT NULL,
  turns         JSONB       NOT NULL,
  source        TEXT        DEFAULT 'recorded',
  recorded_at   TIMESTAMPTZ,
  last_run      TIMESTAMPTZ,
  last_status   TEXT,
  last_run_diff JSONB,
  created_at    TIMESTAMPTZ DEFAULT now()
);
