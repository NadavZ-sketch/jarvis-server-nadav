-- docs/superpowers/migrations/prompt_library.sql
CREATE TABLE IF NOT EXISTS prompt_library (
  id         UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT    NOT NULL,
  content    TEXT    NOT NULL,
  version    INTEGER DEFAULT 1,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for listing by creation date (most common query: newest first).
CREATE INDEX IF NOT EXISTS prompt_library_created_at_idx ON prompt_library (created_at DESC);
