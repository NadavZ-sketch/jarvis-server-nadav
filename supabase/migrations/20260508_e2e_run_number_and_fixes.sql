-- Adds sequential run numbering + per-finding fix tracking to e2e_reports.
ALTER TABLE e2e_reports ADD COLUMN IF NOT EXISTS run_number INTEGER;
ALTER TABLE e2e_reports ADD COLUMN IF NOT EXISTS fixed_at   TIMESTAMPTZ;
ALTER TABLE e2e_reports ADD COLUMN IF NOT EXISTS fix_note   TEXT;

CREATE INDEX IF NOT EXISTS e2e_reports_run_number_idx ON e2e_reports(run_number);
