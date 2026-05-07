-- E2E testing agent: self-learned probes that grow over time
CREATE TABLE IF NOT EXISTS e2e_learned_probes (
  id             BIGSERIAL PRIMARY KEY,
  kind           TEXT NOT NULL CHECK (kind IN ('api','static','flutter','ux')),
  target         TEXT,
  query          TEXT,
  file_pattern   TEXT,
  reason         TEXT,
  hits           INTEGER NOT NULL DEFAULT 0,
  misses         INTEGER NOT NULL DEFAULT 0,
  auto_generated BOOLEAN NOT NULL DEFAULT true,
  active         BOOLEAN NOT NULL DEFAULT true,
  last_used_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS e2e_learned_probes_active_idx ON e2e_learned_probes(active, kind);
CREATE INDEX IF NOT EXISTS e2e_learned_probes_used_idx   ON e2e_learned_probes(last_used_at);
