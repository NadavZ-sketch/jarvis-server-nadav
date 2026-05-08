-- Add chat_id column to track individual chat sessions
-- This allows separating messages from different conversations
ALTER TABLE chat_history
ADD COLUMN chat_id TEXT NOT NULL DEFAULT 'default-session' AFTER text;

-- Create index for faster filtering by chat_id
CREATE INDEX idx_chat_history_chat_id ON chat_history(chat_id, created_at DESC);
