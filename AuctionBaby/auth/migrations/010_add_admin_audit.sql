-- Migration 010 — admin audit log (Batch Q).
-- One row per admin action, so "who unverified whom and when" is answerable
-- for accountability + reversibility. Referenced by GET /admin/audit and
-- written from every /admin/* handler that mutates state.
--
-- actor_id: admin session's userId (from ensureAdminSession).
-- action:   verify | unverify | delete_user | resolve_report:actioned |
--           resolve_report:reviewed | resolve_report:dismissed.
-- target_id: the user or report the action was on. Nullable for actions
--   that don't have a single subject (future: bulk imports, etc).
-- note: free-form operator note, max 300 chars.

CREATE TABLE IF NOT EXISTS admin_audit (
  id          TEXT PRIMARY KEY,
  actor_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action      TEXT NOT NULL,
  target_id   TEXT,
  note        TEXT,
  created_at  INTEGER NOT NULL
);
-- The audit queue query hits this hardest — newest first, all rows.
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit(created_at DESC);
-- "Everything I did to this user" lookup.
CREATE INDEX IF NOT EXISTS idx_admin_audit_target ON admin_audit(target_id, created_at DESC);
