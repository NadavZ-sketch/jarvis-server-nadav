-- Track when a user actually completed a survey and which questions were asked.
-- Used by /survey-check to (a) enforce a per-user cooldown so the same user is
-- not re-prompted within N hours, and (b) avoid re-asking questions already
-- answered recently.

DO $$
BEGIN
  IF to_regclass('public.user_surveys') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='user_surveys' AND column_name='completed_at'
    ) THEN
      ALTER TABLE public.user_surveys ADD COLUMN completed_at TIMESTAMPTZ;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='user_surveys' AND column_name='question_ids'
    ) THEN
      ALTER TABLE public.user_surveys ADD COLUMN question_ids TEXT[] DEFAULT '{}';
    END IF;

    -- Backfill completed_at from created_at so existing rows count as completed.
    UPDATE public.user_surveys
       SET completed_at = created_at
     WHERE completed_at IS NULL;

    CREATE INDEX IF NOT EXISTS user_surveys_completed_at_idx
      ON public.user_surveys (user_name, completed_at DESC);
  END IF;
END$$;
