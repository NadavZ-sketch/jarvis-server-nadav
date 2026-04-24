-- Supabase performance indexes for Jarvis
-- Run in Supabase SQL Editor → once only (idempotent with IF NOT EXISTS)

-- chat_history: main sort column used by every loadChatHistory() call
CREATE INDEX IF NOT EXISTS idx_chat_history_created_at
    ON chat_history (created_at DESC);

-- reminders: cron checks fire non-fired reminders ordered by time
CREATE INDEX IF NOT EXISTS idx_reminders_fired_scheduled
    ON reminders (fired, scheduled_time ASC)
    WHERE fired = false;

-- tasks: listing always sorts by created_at
CREATE INDEX IF NOT EXISTS idx_tasks_created_at
    ON tasks (created_at DESC);

-- memories: ilike search on content (%keyword%)
-- pg_trgm extension + GIN index is the only way to accelerate ilike
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_memories_content_trgm
    ON memories USING GIN (content gin_trgm_ops);

-- notes: ilike search + created_at sort
CREATE INDEX IF NOT EXISTS idx_notes_content_trgm
    ON notes USING GIN (content gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_notes_created_at
    ON notes (created_at DESC);

-- shopping_items: WHERE done = false is the hot path
CREATE INDEX IF NOT EXISTS idx_shopping_done_created
    ON shopping_items (done, created_at ASC)
    WHERE done = false;

-- contacts: sorted by name
CREATE INDEX IF NOT EXISTS idx_contacts_name
    ON contacts (name ASC);
