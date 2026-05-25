-- Create projects table
CREATE TABLE IF NOT EXISTS projects (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name        text NOT NULL,
  description text,
  status      text DEFAULT 'active'
                CHECK (status IN ('active','paused','completed','archived')),
  priority    text DEFAULT 'medium'
                CHECK (priority IN ('low','medium','high','critical')),
  start_date  date,
  due_date    date,
  color       text DEFAULT '#6366f1',
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

-- Create project milestones table
CREATE TABLE IF NOT EXISTS project_milestones (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id   uuid REFERENCES projects(id) ON DELETE CASCADE,
  title        text NOT NULL,
  due_date     date,
  completed    boolean DEFAULT false,
  completed_at timestamptz,
  created_at   timestamptz DEFAULT now()
);

-- Add project_id foreign key to existing tables
ALTER TABLE tasks     ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id) ON DELETE SET NULL;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id) ON DELETE SET NULL;
ALTER TABLE notes     ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id) ON DELETE SET NULL;
