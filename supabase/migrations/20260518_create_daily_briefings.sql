CREATE TABLE IF NOT EXISTS public.daily_briefings (
  briefing_date  DATE        PRIMARY KEY,
  content        TEXT        NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
