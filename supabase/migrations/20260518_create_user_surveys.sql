CREATE TABLE IF NOT EXISTS public.user_surveys (
  id          BIGSERIAL PRIMARY KEY,
  user_name   TEXT        NOT NULL,
  responses   TEXT,
  summary     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_surveys_user_name_idx ON public.user_surveys (user_name, created_at DESC);
