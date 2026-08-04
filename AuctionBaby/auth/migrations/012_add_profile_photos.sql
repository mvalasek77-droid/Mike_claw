-- Batch U — R2-hosted profile photos.
--
-- One row in `profiles` holds a JSON array of photo entries:
--   [{"id":"<uuid>","key":"photos/<userId>/<uuid>.jpg"}, ...]
--
-- The URL clients see is derived at read time from PHOTOS_PUBLIC_URL + key,
-- so switching the public bucket domain later doesn't require a DB rewrite.
-- Position in the array IS the order — index 0 is the primary photo.
--
-- Photos themselves live in the `PHOTOS` R2 bucket; this column is just the
-- pointer + ordering.
--
-- Apply with:
--   wrangler d1 execute auctionbaby-users --file=migrations/012_add_profile_photos.sql

ALTER TABLE profiles ADD COLUMN photos_json TEXT;
