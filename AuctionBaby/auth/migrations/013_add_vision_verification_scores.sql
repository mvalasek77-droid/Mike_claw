-- Stores only non-biometric numeric outcomes from the on-device Vision check.
-- No selfie, face landmarks, or biometric template leaves the device.
ALTER TABLE users ADD COLUMN verification_selfie_score REAL;
ALTER TABLE users ADD COLUMN verification_face_match_score REAL;
ALTER TABLE users ADD COLUMN verification_liveness_passed INTEGER;
