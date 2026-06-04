-- Track how each E2E finding was produced so reports can separate
-- hard measurements (HTTP/latency/regex) from LLM evaluations (which can err).
-- 'measured'  = deterministic / verifiable
-- 'evaluated' = LLM judgment, needs validation before acting on it
ALTER TABLE e2e_reports
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'measured'
  CHECK (source IN ('measured', 'evaluated'));

CREATE INDEX IF NOT EXISTS e2e_reports_source_idx ON e2e_reports(source);
