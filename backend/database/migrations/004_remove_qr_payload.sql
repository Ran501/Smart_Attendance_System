-- QR backup attendance is no longer used by FacePass Bhutan.
ALTER TABLE attendance_sessions DROP COLUMN IF EXISTS qr_payload;
