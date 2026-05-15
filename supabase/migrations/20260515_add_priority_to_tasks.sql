-- Add priority field to tasks table
-- Valid values: 'high', 'medium', 'low' (default 'medium', backward compatible)
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT 'medium'
    CHECK (priority IN ('high', 'medium', 'low'));
