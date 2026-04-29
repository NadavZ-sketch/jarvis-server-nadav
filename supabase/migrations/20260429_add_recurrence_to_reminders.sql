-- Add recurrence support to reminders
-- Valid values: 'daily', 'weekly', 'monthly', NULL = one-time
ALTER TABLE reminders
  ADD COLUMN IF NOT EXISTS recurrence TEXT DEFAULT NULL
    CHECK (recurrence IN ('daily', 'weekly', 'monthly'));
