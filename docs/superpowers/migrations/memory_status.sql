ALTER TABLE memories ADD COLUMN IF NOT EXISTS status text DEFAULT 'approved';
CREATE INDEX IF NOT EXISTS memories_status_idx ON memories(status);
