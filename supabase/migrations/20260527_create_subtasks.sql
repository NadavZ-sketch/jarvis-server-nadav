-- Subtasks: a flat one-level checklist under a parent task.
-- Used by the smart-suggestions flow (a suggestion can become a subtask) and by
-- the completion guard (a task with open subtasks asks for confirmation before
-- it can be marked done).
CREATE TABLE IF NOT EXISTS subtasks (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  parent_task_id uuid REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
  content        text NOT NULL,
  done           boolean NOT NULL DEFAULT false,
  created_at     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS subtasks_parent_task_id_idx ON subtasks(parent_task_id);
