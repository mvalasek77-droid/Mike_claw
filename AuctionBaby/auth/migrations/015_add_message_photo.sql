-- Photo messages: store an optional R2/public photo URL per message.
-- Client sends { text: "", photo: "<url>" }; at least one of text/photo
-- must be non-empty. text stays NOT NULL (empty string = photo-only).
ALTER TABLE messages ADD COLUMN photo TEXT;