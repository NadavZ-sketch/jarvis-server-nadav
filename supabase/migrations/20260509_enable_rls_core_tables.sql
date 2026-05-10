-- Enable strict Row Level Security for core personal tables.
-- Safe version: every operation checks table existence first.

-- memories
DO $$
BEGIN
  IF to_regclass('public.memories') IS NOT NULL THEN
    ALTER TABLE public.memories ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS memories_select_own ON public.memories;
    DROP POLICY IF EXISTS memories_insert_own ON public.memories;
    DROP POLICY IF EXISTS memories_update_own ON public.memories;
    DROP POLICY IF EXISTS memories_delete_own ON public.memories;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='memories' AND column_name='user_id'
    ) THEN
      CREATE POLICY memories_select_own ON public.memories FOR SELECT USING (auth.uid() = user_id);
      CREATE POLICY memories_insert_own ON public.memories FOR INSERT WITH CHECK (auth.uid() = user_id);
      CREATE POLICY memories_update_own ON public.memories FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
      CREATE POLICY memories_delete_own ON public.memories FOR DELETE USING (auth.uid() = user_id);
    END IF;

    REVOKE ALL ON public.memories FROM anon;
  END IF;
END$$;

-- chat_history
DO $$
BEGIN
  IF to_regclass('public.chat_history') IS NOT NULL THEN
    ALTER TABLE public.chat_history ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS chat_history_select_own ON public.chat_history;
    DROP POLICY IF EXISTS chat_history_insert_own ON public.chat_history;
    DROP POLICY IF EXISTS chat_history_update_own ON public.chat_history;
    DROP POLICY IF EXISTS chat_history_delete_own ON public.chat_history;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='chat_history' AND column_name='user_id'
    ) THEN
      CREATE POLICY chat_history_select_own ON public.chat_history FOR SELECT USING (auth.uid() = user_id);
      CREATE POLICY chat_history_insert_own ON public.chat_history FOR INSERT WITH CHECK (auth.uid() = user_id);
      CREATE POLICY chat_history_update_own ON public.chat_history FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
      CREATE POLICY chat_history_delete_own ON public.chat_history FOR DELETE USING (auth.uid() = user_id);
    END IF;

    REVOKE ALL ON public.chat_history FROM anon;
  END IF;
END$$;

-- reminders
DO $$
BEGIN
  IF to_regclass('public.reminders') IS NOT NULL THEN
    ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS reminders_select_own ON public.reminders;
    DROP POLICY IF EXISTS reminders_insert_own ON public.reminders;
    DROP POLICY IF EXISTS reminders_update_own ON public.reminders;
    DROP POLICY IF EXISTS reminders_delete_own ON public.reminders;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='reminders' AND column_name='user_id'
    ) THEN
      CREATE POLICY reminders_select_own ON public.reminders FOR SELECT USING (auth.uid() = user_id);
      CREATE POLICY reminders_insert_own ON public.reminders FOR INSERT WITH CHECK (auth.uid() = user_id);
      CREATE POLICY reminders_update_own ON public.reminders FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
      CREATE POLICY reminders_delete_own ON public.reminders FOR DELETE USING (auth.uid() = user_id);
    END IF;

    REVOKE ALL ON public.reminders FROM anon;
  END IF;
END$$;
