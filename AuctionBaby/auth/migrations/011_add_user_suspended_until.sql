-- Migration 011 — reversible ban (Batch R).
-- Adds `users.suspended_until`, an epoch-ms cutoff. When set + in the
-- future the user is treated as suspended: handleAppleAuth rejects new
-- sign-ins, handleUpsertMyProfile rejects profile writes, and the matching
-- Worker's handlePlaceBid rejects new bids from OR to that user.
--
-- Existing sessions stay valid up to their normal TTL — this is a
-- soft-ban primitive. For an immediate hard ban, use `DELETE /admin/users/:id`
-- (Batch G). Lift a suspension with `POST /admin/users/:id/unsuspend`.

ALTER TABLE users ADD COLUMN suspended_until INTEGER;
