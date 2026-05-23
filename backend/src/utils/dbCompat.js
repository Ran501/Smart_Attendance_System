/**
 * Works with legacy Neon/Postgres schemas (GPS/Wi-Fi columns present but unused).
 * Attendance is gated by Bluetooth only; geo/wifi DB fields are always false/null.
 */

async function upsertAttendanceRecord(pool, {
  sessionId,
  classId,
  studentId,
  status,
  confidence,
  deviceValid,
  livenessPassed,
  rejectionReason,
  bleVerified,
  bleRssi,
}) {
  const legacySql = `
    INSERT INTO attendance_records
      (session_id, class_id, student_id, status, match_confidence,
       latitude, longitude, geo_valid, wifi_valid, device_valid, liveness_passed,
       rejection_reason)
    VALUES ($1, $2, $3, $4, $5, NULL, NULL, false, false, $6, $7, $8)
    ON CONFLICT (session_id, student_id) DO UPDATE SET
      status = EXCLUDED.status,
      match_confidence = EXCLUDED.match_confidence,
      latitude = NULL,
      longitude = NULL,
      geo_valid = false,
      wifi_valid = false,
      device_valid = EXCLUDED.device_valid,
      liveness_passed = EXCLUDED.liveness_passed,
      rejection_reason = EXCLUDED.rejection_reason,
      updated_at = NOW()`;

  const legacyParams = [
    sessionId,
    classId,
    studentId,
    status,
    confidence,
    deviceValid,
    livenessPassed,
    rejectionReason ?? null,
  ];

  const bleSql = `
    INSERT INTO attendance_records
      (session_id, class_id, student_id, status, match_confidence,
       latitude, longitude, geo_valid, wifi_valid, device_valid, liveness_passed,
       rejection_reason, ble_verified, ble_rssi)
    VALUES ($1, $2, $3, $4, $5, NULL, NULL, false, false, $6, $7, $8, $9, $10)
    ON CONFLICT (session_id, student_id) DO UPDATE SET
      status = EXCLUDED.status,
      match_confidence = EXCLUDED.match_confidence,
      latitude = NULL,
      longitude = NULL,
      geo_valid = false,
      wifi_valid = false,
      device_valid = EXCLUDED.device_valid,
      liveness_passed = EXCLUDED.liveness_passed,
      rejection_reason = EXCLUDED.rejection_reason,
      ble_verified = EXCLUDED.ble_verified,
      ble_rssi = EXCLUDED.ble_rssi,
      updated_at = NOW()`;

  const bleParams = [
    ...legacyParams.slice(0, 8),
    bleVerified === true,
    bleRssi != null ? Number(bleRssi) : null,
  ];

  try {
    await pool.query(bleSql, bleParams);
  } catch (err) {
    if (err.code === '42703') {
      await pool.query(legacySql, legacyParams);
    } else {
      throw err;
    }
  }
}

/**
 * Teacher/admin manual status change (present, absent, medical, official).
 */
async function setAttendanceStatus(pool, {
  sessionId,
  classId,
  studentId,
  recordId,
  status,
  updatedBy,
}) {
  if (recordId) {
    const updateWithBy = `
      UPDATE attendance_records
      SET status = $1, updated_by = $2, updated_at = NOW()
      WHERE id = $3 AND session_id = $4
      RETURNING id, student_id`;
    try {
      const result = await pool.query(updateWithBy, [status, updatedBy, recordId, sessionId]);
      if (result.rowCount > 0) return result.rows[0];
    } catch (err) {
      if (err.code !== '42703') throw err;
      const result = await pool.query(
        `UPDATE attendance_records
         SET status = $1, updated_at = NOW()
         WHERE id = $2 AND session_id = $3
         RETURNING id, student_id`,
        [status, recordId, sessionId],
      );
      if (result.rowCount > 0) return result.rows[0];
    }
  }

  const resolvedStudentId = studentId;
  if (!resolvedStudentId) {
    return null;
  }

  const upsertWithBy = `
    INSERT INTO attendance_records (session_id, class_id, student_id, status, updated_by, updated_at)
    VALUES ($1, $2, $3, $4, $5, NOW())
    ON CONFLICT (session_id, student_id) DO UPDATE SET
      status = EXCLUDED.status,
      updated_by = EXCLUDED.updated_by,
      updated_at = NOW()
    RETURNING id, student_id`;

  try {
    const result = await pool.query(upsertWithBy, [
      sessionId,
      classId,
      resolvedStudentId,
      status,
      updatedBy,
    ]);
    return result.rows[0];
  } catch (err) {
    if (err.code !== '42703') throw err;
    const result = await pool.query(
      `INSERT INTO attendance_records (session_id, class_id, student_id, status, updated_at)
       VALUES ($1, $2, $3, $4, NOW())
       ON CONFLICT (session_id, student_id) DO UPDATE SET
         status = EXCLUDED.status,
         updated_at = NOW()
       RETURNING id, student_id`,
      [sessionId, classId, resolvedStudentId, status],
    );
    return result.rows[0];
  }
}

module.exports = { upsertAttendanceRecord, setAttendanceStatus };
