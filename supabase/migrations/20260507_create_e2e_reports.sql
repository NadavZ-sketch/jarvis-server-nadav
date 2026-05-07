-- E2E testing agent: per-finding rows for each test run
CREATE TABLE IF NOT EXISTS e2e_reports (
  id             BIGSERIAL PRIMARY KEY,
  run_id         UUID NOT NULL,
  category       TEXT NOT NULL CHECK (category IN
                 ('security','bug','performance','reliability','ui','ux_backend','quality','accessibility')),
  severity       TEXT NOT NULL CHECK (severity IN ('critical','high','medium','low')),
  target         TEXT NOT NULL,
  finding        TEXT NOT NULL,
  recommendation TEXT,
  latency_ms     INTEGER,
  score          INTEGER,
  fingerprint    TEXT,
  status         TEXT NOT NULL DEFAULT 'new'
                 CHECK (status IN ('new','regression','flaky','known')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS e2e_reports_run_id_idx      ON e2e_reports(run_id);
CREATE INDEX IF NOT EXISTS e2e_reports_severity_idx    ON e2e_reports(severity);
CREATE INDEX IF NOT EXISTS e2e_reports_fingerprint_idx ON e2e_reports(fingerprint);
CREATE INDEX IF NOT EXISTS e2e_reports_created_at_idx  ON e2e_reports(created_at DESC);
