-- Add recurrence support to tasks
-- Valid values: 'daily', 'weekly', 'monthly', NULL = one-time
-- Mirrors the reminders.recurrence column (20260429_add_recurrence_to_reminders.sql).
-- When a recurring task is completed, the task agent creates the next occurrence
-- with the due_date advanced by the recurrence interval.
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS recurrence TEXT DEFAULT NULL
    CHECK (recurrence IN ('daily', 'weekly', 'monthly'));
