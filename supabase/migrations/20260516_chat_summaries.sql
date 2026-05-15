-- Rolling conversation summaries for mid-term memory
-- Stores an LLM-generated Hebrew summary per chat session,
-- updated every ~8 turns in the background.

CREATE TABLE IF NOT EXISTS public.chat_summaries (
  chat_id       text PRIMARY KEY,
  summary       text        NOT NULL DEFAULT '',
  topics        text[]      NOT NULL DEFAULT '{}',
  turns_covered int         NOT NULL DEFAULT 0,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Scope field on memories: long_term | session | recent
-- long_term = stable personal facts (existing default)
-- session   = relevant to current week, deleted after 7 days
-- recent    = ephemeral, deleted after 24 hours
ALTER TABLE public.memories
  ADD COLUMN IF NOT EXISTS scope text NOT NULL DEFAULT 'long_term';

CREATE INDEX IF NOT EXISTS idx_memories_scope ON public.memories (scope, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_summaries_updated ON public.chat_summaries (updated_at DESC);
