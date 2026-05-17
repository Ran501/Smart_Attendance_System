-- Teacher GPS anchor for live sessions (students must be within radius_meters)
ALTER TABLE attendance_sessions
  ADD COLUMN IF NOT EXISTS host_latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS host_longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS radius_meters INTEGER DEFAULT 5;
