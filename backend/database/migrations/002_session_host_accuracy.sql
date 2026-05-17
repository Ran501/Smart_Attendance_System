ALTER TABLE attendance_sessions
  ADD COLUMN IF NOT EXISTS host_accuracy DOUBLE PRECISION;
