-- Add methodology support to projects
ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS methodology text DEFAULT 'kanban'
    CHECK (methodology IN ('kanban','scrum','eisenhower','gantt')),
  ADD COLUMN IF NOT EXISTS method_config jsonb DEFAULT '{}'::jsonb;

-- Sprints table for Scrum methodology
CREATE TABLE IF NOT EXISTS project_sprints (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id      uuid REFERENCES projects(id) ON DELETE CASCADE NOT NULL,
  name            text NOT NULL,
  goal            text,
  start_date      date NOT NULL,
  end_date        date NOT NULL,
  status          text DEFAULT 'planned' CHECK (status IN ('planned','active','completed')),
  capacity_points integer DEFAULT 0,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS project_sprints_project_id_idx ON project_sprints(project_id);
CREATE INDEX IF NOT EXISTS project_sprints_status_idx ON project_sprints(status);

-- Add methodology-specific columns to tasks
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS story_points    integer DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS sprint_id       uuid REFERENCES project_sprints(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS kanban_column   text DEFAULT 'todo'
    CHECK (kanban_column IN ('todo','in_progress','review','done')),
  ADD COLUMN IF NOT EXISTS eisenhower_quad text DEFAULT NULL
    CHECK (eisenhower_quad IN ('q1','q2','q3','q4') OR eisenhower_quad IS NULL),
  ADD COLUMN IF NOT EXISTS task_start_date date DEFAULT NULL;

CREATE INDEX IF NOT EXISTS tasks_sprint_id_idx ON tasks(sprint_id);
CREATE INDEX IF NOT EXISTS tasks_kanban_column_idx ON tasks(kanban_column);
