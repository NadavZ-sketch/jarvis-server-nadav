-- Add 'planning' as a valid project status.
-- The projects UI (filters, labels, colors) already references 'planning', but
-- the original CHECK constraint rejected it, so projects could never be saved
-- with that status. This migration widens the constraint to include it.

ALTER TABLE projects DROP CONSTRAINT IF EXISTS projects_status_check;

ALTER TABLE projects
  ADD CONSTRAINT projects_status_check
  CHECK (status IN ('active', 'planning', 'paused', 'completed', 'archived'));
