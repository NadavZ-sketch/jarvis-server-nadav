-- Habit tracking: recurring personal habits the user wants to build, plus a
-- per-day completion log used to compute streaks.

CREATE TABLE IF NOT EXISTS habits (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name        text NOT NULL,
  schedule    text DEFAULT 'daily',   -- free text: 'daily', 'weekly', etc.
  active      boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS habit_logs (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  habit_id    uuid REFERENCES habits(id) ON DELETE CASCADE,
  date        date NOT NULL,
  done        boolean DEFAULT true,
  created_at  timestamptz DEFAULT now(),
  UNIQUE (habit_id, date)
);

CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_date ON habit_logs (habit_id, date);
