-- System events log — replaces silent console-only logging
-- Written by services/systemLog.js on every warn/error/critical event.
-- Admins can review via the Control Center dashboard.

CREATE TABLE IF NOT EXISTS system_events (
    id          BIGSERIAL   NOT NULL,
    level       TEXT        NOT NULL CHECK (level IN ('info', 'warn', 'error', 'critical')),
    source      TEXT        NOT NULL,
    message     TEXT        NOT NULL,
    stack       TEXT,
    meta        JSONB,
    fingerprint TEXT,
    acked       BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT system_events_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS system_events_created_at_idx  ON system_events (created_at DESC);
CREATE INDEX IF NOT EXISTS system_events_level_idx       ON system_events (level);
CREATE INDEX IF NOT EXISTS system_events_fingerprint_idx ON system_events (fingerprint);
CREATE INDEX IF NOT EXISTS system_events_acked_idx       ON system_events (acked) WHERE acked = false;

COMMENT ON TABLE  system_events              IS 'Persistent log of server-side errors and critical events';
COMMENT ON COLUMN system_events.level        IS 'info | warn | error | critical';
COMMENT ON COLUMN system_events.source       IS 'Module:function, e.g. cron:morning_briefing';
COMMENT ON COLUMN system_events.fingerprint  IS 'Dedup key: source + first line of message';
COMMENT ON COLUMN system_events.acked        IS 'True once the user has acknowledged this event in the dashboard';
