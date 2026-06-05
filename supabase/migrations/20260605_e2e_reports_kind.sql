-- Distinguish full end-to-end runs from standalone code-error scans so both
-- can live in the same reports list and be labeled in the UI.
-- 'e2e'       = full end-to-end run (all probes)
-- 'code_scan' = standalone code-error scan ("סרוק שגיאות קוד")
ALTER TABLE e2e_reports
  ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'e2e'
  CHECK (kind IN ('e2e', 'code_scan'));

CREATE INDEX IF NOT EXISTS e2e_reports_kind_idx ON e2e_reports(kind);
