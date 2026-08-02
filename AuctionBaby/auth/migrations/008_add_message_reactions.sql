-- Migration 008 — slice: server-side reactions.
-- One reaction per message. Overwrites are visible to both sides — matches
-- the existing local model where `ChatMessage.reaction: String?` is a single
-- optional emoji. A future per-viewer model would replace this with a
-- (message_id, from_id, emoji) join table; for MVP the single column keeps
-- the schema minimal and the wire small.

ALTER TABLE messages ADD COLUMN reaction TEXT;
