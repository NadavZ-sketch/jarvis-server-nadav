CREATE TABLE IF NOT EXISTS public.daily_briefings (
  date        DATE        PRIMARY KEY,
  content     TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
