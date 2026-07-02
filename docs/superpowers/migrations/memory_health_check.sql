-- supabase/migrations/20260702_memory_health_check.sql
-- Memory health check: persisted category on memories + a findings table for
-- the batch health scan (duplicates, conflicts, category mismatches,
-- stale/thin content, Supabase<->Pinecone sync gaps).

ALTER TABLE memories ADD COLUMN IF NOT EXISTS category TEXT;

CREATE TABLE IF NOT EXISTS memory_health_findings (
    id                 UUID        NOT NULL DEFAULT gen_random_uuid(),
    type               TEXT        NOT NULL CHECK (type IN (
                            'duplicate', 'conflict', 'category_mismatch',
                            'stale', 'thin_content', 'orphaned_vector', 'orphaned_row'
                        )),
    memory_id          BIGINT      NOT NULL,
    related_memory_id  BIGINT,
    suggested_action   TEXT        NOT NULL CHECK (suggested_action IN (
                            'delete', 'merge', 'move', 'archive', 'resync'
                        )),
    suggested_payload  JSONB,
    score              NUMERIC,
    status             TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    content_hash       TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at        TIMESTAMPTZ,
    CONSTRAINT memory_health_findings_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS memory_health_findings_status_idx ON memory_health_findings (status);
CREATE INDEX IF NOT EXISTS memory_health_findings_lookup_idx ON memory_health_findings (type, memory_id, related_memory_id);

COMMENT ON COLUMN memories.category                        IS 'One of עבודה/משפחה/בריאות/תחביב/כללי, LLM-classified at write time; NULL for rows created before this feature';
COMMENT ON TABLE  memory_health_findings                    IS 'Findings from the batch memory-health scan (services/memoryHealthCheck.js)';
COMMENT ON COLUMN memory_health_findings.related_memory_id  IS 'Second memory in a pair finding (duplicate/conflict); NULL for single-memory findings';
COMMENT ON COLUMN memory_health_findings.content_hash       IS 'Hash of the involved memory content(s) at scan time — lets a dismissed finding resurface only if content later changed';
