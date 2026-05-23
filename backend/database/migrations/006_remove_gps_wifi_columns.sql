-- OPTIONAL — do not run unless you want to drop legacy columns manually.
-- The app works with GPS/Wi-Fi columns left in place (unused; Bluetooth only).
-- This file is NOT applied automatically on server start.

-- Remove legacy GPS / Wi-Fi geofencing columns (attendance uses Bluetooth only).

ALTER TABLE classrooms
  DROP COLUMN IF EXISTS latitude,
  DROP COLUMN IF EXISTS longitude,
  DROP COLUMN IF EXISTS radius_meters,
  DROP COLUMN IF EXISTS allowed_wifi_ssid,
  DROP COLUMN IF EXISTS allowed_wifi_bssid,
  DROP COLUMN IF EXISTS allowed_subnet;

ALTER TABLE attendance_sessions
  DROP COLUMN IF EXISTS host_latitude,
  DROP COLUMN IF EXISTS host_longitude,
  DROP COLUMN IF EXISTS host_accuracy,
  DROP COLUMN IF EXISTS radius_meters;

ALTER TABLE attendance_records
  DROP COLUMN IF EXISTS latitude,
  DROP COLUMN IF EXISTS longitude,
  DROP COLUMN IF EXISTS geo_valid,
  DROP COLUMN IF EXISTS wifi_valid;

ALTER TABLE attendance_records
  ADD COLUMN IF NOT EXISTS ble_verified BOOLEAN,
  ADD COLUMN IF NOT EXISTS ble_rssi INTEGER;
